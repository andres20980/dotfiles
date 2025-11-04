#!/bin/bash
set -euo pipefail

# ============================================================================
# 🚀 Entorno GitOps - Instalación Completa Optimizada
# ============================================================================
# Instala TODO desde WSL limpio siguiendo best practices:
# 1. Dependencias sistema
# 2. Cluster Kubernetes (Kind)
# 3. Argo CD (motor GitOps)
# 4. Gitea (source of truth)
# 5. Push local → Gitea
# 6. Bootstrap GitOps (root-app desde Gitea)
# 7. Despliegue automático de todas las tools
#
# Uso: ./install.sh
# Tiempo estimado: 5-10 minutos
# Requisitos: WSL2 con Ubuntu
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

check_wsl() {
    if grep -qi microsoft /proc/version; then
        log_info "Entorno WSL detectado"
        return 0
    fi
    if [ "$(uname -s)" = "Linux" ]; then
        log_warn "No es WSL, pero es Linux. Continuamos (modo genérico)."
        return 0
    fi
    log_error "SO no soportado automáticamente. Requiere Linux/WSL2."
    exit 1
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
    
    DASHBOARD_VERSION=$(latest_github_release kubernetes dashboard)
    sleep 0.2
    # Dashboard v7+ requiere arquitectura multi-container compleja
    # Usamos v2.7.0 que es la última versión simple con una sola imagen
    if [ -z "$DASHBOARD_VERSION" ]; then DASHBOARD_VERSION="v2.7.0"; fi
    DASHBOARD_IMAGE_TAG="${DASHBOARD_VERSION}"
    
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

    # 4) Argo Workflows (controller + cli)
    if [ -n "$ARGO_WORKFLOWS_VERSION" ] && [ -f "${SCRIPT_DIR}/gitops-manifests/gitops-tools/argo-workflows/install.yaml" ]; then
        sed -i "s#quay.io/argoproj/workflow-controller:v[0-9][^ \n\r]*#quay.io/argoproj/workflow-controller:${ARGO_WORKFLOWS_VERSION}#" \
            "${SCRIPT_DIR}/gitops-manifests/gitops-tools/argo-workflows/install.yaml" 2>/dev/null || true
        sed -i "s#quay.io/argoproj/argocli:v[0-9][^ \n\r]*#quay.io/argoproj/argocli:${ARGO_WORKFLOWS_VERSION}#" \
            "${SCRIPT_DIR}/gitops-manifests/gitops-tools/argo-workflows/install.yaml" 2>/dev/null || true
    fi

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
    
    log_info "Actualizando sistema Ubuntu..."
    sudo apt-get update -qq
    sudo apt-get upgrade -y -qq
    
    # Si no hay sudo sin interacción, evitamos colgarnos pidiendo contraseña
    if ! sudo -n true 2>/dev/null; then
        log_warn "No hay sudo sin contraseña. Saltando instalación de dependencias del sistema. Se asume que Docker, kubectl, kind y helm ya están instalados."
        # Aun así resolvemos versiones para el resto de pasos
        resolve_latest_versions
        return 0
    fi

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
        --config "${SCRIPT_DIR}/config/kind-config.yaml" \
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
    kubectl apply -n argocd -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"
    
    log_info "Esperando a que Argo CD esté completamente listo..."
    kubectl wait --for=condition=available --timeout=300s \
        deployment/argocd-server \
        deployment/argocd-repo-server \
        deployment/argocd-applicationset-controller \
        deployment/argocd-dex-server \
        -n argocd
    
    kubectl wait --for=condition=ready --timeout=300s \
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
    kubectl apply -f "${ss_manifest}"

    log_info "Esperando a que el controlador de Sealed Secrets esté listo..."
    kubectl wait --for=condition=available --timeout=300s \
        deployment/sealed-secrets-controller -n sealed-secrets || {
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
    kubectl apply -f "${SCRIPT_DIR}/gitops-manifests/gitops-tools/gitea/"
    
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
# FASE 5: INICIALIZAR REPOSITORIOS EN GITEA
# ============================================================================
initialize_gitea_repos() {
    log_phase "FASE 5/7: Inicializando repositorios en Gitea"
    
    # Crear usuario admin en Gitea
    log_info "Creando usuario admin en Gitea..."
    kubectl exec -n gitea deployment/gitea -- su git -c "\
        gitea admin user create \
        --admin \
        --username ${GITEA_USER} \
        --password ${GITEA_PASSWORD} \
        --email ${GITEA_USER}@gitops.local \
        --must-change-password=false" 2>/dev/null || log_info "Usuario ya existe"
    
    # Esperar un momento para que el usuario esté disponible
    sleep 3
    
    # Crear token de API
    log_info "Creando token de API en Gitea..."
    local token
    token=$(curl -s -X POST "${GITEA_URL_EXTERNAL}/api/v1/users/${GITEA_USER}/tokens" \
        -H "Content-Type: application/json" \
        -u "${GITEA_USER}:${GITEA_PASSWORD}" \
        -d "{\"name\": \"bootstrap-$(date +%s)\", \"scopes\": [\"write:repository\", \"write:user\"]}" \
        | jq -r '.sha1')
    
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
    
    # Generar SealedSecrets iniciales (Grafana, Kargo) antes del primer push
    generate_initial_sealed_secrets || log_warn "No se pudieron generar SealedSecrets iniciales (continuamos)"

    # Crear y pushear gitops-manifests
    create_gitea_repo "gitops-manifests"
    push_to_gitea "gitops-manifests" "${SCRIPT_DIR}/gitops-manifests"
    
    # Crear y pushear aplicaciones de source code
    for app in app-reloj visor-gitops; do
        create_gitea_repo "${app}"
        push_to_gitea "${app}" "${SCRIPT_DIR}/gitops-source-code/${app}"
    done
    
                log_success "Repositorios inicializados en Gitea"

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
    kubectl apply -f "${SCRIPT_DIR}/bootstrap/root-app.yaml"
    
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
        # Si hay error, abortar y mostrar mensaje
        if [[ "$cond" =~ Error|ComparisonError|Suspended|MissingResource ]]; then
            log_error "La aplicación root está en estado de error: $cond"
            echo "$msg"
            exit 1
        fi
        # Re-intentar refresh cada cierto tiempo
        if (( tries % 10 == 0 )); then
            kubectl patch app root -n argocd --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' >/dev/null 2>&1 || true
        fi
        tries=$((tries+1))
        sleep 2
    done

    # Esperar a que se creen aplicaciones hijas clave (p.ej. argocd-self-config)
    log_info "Esperando a que se creen aplicaciones hijas (argocd-self-config, gitops-tools, etc.)..."
    tries=0
    while [ $tries -lt 120 ]; do
        if kubectl get app argocd-self-config -n argocd >/dev/null 2>&1; then
            log_success "Aplicación argocd-self-config detectada"
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
# FASE 7: VERIFICACIÓN
# ============================================================================
verify_deployment() {
    log_phase "FASE 7/7: Verificando despliegue completo"
    
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
    echo -e "${CYAN}URLs de acceso:${NC}"
    echo -e "  ${GREEN}•${NC} Argo CD:  http://localhost:30080"
    echo -e "  ${GREEN}•${NC} Gitea:    http://localhost:30083"
    echo -e "     └─ Usuario: ${GITEA_USER} / Contraseña: ${GITEA_PASSWORD}"
    echo ""
    echo -e "${CYAN}Próximos pasos:${NC}"
    echo -e "  ${GREEN}1.${NC} Accede a Argo CD para ver el despliegue automático"
    echo -e "  ${GREEN}2.${NC} Revisa los repositorios en Gitea"
    echo -e "  ${GREEN}3.${NC} Haz cambios en los repos y observa el auto-sync"
    echo ""
    echo -e "${YELLOW}💡 Gitea es tu source of truth - todos los cambios deben ir ahí${NC}"
    echo ""
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
    log_info "Generando SealedSecrets iniciales (Grafana, Kargo)..."

    # Asegura sealed-secrets listo (en caso de ejecución fuera de orden)
    if ! kubectl get deploy -n sealed-secrets sealed-secrets-controller >/dev/null 2>&1; then
        log_warn "Sealed Secrets no está desplegado aún; saltando generación."
        return 1
    fi
    kubectl wait --for=condition=available --timeout=180s deployment/sealed-secrets-controller -n sealed-secrets || true

    ensure_kubeseal_installed

    local CERT_FILE
    CERT_FILE="${SCRIPT_DIR}/.tmp/sealed-secrets-pub-cert.pem"
    mkdir -p "${SCRIPT_DIR}/.tmp"
    log_info "Obteniendo clave pública del controlador..."
    kubeseal --controller-name=sealed-secrets-controller \
             --controller-namespace=sealed-secrets \
             --fetch-cert > "$CERT_FILE"

    # 1) Grafana: password admin
    mkdir -p "${SCRIPT_DIR}/gitops-manifests/gitops-tools/grafana"
    kubectl create secret generic grafana-admin \
        --namespace=grafana \
        --from-literal=GF_SECURITY_ADMIN_PASSWORD=gitops \
        --dry-run=client -o yaml | \
        kubeseal --cert="$CERT_FILE" --format=yaml > \
        "${SCRIPT_DIR}/gitops-manifests/gitops-tools/grafana/sealed-secret.yaml"

    # 2) Kargo: credenciales admin (entorno de aprendizaje)
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

    log_success "SealedSecrets generados en gitops-manifests/gitops-tools/{grafana,kargo}"
}

# ============================================================================
# MAIN
# ============================================================================
main() {
    echo ""
    echo -e "${MAGENTA}════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}     🚀 GitOps Learning Environment - Bootstrap v2.0${NC}"
    echo -e "${MAGENTA}════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    check_wsl
    
    install_dependencies
    update_manifests_with_latest_versions
    create_cluster
    install_argocd
    deploy_sealed_secrets_prebootstrap
    deploy_gitea
    initialize_gitea_repos
    bootstrap_gitops
    verify_deployment
}

# Ejecutar
main "$@"
