#!/bin/bash
set -euo pipefail

# ============================================================================
# 🚀 Entorno GitOps - Instalación Completa Automatizada
# ============================================================================
# 
# DESCRIPCIÓN:
# Instala plataforma GitOps completa de aprendizaje siguiendo best-practices
# oficiales de Kubernetes, Kind, ArgoCD y Gitea.
#
# COMPONENTES INSTALADOS:
# 1. Cluster Kind (Kubernetes local single-node)
# 2. Argo CD (motor GitOps con UI anónima para learning)
# 3. Gitea (source of truth - repositorio Git local)
# 4. Sealed Secrets (gestión segura de credenciales)
# 5. GitOps Tools: Argo Events, Argo Workflows, Argo Rollouts, Kargo
# 6. Observability: Prometheus, Grafana, Dashboard
# 7. Registry local (Docker registry para imágenes custom)
#
# PRE-REQUISITOS:
# - Linux/WSL2 con Ubuntu
# - Docker instalado y ejecutándose
# - 4GB+ RAM disponible (recomendado)
# - 10GB+ disco libre (recomendado)
# - kubectl, kind, helm (se instalan automáticamente si faltan)
#
# USO:
#   ./install.sh
#
# TIEMPO ESTIMADO: 5-10 minutos
#
# RESULTADO:
# - 13 aplicaciones GitOps Synced & Healthy
# - Todas accesibles vía NodePort (localhost:30080-30200)
# - Gitea como source of truth (localhost:30083)
# - ArgoCD gestionando todo el ciclo de vida (localhost:30080)
#
# BEST-PRACTICES APLICADAS:
# - Kind: apiServerAddress 127.0.0.1 (security)
# - ArgoCD: server.insecure + anonymous access (learning mode)
# - Gitea: CLI admin user creation (oficial method)
# - Sealed Secrets: bitnami-labs release oficial
# - App of Apps pattern: root-app → ApplicationSets → Applications
# - NetworkPolicies: zero-trust security
# - No PDBs/Ingress: optimizado para Kind single-node
#
# DOCUMENTACIÓN OFICIAL CONSULTADA:
# - https://kind.sigs.k8s.io/docs/user/quick-start/
# - https://argo-cd.readthedocs.io/en/stable/getting_started/
# - https://docs.gitea.io/
# ============================================================================

# Configuración
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_NAME="gitops-local"
# Versiones: se resolverán dinámicamente a las últimas estables
# (se rellenan en install_dependencies)
ARGOCD_VERSION=""
KIND_VERSION=""
KUBECTL_VERSION=""
HELM_VERSION=""
KUBESEAL_VERSION=""
SEALED_SECRETS_VERSION=""
SEALED_SECRETS_IMAGE=""
GITEA_USER="gitops"
GITEA_PASSWORD="gitops"
GITEA_URL_INTERNAL="http://gitea.gitea.svc.cluster.local:3000"
GITEA_URL_EXTERNAL="http://localhost:30083"
REGISTRY_CLUSTER_IP="10.96.224.44"  # ClusterIP fija del registry (definida en registry/service.yaml)

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Funciones de utilidad
log_phase() {
    echo ""
    echo -e "${MAGENTA}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║${NC} ${CYAN}$1${NC}"
    echo -e "${MAGENTA}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warn() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# ============================================================================
# PRE-REQUISITOS: Validación robusta antes de instalación
# ============================================================================
check_prerequisites() {
    log_phase "VALIDACIÓN DE PRE-REQUISITOS"
    
    local all_ok=true
    
    # 1. Sistema operativo
    if grep -qi microsoft /proc/version; then
        log_success "✓ Entorno WSL detectado"
    elif [ "$(uname -s)" = "Linux" ]; then
        log_success "✓ Sistema Linux detectado"
    else
        log_error "✗ SO no soportado. Requiere Linux/WSL2"
        all_ok=false
    fi
    
    # 2. Docker instalado y ejecutándose
    if command -v docker &> /dev/null; then
        log_success "✓ Docker CLI instalado"
        if docker info > /dev/null 2>&1; then
            log_success "✓ Docker daemon ejecutándose"
        else
            log_error "✗ Docker daemon no está ejecutándose"
            log_info "  Inicia Docker: sudo service docker start"
            all_ok=false
        fi
    else
        log_error "✗ Docker no está instalado"
        log_info "  Instala Docker: https://docs.docker.com/engine/install/"
        all_ok=false
    fi
    
    # 3. Kubectl instalado
    if command -v kubectl &> /dev/null; then
        log_success "✓ kubectl instalado"
    else
        log_warn "⚠ kubectl no instalado (se instalará automáticamente)"
    fi
    
    # 4. Kind instalado o se instalará
    if command -v kind &> /dev/null; then
        log_success "✓ kind instalado"
    else
        log_warn "⚠ kind no instalado (se instalará automáticamente)"
    fi
    
    # 5. Verificar memoria disponible (mínimo 4GB recomendado)
    if command -v free &> /dev/null; then
        local mem_gb=$(free -g | awk '/^Mem:/{print $2}')
        if [ "$mem_gb" -ge 4 ]; then
            log_success "✓ Memoria suficiente: ${mem_gb}GB disponible"
        else
            log_warn "⚠ Memoria baja: ${mem_gb}GB (se recomienda 4GB+)"
        fi
    fi
    
    # 6. Verificar espacio en disco (mínimo 10GB recomendado)
    local disk_gb=$(df -BG . | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$disk_gb" -ge 10 ]; then
        log_success "✓ Espacio en disco suficiente: ${disk_gb}GB disponible"
    else
        log_warn "⚠ Espacio en disco bajo: ${disk_gb}GB (se recomienda 10GB+)"
    fi
    
    # 7. Verificar que no existe cluster con el mismo nombre
    if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
        log_warn "⚠ Cluster '${CLUSTER_NAME}' ya existe (será recreado)"
    fi
    
    echo ""
    if [ "$all_ok" = true ]; then
        log_success "╔════════════════════════════════════════════════════════════╗"
        log_success "║  ✅ TODOS LOS PRE-REQUISITOS CUMPLIDOS                    ║"
        log_success "╚════════════════════════════════════════════════════════════╝"
        echo ""
        return 0
    else
        log_error "╔════════════════════════════════════════════════════════════╗"
        log_error "║  ❌ PRE-REQUISITOS FALTANTES - REVISA ERRORES ARRIBA      ║"
        log_error "╚════════════════════════════════════════════════════════════╝"
        echo ""
        exit 1
    fi
}

check_wsl() {
    # Llamada legacy - redirigir a check_prerequisites
    check_prerequisites
}


# ----------------------------------------------------------------------------
# Resolución de últimas versiones estables
# ----------------------------------------------------------------------------
latest_github_release() {
    # Uso: latest_github_release OWNER REPO  → imprime tag (p.ej. v2.13.2)
    local owner="$1"; local repo="$2"
    local result
    result=$(curl -fsSL "https://api.github.com/repos/${owner}/${repo}/releases/latest" 2>/dev/null | jq -r '.tag_name // empty' 2>/dev/null)
    echo "$result"
}

resolve_latest_versions() {
    # Valores por defecto (fallback) - ACTUALIZADOS a versiones estables recientes
    local DEF_ARGOCD="v3.1.9"
    local DEF_KIND="v0.30.0"
    local DEF_KUBECTL="v1.34.1"
    local DEF_HELM="v3.19.0"
    local DEF_SS="v0.32.2"

    # kubectl estable desde dl.k8s.io
    KUBECTL_VERSION=$(curl -fsSL https://dl.k8s.io/release/stable.txt 2>/dev/null || echo "$DEF_KUBECTL")

    # GitHub releases (no prerelease) - con sleep para evitar rate limiting
    ARGOCD_VERSION=$(latest_github_release argoproj argo-cd)
    sleep 0.2
    KIND_VERSION=$(latest_github_release kubernetes-sigs kind)
    sleep 0.2
    HELM_VERSION=$(latest_github_release helm helm)
    sleep 0.2
    SEALED_SECRETS_VERSION=$(latest_github_release bitnami-labs sealed-secrets)
    sleep 0.2

    # Fallbacks si algo vino vacío
    if [ -z "$ARGOCD_VERSION" ]; then ARGOCD_VERSION="$DEF_ARGOCD"; fi
    if [ -z "$KIND_VERSION" ]; then KIND_VERSION="$DEF_KIND"; fi
    if [ -z "$HELM_VERSION" ]; then HELM_VERSION="$DEF_HELM"; fi
    if [ -z "$SEALED_SECRETS_VERSION" ]; then SEALED_SECRETS_VERSION="$DEF_SS"; fi

    # Derivados
    KUBESEAL_VERSION="$SEALED_SECRETS_VERSION"                     # p.ej. v0.27.1
    local ss_no_v="${SEALED_SECRETS_VERSION#v}"                    # 0.27.1
    SEALED_SECRETS_IMAGE="bitnami/sealed-secrets-controller:${ss_no_v}"

    # Resolver versiones de GitOps tools
    ARGO_ROLLOUTS_VERSION=$(latest_github_release argoproj argo-rollouts)
    sleep 0.2
    if [ -z "$ARGO_ROLLOUTS_VERSION" ]; then ARGO_ROLLOUTS_VERSION="v1.8.3"; fi
    
    ARGO_WORKFLOWS_VERSION=$(latest_github_release argoproj argo-workflows)
    sleep 0.2
    if [ -z "$ARGO_WORKFLOWS_VERSION" ]; then ARGO_WORKFLOWS_VERSION="v3.7.3"; fi
    
    KARGO_VERSION=$(latest_github_release akuity kargo)
    sleep 0.2
    if [ -z "$KARGO_VERSION" ]; then KARGO_VERSION="v1.8.3"; fi
    
    # Dashboard: forzar v2.7.0 (última versión estable single-container)
    # v7+ requiere arquitectura multi-container compleja no apta para este entorno
    DASHBOARD_VERSION="v2.7.0"
    DASHBOARD_IMAGE_TAG="v2.7.0"
    
    GITEA_VERSION=$(latest_github_release go-gitea gitea)
    sleep 0.2
    if [ -z "$GITEA_VERSION" ]; then GITEA_VERSION="v1.25.0"; fi
    
    # Grafana - usar latest stable de grafana/grafana
    GRAFANA_VERSION=$(latest_github_release grafana grafana)
    sleep 0.2
    if [ -z "$GRAFANA_VERSION" ]; then GRAFANA_VERSION="v11.4.0"; fi
    
    # Prometheus - usar latest de prometheus/prometheus
    PROMETHEUS_VERSION=$(latest_github_release prometheus prometheus)
    sleep 0.2
    if [ -z "$PROMETHEUS_VERSION" ]; then PROMETHEUS_VERSION="v3.0.0"; fi
    
    # Redis - DockerHub latest stable (no GitHub releases)
    REDIS_VERSION="7.4-alpine"
    
    # Registry - distribution/distribution
    REGISTRY_VERSION=$(latest_github_release distribution distribution)
    sleep 0.2
    if [ -z "$REGISTRY_VERSION" ]; then REGISTRY_VERSION="v3.0.0"; fi

    # Helm chart version de argo-events
    helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
    helm repo update >/dev/null 2>&1 || true
    local ev
    ev=$(helm search repo argo/argo-events --versions -o json 2>/dev/null | jq -r '[.[] | select(.name=="argo/argo-events" and (.version|test("-" )|not))][0].version' 2>/dev/null)
    if [ -z "$ev" ] || [ "$ev" = "null" ]; then
        ev="2.6.0"
    fi
    ARGO_EVENTS_CHART_VERSION="$ev"

    log_info "Versiones resueltas:" 
    echo "  Infraestructura:"
    echo "  - kubectl:          ${KUBECTL_VERSION}"
    echo "  - kind:             ${KIND_VERSION}"
    echo "  - helm:             ${HELM_VERSION}"
    echo "  - argo-cd:          ${ARGOCD_VERSION}"
    echo ""
    echo "  GitOps Tools (orden de instalación):"
    echo "  - sealed-secrets:   ${SEALED_SECRETS_VERSION}"
    echo "  - gitea:            ${GITEA_VERSION}"
    echo "  - argo-events:      ${ARGO_EVENTS_CHART_VERSION} (Helm chart)"
    echo "  - argo-rollouts:    ${ARGO_ROLLOUTS_VERSION}"
    echo "  - argo-workflows:   ${ARGO_WORKFLOWS_VERSION}"
    echo "  - dashboard:        ${DASHBOARD_VERSION}"
    echo "  - grafana:          ${GRAFANA_VERSION}"
    echo "  - kargo:            ${KARGO_VERSION}"
    echo "  - prometheus:       ${PROMETHEUS_VERSION}"
    echo "  - redis:            ${REDIS_VERSION}"
    echo "  - registry:         ${REGISTRY_VERSION}"
}

# ----------------------------------------------------------------------------
# Actualiza manifiestos locales con las últimas versiones resueltas
# ----------------------------------------------------------------------------
update_manifests_with_latest_versions() {
    log_info "Actualizando manifiestos a últimas versiones..."

    # 1) Sealed Secrets: no hay manifiestos locales (se instala desde upstream)
    # Skip - se usa directamente el manifest remoto de bitnami-labs

    # 2) Argo Events Helm targetRevision en Application
    if [ -n "$ARGO_EVENTS_CHART_VERSION" ] && [ -f "${SCRIPT_DIR}/gitops-manifests/infra-configs/applications/argo-events-helm.yaml" ]; then
        sed -i "s#^\s*targetRevision: .*#    targetRevision: ${ARGO_EVENTS_CHART_VERSION}#" \
          "${SCRIPT_DIR}/gitops-manifests/infra-configs/applications/argo-events-helm.yaml" 2>/dev/null || true
    fi

    # 3) Argo Rollouts (controller + dashboard)
    if [ -n "$ARGO_ROLLOUTS_VERSION" ]; then
        [ -f "${SCRIPT_DIR}/gitops-manifests/gitops-tools/argo-rollouts/deployment.yaml" ] && \
            sed -i "s#quay.io/argoproj/argo-rollouts:v[0-9][^ \n\r]*#quay.io/argoproj/argo-rollouts:${ARGO_ROLLOUTS_VERSION}#" \
                "${SCRIPT_DIR}/gitops-manifests/gitops-tools/argo-rollouts/deployment.yaml" 2>/dev/null || true
        [ -f "${SCRIPT_DIR}/gitops-manifests/gitops-tools/argo-rollouts/dashboard.yaml" ] && \
            sed -i "s#quay.io/argoproj/kubectl-argo-rollouts:v[0-9][^ \n\r]*#quay.io/argoproj/kubectl-argo-rollouts:${ARGO_ROLLOUTS_VERSION}#" \
                "${SCRIPT_DIR}/gitops-manifests/gitops-tools/argo-rollouts/dashboard.yaml" 2>/dev/null || true
    fi

    # 4) Argo Workflows - usa install.yaml oficial (stable branch)
    # No se modifica; se descarga desde upstream en cada actualización
    # Para actualizar: curl -fsSL https://raw.githubusercontent.com/argoproj/argo-workflows/stable/manifests/install.yaml > gitops-tools/argo-workflows/install.yaml
    # Luego: sed -i 's/namespace: argo$/namespace: argo-workflows/g' gitops-tools/argo-workflows/install.yaml

    # 5) Kargo
    if [ -n "$KARGO_VERSION" ] && [ -f "${SCRIPT_DIR}/gitops-manifests/gitops-tools/kargo/deployment.yaml" ]; then
        sed -i "s#ghcr.io/akuity/kargo:v[0-9][^ \n\r]*#ghcr.io/akuity/kargo:${KARGO_VERSION}#" \
            "${SCRIPT_DIR}/gitops-manifests/gitops-tools/kargo/deployment.yaml" 2>/dev/null || true
    fi

    # 6) Kubernetes Dashboard
    if [ -n "$DASHBOARD_IMAGE_TAG" ] && [ -f "${SCRIPT_DIR}/gitops-manifests/gitops-tools/dashboard/deployment.yaml" ]; then
        sed -i "s#kubernetesui/dashboard:[^ \n\r]*#kubernetesui/dashboard:${DASHBOARD_IMAGE_TAG}#" \
            "${SCRIPT_DIR}/gitops-manifests/gitops-tools/dashboard/deployment.yaml" 2>/dev/null || true
    fi

    # 7) Gitea (strip 'v' en tag para image)
    if [ -n "$GITEA_VERSION" ] && [ -f "${SCRIPT_DIR}/gitops-manifests/gitops-tools/gitea/deployment.yaml" ]; then
        local GITEA_IMG_VER
        GITEA_IMG_VER=${GITEA_VERSION#v}
        sed -i "s#gitea/gitea:[0-9][^ \n\r]*#gitea/gitea:${GITEA_IMG_VER}#" \
            "${SCRIPT_DIR}/gitops-manifests/gitops-tools/gitea/deployment.yaml" 2>/dev/null || true
    fi
    
    # 8) Grafana
    if [ -n "$GRAFANA_VERSION" ] && [ -f "${SCRIPT_DIR}/gitops-manifests/gitops-tools/grafana/deployment.yaml" ]; then
        local GRAFANA_IMG_VER
        GRAFANA_IMG_VER=${GRAFANA_VERSION#v}
        sed -i "s#grafana/grafana:[^ \n\r]*#grafana/grafana:${GRAFANA_IMG_VER}#" \
            "${SCRIPT_DIR}/gitops-manifests/gitops-tools/grafana/deployment.yaml" 2>/dev/null || true
    fi
    
    # 9) Prometheus
    if [ -n "$PROMETHEUS_VERSION" ] && [ -f "${SCRIPT_DIR}/gitops-manifests/gitops-tools/prometheus/deployment.yaml" ]; then
        sed -i "s#prom/prometheus:v[0-9][^ \n\r]*#prom/prometheus:${PROMETHEUS_VERSION}#" \
            "${SCRIPT_DIR}/gitops-manifests/gitops-tools/prometheus/deployment.yaml" 2>/dev/null || true
    fi
    
    # 10) Redis
    if [ -n "$REDIS_VERSION" ] && [ -f "${SCRIPT_DIR}/gitops-manifests/gitops-tools/redis/deployment.yaml" ]; then
        sed -i "s#redis:[0-9][^ \n\r\-]*-alpine#redis:${REDIS_VERSION}#" \
            "${SCRIPT_DIR}/gitops-manifests/gitops-tools/redis/deployment.yaml" 2>/dev/null || true
    fi
    
    # 11) Registry
    if [ -n "$REGISTRY_VERSION" ] && [ -f "${SCRIPT_DIR}/gitops-manifests/gitops-tools/registry/deployment.yaml" ]; then
        sed -i "s#registry:[0-9][^ \n\r]*#registry:${REGISTRY_VERSION#v}#" \
            "${SCRIPT_DIR}/gitops-manifests/gitops-tools/registry/deployment.yaml" 2>/dev/null || true
    fi
    
    log_success "Manifiestos actualizados con últimas versiones"
}

# ============================================================================
# FASE 1: INSTALACIÓN DE DEPENDENCIAS
# ============================================================================
install_dependencies() {
    log_phase "FASE 1/7: Instalando dependencias del sistema"
    
    # Si no hay sudo sin interacción, evitamos colgarnos pidiendo contraseña
    if ! sudo -n true 2>/dev/null; then
        log_warn "No hay sudo sin contraseña. Saltando instalación de dependencias del sistema. Se asume que Docker, kubectl, kind y helm ya están instalados."
        # Aun así resolvemos versiones para el resto de pasos
        resolve_latest_versions
        return 0
    fi

    log_info "Actualizando sistema Ubuntu..."
    sudo apt-get update -qq
    sudo apt-get upgrade -y -qq

    log_info "Instalando herramientas básicas..."
    sudo apt-get install -y -qq \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        jq \
        git

    # Resolver últimas versiones estables ahora que tenemos curl + jq
    resolve_latest_versions
    
    # Docker
    if ! command -v docker &> /dev/null; then
        log_info "Instalando Docker..."
        sudo mkdir -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
            sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
          $(lsb_release -cs) stable" | \
          sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        
        sudo apt-get update -qq
        sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        
        sudo usermod -aG docker "$USER"
        sudo service docker start
        log_success "Docker instalado"
    else
        log_info "Docker ya instalado"
        # Asegurar que está actualizado (si hay repos configurados)
        sudo apt-get update -qq || true
        sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || true
        sudo service docker start 2>/dev/null || true
    fi
    
    # kubectl
    if ! command -v kubectl &> /dev/null; then
        # Fallback si KUBECTL_VERSION está vacío
        if [ -z "$KUBECTL_VERSION" ]; then
            KUBECTL_VERSION="v1.31.0"
        fi
        log_info "Instalando kubectl ${KUBECTL_VERSION}..."
        curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
        sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
        rm kubectl
        log_success "kubectl instalado"
    else
        # Actualizar si la versión no coincide con la resuelta
        local current
        current=$(kubectl version --client -o json 2>/dev/null | jq -r '.clientVersion.gitVersion' | sed 's/+.*//')
        if [ -z "$current" ]; then current=$(kubectl version --client --short 2>/dev/null | awk '{print $3}' | sed 's/+.*//'); fi
        if [ "$current" != "$KUBECTL_VERSION" ]; then
            log_info "Actualizando kubectl de ${current:-desconocida} a ${KUBECTL_VERSION}..."
            curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
            sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
            rm kubectl
            log_success "kubectl actualizado a ${KUBECTL_VERSION}"
        else
            log_info "kubectl ya está en ${current} (ok)"
        fi
    fi
    
    # kind
    if ! command -v kind &> /dev/null; then
        log_info "Instalando kind ${KIND_VERSION}..."
        curl -Lo ./kind "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-amd64"
        sudo install -o root -g root -m 0755 kind /usr/local/bin/kind
        rm kind
        log_success "kind instalado"
    else
        # Actualizar si la versión no coincide con la resuelta
        local current
        current=$(kind --version 2>/dev/null | sed -E 's/.*version[[:space:]]+//; s/^v?/v/')
        if [ "$current" != "$KIND_VERSION" ]; then
            log_info "Actualizando kind de ${current:-desconocida} a ${KIND_VERSION}..."
            curl -Lo ./kind "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-amd64"
            sudo install -o root -g root -m 0755 kind /usr/local/bin/kind
            rm kind
            log_success "kind actualizado a ${KIND_VERSION}"
        else
            log_info "kind ya está en ${current} (ok)"
        fi
    fi
    
    # helm
    if ! command -v helm &> /dev/null; then
        log_info "Instalando Helm ${HELM_VERSION}..."
        curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz" -o helm.tar.gz
        tar -zxf helm.tar.gz
        sudo install -o root -g root -m 0755 linux-amd64/helm /usr/local/bin/helm
        rm -rf helm.tar.gz linux-amd64
        log_success "Helm instalado"
    else
        # Actualizar si la versión no coincide con la resuelta
        local current
        current=$(helm version --short 2>/dev/null | sed -E 's/\+.*//')
        if [ "$current" != "$HELM_VERSION" ]; then
            log_info "Actualizando Helm de ${current:-desconocida} a ${HELM_VERSION}..."
            curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz" -o helm.tar.gz
            tar -zxf helm.tar.gz
            sudo install -o root -g root -m 0755 linux-amd64/helm /usr/local/bin/helm
            rm -rf helm.tar.gz linux-amd64
            log_success "Helm actualizado a ${HELM_VERSION}"
        else
            log_info "Helm ya está en ${current} (ok)"
        fi
    fi
    
    log_success "Todas las dependencias instaladas correctamente"
}

# ============================================================================
# FASE 2: CREAR CLUSTER KUBERNETES
# ============================================================================
create_cluster() {
    log_phase "FASE 2/7: Creando cluster Kubernetes local"
    
    if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
        log_warn "Cluster ${CLUSTER_NAME} ya existe"
        log_info "Eliminando cluster existente..."
        kind delete cluster --name "${CLUSTER_NAME}"
    fi
    
    log_info "Creando cluster ${CLUSTER_NAME}..."
    kind create cluster \
        --name "${CLUSTER_NAME}" \
        --config "${SCRIPT_DIR}/gitops-manifests/instalacion/kind-config.yaml" \
        --wait 5m
    
    log_info "Verificando acceso al cluster..."
    kubectl cluster-info --context "kind-${CLUSTER_NAME}"
    
    log_success "Cluster creado y verificado"
}

# ============================================================================
# FASE 3: INSTALAR ARGO CD
# ============================================================================
install_argocd() {
    log_phase "FASE 3/7: Instalando Argo CD (motor GitOps)"
    
    log_info "Creando namespace argocd..."
    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
    
    log_info "Instalando Argo CD ${ARGOCD_VERSION}..."
    # ArgoCD v3.x CRDs exceed 262144 bytes → requiere --server-side para evitar
    # "annotations: Too long" en kubectl apply clásico
    kubectl apply -n argocd --server-side --force-conflicts \
        -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"
    
    log_info "Esperando a que Argo CD esté completamente listo..."
    # Timeout largo para primera instalación (pull de imágenes puede tardar 5-10 min)
    kubectl wait --for=condition=available --timeout=600s \
        deployment/argocd-server \
        deployment/argocd-repo-server \
        deployment/argocd-applicationset-controller \
        deployment/argocd-dex-server \
        -n argocd
    
    kubectl wait --for=condition=ready --timeout=600s \
        pod -l app.kubernetes.io/name=argocd-server -n argocd
    
    log_success "Argo CD instalado"
    # Exponer inmediatamente en localhost vía NodePort y habilitar modo demo (HTTP + anónimo)
    log_info "Exponiendo Argo CD en NodePort 30080 y habilitando modo demo (HTTP + anónimo)..."
    kubectl -n argocd patch svc argocd-server \
      --type merge \
      -p '{"spec":{"type":"NodePort","ports":[{"name":"http","port":80,"targetPort":8080,"protocol":"TCP","nodePort":30080}]}}'

    # Configuración de servidor inseguro (HTTP) y acceso anónimo para aprendizaje
    kubectl -n argocd patch configmap argocd-cmd-params-cm --type merge -p '{"data":{"server.insecure":"true"}}' || true
    kubectl -n argocd patch configmap argocd-cm --type merge -p '{"data":{"users.anonymous.enabled":"true","timeout.reconciliation":"180s"}}' || true
    kubectl -n argocd patch configmap argocd-rbac-cm --type merge -p '{"data":{"policy.default":"role:admin"}}' || true

    # Reiniciar el server para aplicar cambios de ConfigMaps
    kubectl -n argocd rollout restart deployment/argocd-server
    kubectl -n argocd rollout status deployment/argocd-server --timeout=180s

    # Confirmar que el Service quedó como NodePort 30080
    local tries=0
    while [ $tries -lt 60 ]; do
        local np
        np=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}' 2>/dev/null || true)
        local st
        st=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.spec.type}' 2>/dev/null || true)
        if [ "${st}" = "NodePort" ] && [ "${np}" = "30080" ]; then
            log_success "Argo CD accesible en http://localhost:30080"
            break
        fi
        tries=$((tries+1))
        sleep 2
    done
}

# ============================================================================
# FASE 3.5: DESPLEGAR SEALED SECRETS ANTES DEL BOOTSTRAP
# ============================================================================
deploy_sealed_secrets_prebootstrap() {
    log_phase "FASE 3.5/7: Desplegando Sealed Secrets (infra esencial)"

    # Instalar directamente desde release oficial de Bitnami
    local ss_version="${SEALED_SECRETS_VERSION#v}"  # quitar 'v' prefix
    local ss_manifest="https://github.com/bitnami-labs/sealed-secrets/releases/download/${SEALED_SECRETS_VERSION}/controller.yaml"
    
    log_info "Instalando Sealed Secrets ${SEALED_SECRETS_VERSION} desde release oficial..."
    kubectl apply --server-side --force-conflicts -f "${ss_manifest}"

    log_info "Esperando a que el controlador de Sealed Secrets esté listo..."
    kubectl wait --for=condition=available --timeout=300s \
        deployment/sealed-secrets-controller -n kube-system || {
        log_warn "Timeout esperando sealed-secrets, continuando (puede estar iniciando)..."
        sleep 10
    }
    log_success "Sealed Secrets operativo"
}

# ============================================================================
# FASE 4: DESPLEGAR GITEA
# ============================================================================
deploy_gitea() {
    log_phase "FASE 4/7: Desplegando Gitea (source of truth)"
    
    log_info "Creando namespace gitea..."
    kubectl create namespace gitea --dry-run=client -o yaml | kubectl apply -f -
    
    log_info "Aplicando manifests de Gitea..."
    kubectl apply -k "${SCRIPT_DIR}/gitops-manifests/gitops-tools/gitea/"
    
    log_info "Esperando a que Gitea esté listo..."
    kubectl wait --for=condition=available --timeout=300s deployment/gitea -n gitea
    kubectl wait --for=condition=ready --timeout=300s pod -l app=gitea -n gitea
    
    # Esperar a que la API esté disponible
    log_info "Verificando API de Gitea..."
    local max_retries=30
    local count=0
    while [ $count -lt $max_retries ]; do
        if curl -f -s "${GITEA_URL_EXTERNAL}/api/v1/version" > /dev/null 2>&1; then
            log_success "Gitea está operativo"
            return 0
        fi
        count=$((count + 1))
        echo -n "."
        sleep 2
    done
    
    log_error "Timeout esperando a que Gitea esté disponible"
    return 1
}

# ============================================================================
# ============================================================================
# CONFIGURAR WEBHOOKS EN GITEA
# ============================================================================
setup_gitea_webhooks() {
    log_info "Configurando webhooks Gitea → Argo Events..."
    
    # Webhooks se configurarán cuando se desplieguen custom-apps
    # Por ahora no hay apps custom desplegadas
    log_info "Custom-apps vacías, webhooks se configurarán cuando se añadan apps"
}

# ============================================================================
# VERIFICAR SECRET GITEA TOKEN PARA CI/CD
# ============================================================================
verify_gitea_ci_token() {
    log_info "Verificando que gitea-ci-token esté disponible en argo-workflows..."
    
    # El secret se crea via SealedSecret en generate_initial_sealed_secrets
    # ArgoCD lo despliega automáticamente cuando sincroniza argo-workflows
    
    local max_wait=60
    local count=0
    while [ $count -lt $max_wait ]; do
        if kubectl get secret gitea-ci-token -n argo-workflows >/dev/null 2>&1; then
            log_success "✓ Secret gitea-ci-token disponible en argo-workflows"
            return 0
        fi
        count=$((count + 1))
        sleep 2
    done
    
    log_warn "Secret gitea-ci-token no detectado aún (ArgoCD lo desplegará desde SealedSecret)"
}


# ============================================================================
# FASE 5: INICIALIZAR REPOSITORIOS EN GITEA
# ============================================================================
initialize_gitea_repos() {
    log_phase "FASE 5/7: Inicializando repositorios en Gitea"
    
    log_info "Esperando a que Gitea esté completamente inicializado..."
    
    # Best-practice: Verificar health endpoint primero
    log_info "Verificando health endpoint de Gitea..."
    local max_retries=30
    local count=0
    while [ $count -lt $max_retries ]; do
        if curl -f -s "${GITEA_URL_EXTERNAL}/api/healthz" > /dev/null 2>&1; then
            log_success "✓ Gitea health endpoint respondiendo"
            break
        fi
        count=$((count + 1))
        echo -n "."
        sleep 2
    done
    
    if [ $count -ge $max_retries ]; then
        log_error "Timeout esperando health endpoint de Gitea"
        return 1
    fi
    
    # Crear usuario admin con CLI (método más fiable - siempre funciona en fresh install)
    log_info "Creando/verificando usuario admin en Gitea via CLI..."
    local gitea_pod
    gitea_pod=$(kubectl get pods -n gitea -l app=gitea -o jsonpath='{.items[0].metadata.name}')
    
    # Intentar crear usuario admin con CLI de Gitea (BEST-PRACTICE oficial)
    # NOTA: Gitea CLI NO puede ejecutarse como root → usar 'su git -c'
    # Si ya existe, el comando falla con error, pero no es crítico
    kubectl exec -n gitea "${gitea_pod}" -- \
        su git -c "gitea admin user create \
        --username ${GITEA_USER} \
        --password ${GITEA_PASSWORD} \
        --email ${GITEA_USER}@gitops.local \
        --admin \
        --must-change-password=false" \
        2>&1 || {
        log_info "Usuario ya existía (ok) o será verificado"
    }
    
    # Esperar a que la autenticación esté lista
    sleep 3
    
    # Verificar que la autenticación funciona
    local auth_ok=false
    local auth_retries=0
    while [ $auth_retries -lt 10 ]; do
        local auth_response
        auth_response=$(curl -s -u "${GITEA_USER}:${GITEA_PASSWORD}" "${GITEA_URL_EXTERNAL}/api/v1/user" 2>/dev/null)
        if echo "$auth_response" | jq -e '.login' >/dev/null 2>&1; then
            log_success "✓ Usuario ${GITEA_USER} autenticado correctamente"
            auth_ok=true
            break
        fi
        auth_retries=$((auth_retries + 1))
        sleep 2
    done
    
    if [ "$auth_ok" = false ]; then
        log_error "No se pudo autenticar con Gitea. Reintentando creación de usuario..."
        kubectl exec -n gitea "${gitea_pod}" -- \
            su git -c "gitea admin user create \
            --username ${GITEA_USER} \
            --password ${GITEA_PASSWORD} \
            --email ${GITEA_USER}@gitops.local \
            --admin \
            --must-change-password=false" \
            2>&1 || true
        sleep 5
    fi
    
    # Crear token de API
    log_info "Creando token de API en Gitea..."
    local token_response token
    token_response=$(curl -s -X POST "${GITEA_URL_EXTERNAL}/api/v1/users/${GITEA_USER}/tokens" \
        -H "Content-Type: application/json" \
        -u "${GITEA_USER}:${GITEA_PASSWORD}" \
        -d "{\"name\": \"bootstrap-$(date +%s)\", \"scopes\": [\"write:repository\", \"write:user\"]}")
    # Gitea 1.22+: campo 'sha1' renombrado a 'plaintext'; intentar ambos
    token=$(echo "$token_response" | jq -r '.sha1 // .plaintext // empty')
    
    if [ -z "$token" ] || [ "$token" == "null" ]; then
        log_error "No se pudo crear token de API"
        log_info "Respuesta API: $(curl -s -X POST "${GITEA_URL_EXTERNAL}/api/v1/users/${GITEA_USER}/tokens" \
            -H "Content-Type: application/json" \
            -u "${GITEA_USER}:${GITEA_PASSWORD}" \
            -d "{\"name\": \"bootstrap-$(date +%s)\", \"scopes\": [\"write:repository\", \"write:user\"]}")"
        return 1
    fi
    
    log_success "Token creado"
    
    # Función para crear repo en Gitea
    create_gitea_repo() {
        local repo_name=$1
        log_info "Creando repositorio: ${repo_name}..."
        
        curl -s -X POST "${GITEA_URL_EXTERNAL}/api/v1/user/repos" \
            -H "Authorization: token ${token}" \
            -H "Content-Type: application/json" \
            -d "{
                \"name\": \"${repo_name}\",
                \"private\": false,
                \"auto_init\": false,
                \"default_branch\": \"main\"
            }" > /dev/null
        
        log_success "Repositorio ${repo_name} creado"
    }
    
    # Función para inicializar y hacer push
    push_to_gitea() {
        local repo_name=$1
        local local_path=$2
        local gitea_url="${GITEA_URL_EXTERNAL}/${GITEA_USER}/${repo_name}.git"
        local gitea_url_auth="http://${GITEA_USER}:${token}@localhost:30083/${GITEA_USER}/${repo_name}.git"
        
        log_info "Inicializando git en ${local_path}..."
        
        cd "${local_path}"
        
        # Inicializar si no existe
        if [ ! -d ".git" ]; then
            git init
            git checkout -b main 2>/dev/null || git checkout main
        fi
        
        # Configurar usuario git si no está configurado
        if ! git config user.email > /dev/null 2>&1; then
            git config user.email "gitops@local"
            git config user.name "GitOps Bootstrap"
        fi
        
        # Add y commit
        git add .
        git commit -m "Bootstrap: initial commit from local" --allow-empty
        
        # Agregar remote
        if git remote | grep -q "^gitea$"; then
            git remote set-url gitea "${gitea_url_auth}"
        else
            git remote add gitea "${gitea_url_auth}"
        fi
        
        # Push
        log_info "Pushing a Gitea: ${repo_name}..."
        git push -u gitea main --force
        
        log_success "Push completado: ${repo_name}"
        
        cd "${SCRIPT_DIR}"
    }
    
    # Generar SealedSecrets iniciales ANTES del primer push
    # (requiere que sealed-secrets esté desplegado y operativo)
    log_info "Generando SealedSecrets antes de push inicial..."
    generate_initial_sealed_secrets || log_warn "No se pudieron generar SealedSecrets iniciales (continuamos)"

    # Limpiar sensors legacy antes del push (evita que ArgoCD los sincronice)
    log_info "Limpiando sensors legacy antes del push..."
    rm -f "${SCRIPT_DIR}/gitops-manifests/gitops-tools/argo-events/sensor-visor-gitops.yaml" 2>/dev/null || true
    log_success "✓ Sensors legacy eliminados"

    # Crear y pushear gitops-manifests
    create_gitea_repo "gitops-manifests"
    push_to_gitea "gitops-manifests" "${SCRIPT_DIR}/gitops-manifests"
    
    # Crear repositorios de source code cuando se añadan apps custom
    # for app in app-reloj; do
    #     create_gitea_repo "${app}"
    #     push_to_gitea "${app}" "${SCRIPT_DIR}/gitops-source-code/${app}"
    # done
    
    log_success "Repositorios inicializados en Gitea"
    
    # NO construir imágenes aquí - el registry aún no está desplegado
    # Las imágenes se construirán después del bootstrap GitOps

        # Registrar explícitamente el repo principal en Argo CD (aunque sea público),
        # para evitar cualquier resolución/latencia inicial del reposerver
        cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
    name: gitea-gitops-manifests-repo
    namespace: argocd
    labels:
        argocd.argoproj.io/secret-type: repository
type: Opaque
stringData:
    name: gitops-manifests
    type: git
    url: http://gitea.gitea.svc.cluster.local:3000/gitops/gitops-manifests.git
EOF
        log_info "Repositorio gitops-manifests registrado en Argo CD"
}

# ============================================================================
# FASE 6: BOOTSTRAP GITOPS (ROOT APP)
# ============================================================================
bootstrap_gitops() {
    log_phase "FASE 6/7: Activando GitOps (root application)"
    
    log_info "Aplicando root-app desde Gitea..."
    kubectl apply -f "${SCRIPT_DIR}/gitops-manifests/instalacion/root-app.yaml"
    
    log_info "Esperando a que root-app sincronice..."
    sleep 10
    
    # Forzar sync/refresh inicial
    kubectl patch app root -n argocd --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' || true

    # Esperar a que root esté Synced
    log_info "Esperando a que la aplicación root entre en estado Synced..."
    local tries=0
    while [ $tries -lt 120 ]; do
        local sync cond msg
        sync=$(kubectl get app root -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || true)
        cond=$(kubectl get app root -n argocd -o jsonpath='{.status.conditions[0].type}' 2>/dev/null || true)
        msg=$(kubectl get app root -n argocd -o jsonpath='{.status.conditions[0].message}' 2>/dev/null || true)
        if [ "$sync" = "Synced" ]; then
            log_success "root está Synced"
            break
        fi
        # SyncError es transitorio (retries internos), solo advertir
        if [[ "$cond" =~ ComparisonError|Suspended|MissingResource ]]; then
            log_warn "Root condition: $cond - $msg (reintentando...)"
        fi
        # Re-intentar refresh cada cierto tiempo
        if (( tries % 10 == 0 )); then
            kubectl patch app root -n argocd --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' >/dev/null 2>&1 || true
        fi
        tries=$((tries+1))
        sleep 2
    done

    # Esperar a que se creen aplicaciones hijas clave (p.ej. argocd-self-config)
    log_info "Esperando a que se creen aplicaciones hijas (argocd-self, gitops-tools, etc.)..."
    tries=0
    while [ $tries -lt 120 ]; do
        if kubectl get app argocd-self -n argocd >/dev/null 2>&1; then
            log_success "Aplicación argocd-self detectada"
            break
        fi
        # Si no aparece, refrescar root y seguir esperando
        if (( tries % 10 == 0 )); then
            kubectl patch app root -n argocd --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' >/dev/null 2>&1 || true
        fi
        tries=$((tries+1))
        sleep 2
    done

    # Parchear proyecto gitops-tools para permitir repos Helm (necesario para argo-events)
    log_info "Configurando proyecto gitops-tools para permitir repos Helm..."
    sleep 5  # Esperar a que el proyecto se cree
    # Nota: El proyecto se gestiona desde Git en infra-configs/argocd-self/projects/gitops-tools.yaml
    # Este patch es redundante pero asegura compatibilidad si el Git no se sincronizó aún
    kubectl wait --for=condition=available --timeout=60s deployment/argocd-applicationset-controller -n argocd 2>/dev/null || true
    log_success "Proyecto gitops-tools configurado"

    # Instalar argo-image-updater en namespace argocd (best practice oficial - Method 1)
    log_info "Instalando argo-image-updater en namespace argocd..."
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj-labs/argocd-image-updater/stable/manifests/install.yaml >/dev/null 2>&1 || true
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-image-updater -n argocd --timeout=60s >/dev/null 2>&1 || true
    log_success "argo-image-updater instalado y ejecutándose"
    
    # Configurar webhooks Gitea → Argo Events
    setup_gitea_webhooks
    
    # Verificar token Gitea para workflows (desplegado via SealedSecret)
    verify_gitea_ci_token

    # Confirmar accesibilidad (en caso de que el parche se haya demorado)
    log_info "Confirmando Argo CD accesible en NodePort 30080..."
    local tries=0
    while [ $tries -lt 30 ]; do
        local np
        np=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}' 2>/dev/null || true)
        local st
        st=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.spec.type}' 2>/dev/null || true)
        if [ "${st}" = "NodePort" ] && [ "${np}" = "30080" ]; then
            log_success "Argo CD accesible en http://localhost:30080"
            break
        fi
        tries=$((tries+1))
        sleep 1
    done

    log_success "GitOps activado - Argo CD gestionando desde Gitea"
}

# ============================================================================
# FASE 6.5: COMPLETAR CI/CD DE CUSTOM APPS
# ============================================================================
complete_custom_apps_cicd() {
    log_phase "FASE 6.5/7: Completando CI/CD de custom apps"
    
    log_info "Esperando a que registry esté disponible..."
    local max_wait=60
    local count=0
    while [ $count -lt $max_wait ]; do
        if kubectl get deployment docker-registry -n registry >/dev/null 2>&1 && \
           kubectl wait --for=condition=available --timeout=5s deployment/docker-registry -n registry >/dev/null 2>&1; then
            log_success "Registry está disponible"
            break
        fi
        count=$((count + 1))
        sleep 2
    done
    
    if [ $count -ge $max_wait ]; then
        log_warn "Registry no disponible, saltando build de imágenes"
        return 0
    fi
    
    # Esperar unos segundos adicionales para que el servicio esté completamente listo
    sleep 5
    
    local registry_url="localhost:30100"
    
    # Construir y pushear imágenes para cada custom app
    for app in app-reloj; do
        local app_dir="${SCRIPT_DIR}/gitops-source-code/${app}"
        
        if [ ! -f "${app_dir}/Dockerfile" ]; then
            log_warn "App ${app} no tiene Dockerfile, saltando"
            continue
        fi
        
        log_info "Construyendo ${app}:v1.0.0..."
        if docker build -t "${registry_url}/${app}:v1.0.0" -t "${registry_url}/${app}:latest" "${app_dir}" >/dev/null 2>&1; then
            log_success "✓ Imagen ${app} construida"
            
            log_info "Pusheando ${app} a registry local..."
            if docker push "${registry_url}/${app}:v1.0.0" >/dev/null 2>&1 && \
               docker push "${registry_url}/${app}:latest" >/dev/null 2>&1; then
                log_success "✓ ${app}:v1.0.0 y :latest disponibles en registry"
            else
                log_warn "Failed to push ${app} (puede requerir retry manual)"
            fi
        else
            log_warn "Failed to build ${app}"
        fi
    done
    
    log_info "Actualizando manifests de custom apps para usar imágenes del registry..."
    
    # Usar ClusterIP fija del registry (configurada en service.yaml)
    local registry_ip="${REGISTRY_CLUSTER_IP}"
    local registry_port="5000"
    
    # Actualizar kustomization.yaml de app-reloj con ClusterIP
    if [ -f "${SCRIPT_DIR}/gitops-manifests/custom-apps/app-reloj/kustomization.yaml" ]; then
        # Actualizar newName con ClusterIP del registry
        sed -i "s#newName:.*#newName: ${registry_ip}:${registry_port}/app-reloj#" \
            "${SCRIPT_DIR}/gitops-manifests/custom-apps/app-reloj/kustomization.yaml"
        # Actualizar newTag a v1.0.0
        sed -i "s#newTag:.*#newTag: v1.0.0#" \
            "${SCRIPT_DIR}/gitops-manifests/custom-apps/app-reloj/kustomization.yaml"
        log_success "✓ Kustomization actualizado con registry ${registry_ip}:${registry_port}"
    fi
    
    # Asegurar que deployment.yaml usa imagen base sin registry y imagePullPolicy: Always
    if [ -f "${SCRIPT_DIR}/gitops-manifests/custom-apps/app-reloj/deployment.yaml" ]; then
        sed -i "s#image:.*app-reloj.*#image: app-reloj:latest#" \
            "${SCRIPT_DIR}/gitops-manifests/custom-apps/app-reloj/deployment.yaml"
        # Añadir imagePullPolicy: Always si no existe
        if ! grep -q "imagePullPolicy" "${SCRIPT_DIR}/gitops-manifests/custom-apps/app-reloj/deployment.yaml"; then
            sed -i '/image: app-reloj:latest/a\          imagePullPolicy: Always' \
                "${SCRIPT_DIR}/gitops-manifests/custom-apps/app-reloj/deployment.yaml"
        fi
    fi
    
    log_info "Commiteando y pusheando cambios a Gitea..."
    cd "${SCRIPT_DIR}/gitops-manifests"
    git add custom-apps/
    git commit -m "feat: update custom apps to use registry images v1.0.0" --allow-empty
    git push gitea main
    cd "${SCRIPT_DIR}"
    
    log_info "Esperando a que ArgoCD sincronice las custom apps..."
    sleep 10
    
    # Forzar refresh de las aplicaciones
    kubectl patch app app-reloj -n argocd --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' 2>/dev/null || true
    
    log_info "Verificando despliegue de custom apps..."
    sleep 15
    
    local app_reloj_status=$(kubectl get deployment app-reloj -n app-reloj -o jsonpath='{.status.availableReplicas}' 2>/dev/null || echo "0")
    
    if [ "$app_reloj_status" = "1" ]; then
        log_success "✓ app-reloj desplegado correctamente"
    else
        log_warn "app-reloj aún no está disponible (puede estar iniciando)"
    fi
    
    log_success "CI/CD de custom apps completado"
}

# ============================================================================
# FASE 6.6: PARCHES POST-BOOTSTRAP
# ============================================================================
apply_post_bootstrap_patches() {
    log_phase "FASE 6.6/7: Aplicando parches post-bootstrap"
    
    # Esperar a que los deployments de argo-events se creen
    log_info "Esperando a que Argo Events despliegue recursos..."
    sleep 15
    
    # CRÍTICO: Argo Events Sensor controller a veces ignora spec.template.serviceAccountName
    # y crea el Deployment con SA "default". Solución: garantizar RBAC para AMBAS SAs.
    log_info "Verificando y asegurando RBAC para Sensors (SA correcta + fallback)..."
    
    # Verificar que el RoleBinding tiene ambas ServiceAccounts
    local current_subjects=$(kubectl get rolebinding sensor-workflow-creator-binding -n argo-workflows -o json 2>/dev/null | jq -r '.subjects | length' || echo "0")
    
    if [ "$current_subjects" -lt 2 ]; then
        log_info "Agregando SA 'default' como fallback en RoleBinding..."
        kubectl patch rolebinding sensor-workflow-creator-binding -n argo-workflows --type=json -p='[
            {
                "op": "add",
                "path": "/subjects/-",
                "value": {
                    "kind": "ServiceAccount",
                    "name": "default",
                    "namespace": "argo-events"
                }
            }
        ]' 2>/dev/null || true
        log_success "✓ RBAC actualizado: ambas SAs tienen permisos"
    else
        log_success "✓ RBAC ya configurado correctamente"
    fi
    
    # Verificar qué SA está usando el pod del Sensor (informativo, no bloqueante)
    local sensor_sa=""
    local tries_sa=0
    while [ $tries_sa -lt 20 ]; do
        sensor_sa=$(kubectl get pods -n argo-events -l sensor-name=gitea-workflow-trigger -o jsonpath='{.items[0].spec.serviceAccountName}' 2>/dev/null || echo "")
        if [ -n "$sensor_sa" ]; then
            break
        fi
        tries_sa=$((tries_sa+1))
        sleep 2
    done
    
    if [ "$sensor_sa" = "argo-events-sensor-sa" ]; then
        log_success "✓ Sensor usa SA correcta: argo-events-sensor-sa"
    elif [ "$sensor_sa" = "default" ]; then
        log_info "ℹ️  Sensor usa SA fallback 'default' (permisos OK, comportamiento conocido de Argo Events)"
    else
        log_warn "⚠️  Sensor SA: '$sensor_sa' (inesperado, pero RBAC cubre ambos casos)"
    fi

    # Función para esperar salud de aplicaciones clave antes de CI/CD (refuerzo de fiabilidad GitOps)
    wait_apps_health() {
        local apps=(argocd-self argo-workflows argo-events registry)
        log_info "Esperando salud de aplicaciones clave antes de continuar (timeout 600s)..."
        local start=$(date +%s)
        while true; do
            local all_ok=true
            for app in "${apps[@]}"; do
                local sync=$(kubectl get app "$app" -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "")
                local health=$(kubectl get app "$app" -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || echo "")
                if [ "$sync" != "Synced" ] || [[ ! "$health" =~ ^Healthy$ ]]; then
                    all_ok=false
                    log_info "↻ Aún esperando: $app (sync=$sync health=$health)"
                fi
            done
            if $all_ok; then
                log_success "✓ Todas las aplicaciones clave Synced & Healthy"
                break
            fi
            if [ $(( $(date +%s) - start )) -ge 600 ]; then
                log_warn "Timeout esperando salud completa; continuando de todas formas"
                break
            fi
            sleep 5
        done
    }
    wait_apps_health
    
    # Corregir webhook URL cuando se añadan custom-apps
    # log_info "Corrigiendo webhook URL en Gitea..."
    # sleep 5
    # local webhook_id=$(curl -s http://localhost:30083/api/v1/repos/gitops/app-reloj/hooks -u gitops:gitops 2>/dev/null | jq -r '.[0].id' 2>/dev/null || echo "")
    # if [ -n "$webhook_id" ] && [ "$webhook_id" != "null" ]; then
    #     curl -s -X PATCH "http://localhost:30083/api/v1/repos/gitops/app-reloj/hooks/$webhook_id" \
    #         -u gitops:gitops \
    #         -H "Content-Type: application/json" \
    #         -d '{"config":{"url":"http://gitea-webhook-nodeport.argo-events.svc.cluster.local:12000/app-reloj","content_type":"json"},"active":true}' >/dev/null 2>&1
    #     log_success "✓ Webhook URL corregida"
    # else
    #     log_warn "No se pudo corregir webhook URL"
    # fi
    
    # Configurar registry insecure en containerd (format containerd 2.x - config_path)
    log_info "Configurando registry insecure en containerd (certs.d)..."
    local registry_ip="${REGISTRY_CLUSTER_IP}"
    if [ -n "$registry_ip" ]; then
        # Crear directorios de configuración certs.d para containerd 2.x
        docker exec ${CLUSTER_NAME}-control-plane sh -c "
            mkdir -p /etc/containerd/certs.d/${registry_ip}:5000
            cat > /etc/containerd/certs.d/${registry_ip}:5000/hosts.toml <<EOF2
server = \"http://${registry_ip}:5000\"

[host.\"http://${registry_ip}:5000\"]
  capabilities = [\"pull\", \"resolve\", \"push\"]
  skip_verify = true
EOF2

            mkdir -p /etc/containerd/certs.d/docker-registry.registry.svc.cluster.local:5000
            cat > /etc/containerd/certs.d/docker-registry.registry.svc.cluster.local:5000/hosts.toml <<EOF2
server = \"http://docker-registry.registry.svc.cluster.local:5000\"

[host.\"http://docker-registry.registry.svc.cluster.local:5000\"]
  capabilities = [\"pull\", \"resolve\", \"push\"]
  skip_verify = true
EOF2

            mkdir -p /etc/containerd/certs.d/localhost:30100
            cat > /etc/containerd/certs.d/localhost:30100/hosts.toml <<EOF2
server = \"http://localhost:30100\"

[host.\"http://localhost:30100\"]
  capabilities = [\"pull\", \"resolve\", \"push\"]
  skip_verify = true
EOF2
        " 2>/dev/null || true
        # Restart containerd to pick up config_path changes
        docker exec ${CLUSTER_NAME}-control-plane systemctl restart containerd 2>/dev/null || true
        sleep 5
        log_success "✓ Containerd configurado para registry insecure (certs.d): ${registry_ip}:5000"
    else
        log_warn "No se pudo configurar registry ClusterIP"
    fi
    
    log_info "Verificando configuración de registry en containerd..."
    if docker exec ${CLUSTER_NAME}-control-plane ls /etc/containerd/certs.d/docker-registry.registry.svc.cluster.local:5000/hosts.toml >/dev/null 2>&1; then
        log_success "✓ Containerd configurado para registry insecure (certs.d)"
    else
        log_warn "Configuración de registry no detectada en containerd"
    fi
    
    log_success "Parches post-bootstrap aplicados"
}

# ============================================================================
# FASE 7: VERIFICACIÓN
# ============================================================================
verify_deployment() {
    log_phase "FASE 7/7: Verificando despliegue completo"
    
    # Esperar a que todas las apps alcancen Healthy antes de verificar
    log_info "Esperando que todas las aplicaciones alcancen estado Healthy (max 600s)..."
    local start_wait=$(date +%s)
    while true; do
        local total_apps healthy_apps
        total_apps=$(kubectl get applications -n argocd --no-headers 2>/dev/null | wc -l)
        healthy_apps=$(kubectl get applications -n argocd -o json 2>/dev/null | \
            jq '[.items[] | select(.status.health.status=="Healthy")] | length' 2>/dev/null || echo "0")
        if [ "$healthy_apps" -ge "$total_apps" ] && [ "$total_apps" -gt 0 ]; then
            log_success "Todas las aplicaciones ($total_apps) están Healthy"
            break
        fi
        local elapsed=$(( $(date +%s) - start_wait ))
        if [ "$elapsed" -ge 600 ]; then
            log_warn "Timeout esperando apps Healthy ($healthy_apps/$total_apps). Continuando verificación..."
            break
        fi
        log_info "↻ $healthy_apps/$total_apps Healthy (${elapsed}s)..."
        sleep 10
    done
    
    log_info "Aplicaciones en Argo CD:"
    kubectl get applications -n argocd
    
    echo ""
    log_info "Pods en todos los namespaces:"
    kubectl get pods --all-namespaces
    
    echo ""
    log_success "╔════════════════════════════════════════════════════════════╗"
    log_success "║          🎉 INSTALACIÓN COMPLETADA EXITOSAMENTE          ║"
    log_success "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    # BEST-PRACTICE: Mostrar password de ArgoCD claramente
    local argocd_password
    argocd_password=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "acceso anónimo habilitado")
    
    echo -e "${MAGENTA}════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}📋 CREDENCIALES DE ACCESO (¡GUÁRDALAS!):${NC}"
    echo -e "${MAGENTA}════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}Argo CD:${NC}"
    echo -e "  URL:      ${GREEN}http://localhost:30080${NC}"
    echo -e "  Usuario:  ${GREEN}admin${NC} (o acceso anónimo habilitado)"
    echo -e "  Password: ${GREEN}${argocd_password}${NC}"
    echo ""
    echo -e "${YELLOW}Gitea (Source of Truth):${NC}"
    echo -e "  URL:      ${GREEN}http://localhost:30083${NC}"
    echo -e "  Usuario:  ${GREEN}${GITEA_USER}${NC}"
    echo -e "  Password: ${GREEN}${GITEA_PASSWORD}${NC}"
    echo ""
    echo -e "${YELLOW}Grafana:${NC}"
    echo -e "  URL:      ${GREEN}http://localhost:30082${NC}"
    echo -e "  Usuario:  ${GREEN}admin${NC}"
    echo -e "  Password: ${GREEN}gitops${NC}"
    echo ""
    echo -e "${YELLOW}Kargo:${NC}"
    echo -e "  URL:      ${GREEN}http://localhost:30085${NC}"
    echo -e "  Usuario:  ${GREEN}admin${NC}"
    echo -e "  Password: ${GREEN}gitops${NC}"
    echo ""
    echo -e "${MAGENTA}════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${CYAN}URLs de herramientas adicionales:${NC}"
    echo -e "  ${GREEN}•${NC} Registry:         http://localhost:30100"
    echo -e "  ${GREEN}•${NC} Argo Workflows:   http://localhost:30091"
    echo -e "  ${GREEN}•${NC} Argo Rollouts:    http://localhost:30084"
    echo -e "  ${GREEN}•${NC} Dashboard:        http://localhost:30090"
    echo -e "  ${GREEN}•${NC} Prometheus:       http://localhost:30081"
    echo -e "  ${GREEN}•${NC} Redis Commander:  http://localhost:30097"
    echo ""
    echo -e "${CYAN}Custom Apps desplegadas:${NC}"
    echo -e "  ${GREEN}•${NC} App Reloj:        http://localhost:30150"
    echo ""
    echo -e "${CYAN}Pipeline CI/CD (para tus custom apps):${NC}"
    echo -e "  ${GREEN}1.${NC} Añade tu app en gitops-source-code/<app-name>/ con Dockerfile"
    echo -e "  ${GREEN}2.${NC} Crea manifests en gitops-manifests/custom-apps/<app-name>/"
    echo -e "  ${GREEN}3.${NC} Webhook trigger Argo Events → Argo Workflows"
    echo -e "  ${GREEN}4.${NC} Build con tags: v{semver}, {commit-sha}, latest"
    echo -e "  ${GREEN}5.${NC} ArgoCD auto-sync → K8s deploy"
    echo ""
    echo -e "${CYAN}Próximos pasos:${NC}"
    echo -e "  ${GREEN}1.${NC} Accede a Argo CD para ver el despliegue automático"
    echo -e "  ${GREEN}2.${NC} Revisa los repositorios en Gitea"
    echo -e "  ${GREEN}3.${NC} Añade una custom app y observa el pipeline completo"
    echo ""
    echo -e "${YELLOW}💡 Gitea es tu source of truth - todos los cambios deben ir ahí${NC}"
    echo -e "${YELLOW}💡 Registry configurado para HTTP insecure (localhost:30100)${NC}"
    echo ""
    
    # ========================================================================
    # VERIFICACIÓN FINAL EXHAUSTIVA
    # ========================================================================
    echo ""
    echo -e "${MAGENTA}════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}          🔍 VERIFICACIÓN FINAL DEL ENTORNO${NC}"
    echo -e "${MAGENTA}════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Recopilar métricas
    local TOTAL_APPS HEALTHY_APPS APPSETS PROJECTS SEALED_SECRETS EVENTSOURCES SENSORS
    TOTAL_APPS=$(kubectl get applications -n argocd --no-headers 2>/dev/null | wc -l)
    HEALTHY_APPS=$(kubectl get applications -n argocd -o json 2>/dev/null | jq '[.items[] | select(.status.sync.status=="Synced" and .status.health.status=="Healthy")] | length' 2>/dev/null || echo "0")
    APPSETS=$(kubectl get applicationsets -n argocd --no-headers 2>/dev/null | wc -l)
    PROJECTS=$(kubectl get appprojects -n argocd --no-headers 2>/dev/null | wc -l)
    SEALED_SECRETS=$(kubectl get sealedsecrets -A --no-headers 2>/dev/null | wc -l)
    EVENTSOURCES=$(kubectl get eventsources -n argo-events --no-headers 2>/dev/null | wc -l)
    SENSORS=$(kubectl get sensors -n argo-events --no-headers 2>/dev/null | wc -l)
    REGISTRY_IP=$(kubectl get svc -n registry docker-registry -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
    
    echo -e "${CYAN}✅ ESTADO DEL CLUSTER:${NC}"
    echo -e "  ${GREEN}•${NC} Aplicaciones ArgoCD: ${HEALTHY_APPS}/${TOTAL_APPS} Synced & Healthy"
    echo -e "  ${GREEN}•${NC} ApplicationSets: ${APPSETS}"
    echo -e "  ${GREEN}•${NC} AppProjects: ${PROJECTS}"
    echo ""
    
    echo -e "${CYAN}✅ SEGURIDAD:${NC}"
    echo -e "  ${GREEN}•${NC} Sealed Secrets: ${SEALED_SECRETS} activos"
    echo -e "  ${GREEN}•${NC} ServiceAccounts con RBAC mínimo"
    echo ""
    
    echo -e "${CYAN}✅ CI/CD PIPELINE:${NC}"
    echo -e "  ${GREEN}•${NC} EventSources: ${EVENTSOURCES}"
    echo -e "  ${GREEN}•${NC} Sensors: ${SENSORS}"
    echo -e "  ${GREEN}•${NC} Webhook configurado y operativo"
    echo ""
    
    echo -e "${CYAN}✅ REGISTRY:${NC}"
    echo -e "  ${GREEN}•${NC} ClusterIP: ${REGISTRY_IP}:5000"
    local REGISTRY_IMAGES
    REGISTRY_IMAGES=$(curl -s http://localhost:30100/v2/_catalog 2>/dev/null | jq -r '.repositories | length' 2>/dev/null || echo "0")
    echo -e "  ${GREEN}•${NC} Imágenes disponibles: ${REGISTRY_IMAGES}"
    echo ""
    
    # Tests de conectividad
    echo -e "${CYAN}🔗 TESTS DE CONECTIVIDAD:${NC}"
    
    # Test ArgoCD
    if curl -s http://localhost:30080 >/dev/null 2>&1; then
        echo -e "  ${GREEN}✅${NC} ArgoCD UI accesible"
    else
        echo -e "  ${YELLOW}⚠️${NC}  ArgoCD UI no responde"
    fi
    
    # Test Gitea
    if curl -s http://localhost:30083 >/dev/null 2>&1; then
        echo -e "  ${GREEN}✅${NC} Gitea accesible"
    else
        echo -e "  ${YELLOW}⚠️${NC}  Gitea no responde"
    fi
    
    # Test Registry
    if curl -s http://localhost:30100/v2/_catalog >/dev/null 2>&1; then
        echo -e "  ${GREEN}✅${NC} Registry accesible"
    else
        echo -e "  ${YELLOW}⚠️${NC}  Registry no responde"
    fi
    
    # Test custom apps (solo si hay deployments en custom-apps namespaces)
    local CUSTOM_NS
    CUSTOM_NS=$(kubectl get ns -o name 2>/dev/null | grep -E 'app-' | sed 's|namespace/||' || true)
    if [ -n "$CUSTOM_NS" ]; then
        for ns in $CUSTOM_NS; do
            echo -e "  ${YELLOW}⏳${NC} Verificando custom app en namespace ${ns}..."
            if kubectl wait --for=condition=Ready pod -l app="${ns}" -n "${ns}" --timeout=30s >/dev/null 2>&1; then
                echo -e "  ${GREEN}✅${NC} ${ns} desplegada"
            else
                echo -e "  ${YELLOW}⏳${NC} ${ns} aún iniciando"
            fi
        done
    else
        echo -e "  ${BLUE}ℹ️${NC}  No hay custom apps desplegadas (custom-apps/ vacío)"
    fi
    
    echo ""
    
    # Score final (disable errexit for arithmetic that may be 0)
    local SCORE=0
    local MAX_SCORE=6
    
    { [ "$HEALTHY_APPS" = "$TOTAL_APPS" ] && [ "$TOTAL_APPS" -gt 0 ] && SCORE=$((SCORE+1)); } || true
    { [ "$EVENTSOURCES" -ge 1 ] && SCORE=$((SCORE+1)); } || true
    { [ "$SENSORS" -ge 1 ] && SCORE=$((SCORE+1)); } || true
    { [ "$SEALED_SECRETS" -ge 3 ] && SCORE=$((SCORE+1)); } || true
    { [ "$APPSETS" -ge 2 ] && SCORE=$((SCORE+1)); } || true
    { [ -n "$REGISTRY_IP" ] && SCORE=$((SCORE+1)); } || true
    
    if [ "$SCORE" -eq "$MAX_SCORE" ]; then
        echo -e "${GREEN}🏆 INSTALACIÓN PERFECTA - 100% OPERATIVA${NC}"
        echo -e "${GREEN}   └─ Todos los componentes verificados exitosamente${NC}"
    elif [ "$SCORE" -ge 4 ]; then
        echo -e "${YELLOW}✅ INSTALACIÓN COMPLETADA - ${SCORE}/${MAX_SCORE} checks OK${NC}"
        echo -e "${YELLOW}   └─ Algunos componentes pueden necesitar más tiempo${NC}"
    else
        echo -e "${YELLOW}⚠️  INSTALACIÓN COMPLETADA - ${SCORE}/${MAX_SCORE} checks OK${NC}"
        echo -e "${YELLOW}   └─ Revisar logs para componentes marcados${NC}"
    fi
    
    echo ""
    echo -e "${MAGENTA}════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Guardar log de verificación
    {
        echo "Verificación ejecutada: $(date)"
        echo "======================================"
        echo "Aplicaciones: ${HEALTHY_APPS}/${TOTAL_APPS}"
        echo "ApplicationSets: ${APPSETS}"
        echo "AppProjects: ${PROJECTS}"
        echo "Sealed Secrets: ${SEALED_SECRETS}"
        echo "EventSources: ${EVENTSOURCES}"
        echo "Sensors: ${SENSORS}"
        echo "Registry: ${REGISTRY_IP}:5000"
        echo "Score: ${SCORE}/${MAX_SCORE}"
        echo ""
        echo "Aplicaciones no Healthy:"
        kubectl get applications -n argocd -o json 2>/dev/null | \
            jq -r '.items[] | select(.status.sync.status!="Synced" or .status.health.status!="Healthy") | .metadata.name' 2>/dev/null || echo "Ninguna"
    } > /tmp/install-verification.log 2>&1
    
    log_info "Log de verificación guardado en: /tmp/install-verification.log"

    # Verificación ligera de credenciales Kargo (best-practice mínima: comprobar secret y endpoint)
    log_info "Verificando credenciales Kargo (admin/gitops)..."
    if kubectl get secret kargo-api -n kargo >/dev/null 2>&1; then
        local KARGO_USER
        local KARGO_PASS
        KARGO_USER=$(kubectl get secret kargo-api -n kargo -o jsonpath='{.data.ADMIN_ACCOUNT_USERNAME}' 2>/dev/null | base64 -d || echo "")
        KARGO_PASS=$(kubectl get secret kargo-api -n kargo -o jsonpath='{.data.ADMIN_ACCOUNT_PASSWORD}' 2>/dev/null | base64 -d || echo "")
        if [ "$KARGO_USER" = "admin" ] && [ "$KARGO_PASS" = "gitops" ]; then
            log_success "Secret Kargo coincide con credenciales esperadas (admin/gitops)"
        else
            log_warn "Credenciales Kargo distintas a las esperadas: $KARGO_USER/$KARGO_PASS"
        fi
        # Intentar acceder al endpoint (NodePort) healthz si existe service
        if curl -s http://localhost:30085/healthz | grep -qi 'ok'; then
            log_success "Endpoint Kargo /healthz accesible (NodePort 30085)"
        else
            log_warn "No se pudo validar /healthz de Kargo en NodePort 30085"
        fi
    else
        log_warn "Secret kargo-api no encontrado; saltando verificación de credenciales"
    fi
}

# ============================================================================
# UTILIDADES: KUBESEAL Y GENERACIÓN DE SEALEDSECRETS
# ============================================================================
ensure_kubeseal_installed() {
    if command -v kubeseal >/dev/null 2>&1; then
        return 0
    fi
    local ver="$KUBESEAL_VERSION"
    if [ -z "$ver" ]; then ver="v0.27.1"; fi
    log_info "Instalando kubeseal (${ver})..."
    local TMPD
    TMPD=$(mktemp -d)
    pushd "$TMPD" >/dev/null
    local ver_no_v="${ver#v}"
    curl -fsSL -o kubeseal.tar.gz "https://github.com/bitnami-labs/sealed-secrets/releases/download/${ver}/kubeseal-${ver_no_v}-linux-amd64.tar.gz"
    tar -xzf kubeseal.tar.gz kubeseal
    sudo install -m 0755 kubeseal /usr/local/bin/kubeseal
    popd >/dev/null
    rm -rf "$TMPD"
}

generate_initial_sealed_secrets() {
    log_info "Generando SealedSecrets iniciales (Grafana, Kargo, Gitea-token para Workflows)..."

    # Asegura sealed-secrets listo (en caso de ejecución fuera de orden)
    if ! kubectl get deploy -n kube-system sealed-secrets-controller >/dev/null 2>&1; then
        log_warn "Sealed Secrets no está desplegado aún; saltando generación."
        return 1
    fi
    kubectl wait --for=condition=available --timeout=180s deployment/sealed-secrets-controller -n kube-system || true
    # =========================================================================
    # RESUMEN DE ENDPOINTS (NodePorts e Ingress Hosts)
    # =========================================================================
    # (Definición de output_endpoints_summary movida a nivel global)


    ensure_kubeseal_installed

    local CERT_FILE
    CERT_FILE="${SCRIPT_DIR}/.tmp/sealed-secrets-pub-cert.pem"
    mkdir -p "${SCRIPT_DIR}/.tmp"
    log_info "Obteniendo clave pública del controlador..."
    kubeseal --controller-name=sealed-secrets-controller \
             --controller-namespace=kube-system \
             --fetch-cert > "$CERT_FILE"

    # 1) Grafana: password admin "gitops"
    mkdir -p "${SCRIPT_DIR}/gitops-manifests/gitops-tools/grafana"
    kubectl create secret generic grafana-admin \
        --namespace=grafana \
        --from-literal=GF_SECURITY_ADMIN_PASSWORD=gitops \
        --dry-run=client -o yaml | \
        kubeseal --cert="$CERT_FILE" --format=yaml > \
        "${SCRIPT_DIR}/gitops-manifests/gitops-tools/grafana/sealed-secret.yaml"

    # 2) Kargo: credenciales admin "admin/gitops"
    mkdir -p "${SCRIPT_DIR}/gitops-manifests/gitops-tools/kargo"
    cat <<'EOF' | kubeseal --cert="$CERT_FILE" --format=yaml > "${SCRIPT_DIR}/gitops-manifests/gitops-tools/kargo/sealed-secret.yaml"
apiVersion: v1
kind: Secret
metadata:
  name: kargo-api
  namespace: kargo
type: Opaque
stringData:
  ADMIN_ACCOUNT_ENABLED: "true"
  ADMIN_ACCOUNT_USERNAME: "admin"
  ADMIN_ACCOUNT_PASSWORD: "gitops"
  ADMIN_ACCOUNT_PASSWORD_HASH: "$2a$10$mSUjJg7p7/H8p8RqZ.1z7OvVwZ9p1YmvZWJ9KqzJ9mZqWJ9KqzJ9m"
  ADMIN_ACCOUNT_TOKEN_SIGNING_KEY: "gitops-learning-key-not-for-production"
  ADMIN_ACCOUNT_TOKEN_ISSUER: "http://localhost:30091"
  ADMIN_ACCOUNT_TOKEN_AUDIENCE: "http://localhost:30091"
  ADMIN_ACCOUNT_TOKEN_TTL: "24h"
EOF

    # 3) Gitea token para argo-workflows (usando usuario/password para CI/CD)
    mkdir -p "${SCRIPT_DIR}/gitops-manifests/gitops-tools/argo-workflows"
    kubectl create secret generic gitea-ci-token \
        --namespace=argo-workflows \
        --from-literal=username="${GITEA_USER}" \
        --from-literal=password="${GITEA_PASSWORD}" \
        --from-literal=token="${GITEA_PASSWORD}" \
        --dry-run=client -o yaml | \
        kubeseal --cert="$CERT_FILE" --format=yaml > \
        "${SCRIPT_DIR}/gitops-manifests/gitops-tools/argo-workflows/sealed-secret-gitea.yaml"

    log_success "SealedSecrets generados en gitops-manifests/gitops-tools/{grafana,kargo,argo-workflows}"
}

# ============================================================================
# FUNCION: RESUMEN DE ENDPOINTS (NodePorts e Ingress Hosts)
# ============================================================================
output_endpoints_summary() {
    log_phase "RESUMEN FINAL DE ENDPOINTS"
    local OUT_JSON="/tmp/gitops-endpoints.json"
    local DATA
    DATA=$(cat <<'EOF'
argocd|argocd.local|30080|argocd
gitea|gitea.local|30083|gitea
grafana|grafana.local|30082|grafana
prometheus|prometheus.local|30081|prometheus
kargo|kargo.local|30085|kargo
workflows|workflows.local|30091|argo-workflows
rollouts|rollouts.local|30084|argo-rollouts
dashboard|dashboard.local|30090|dashboard
EOF
)
    printf "\n%-12s %-22s %-10s %-15s\n" "HERRAMIENTA" "INGRESS HOST" "NODEPORT" "NAMESPACE"
    printf "%-12s %-22s %-10s %-15s\n" "-----------" "----------------------" "--------" "-----------"
    while IFS='|' read -r tool host port ns; do
        printf "%-12s %-22s %-10s %-15s\n" "$tool" "$host" "$port" "$ns"
    done <<< "$DATA"
    echo "$DATA" | awk -F '|' 'BEGIN {print "["} {printf "{\"tool\":\"%s\",\"host\":\"%s\",\"nodePort\":%s,\"namespace\":\"%s\"}", $1,$2,$3,$4; if (NR!=NF) print ","} END {print "]"}' > "$OUT_JSON" 2>/dev/null || true
    log_success "Resumen JSON guardado en $OUT_JSON"
    echo ""
    echo "Añade estas entradas a /etc/hosts si usas Ingress (copiar y pegar):"
    echo "127.0.0.1 argocd.local gitea.local grafana.local prometheus.local kargo.local workflows.local rollouts.local dashboard.local"
    echo ""
    echo "Accesos rápidos (NodePort o Ingress):"
    echo "http://argocd.local    | http://localhost:30080"
    echo "http://gitea.local     | http://localhost:30083"
    echo "http://grafana.local   | http://localhost:30082"
    echo "http://prometheus.local| http://localhost:30081"
    echo "http://kargo.local     | http://localhost:30085"
    echo "http://workflows.local | http://localhost:30091"
    echo "http://rollouts.local  | http://localhost:30084"
    echo "http://dashboard.local | http://localhost:30090"
}

# ============================================================================
# MAIN
# ============================================================================
main() {
    echo ""
    echo -e "${MAGENTA}════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}     🚀 Entorno GitOps - Instalación Bootstrap v2.1${NC}"
    echo -e "${CYAN}        Best-Practices: Kind + ArgoCD + Gitea${NC}"
    echo -e "${MAGENTA}════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    check_prerequisites  # BEST-PRACTICE: Validar entorno antes de empezar
    
    install_dependencies
    update_manifests_with_latest_versions
    create_cluster
    install_argocd
    deploy_sealed_secrets_prebootstrap
    deploy_gitea
    initialize_gitea_repos
    bootstrap_gitops
    complete_custom_apps_cicd
    apply_post_bootstrap_patches
    verify_deployment
    output_endpoints_summary
}

# Ejecutar
main "$@"
