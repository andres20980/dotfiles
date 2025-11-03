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
ARGOCD_VERSION="v2.13.2"
KIND_VERSION="v0.24.0"
KUBECTL_VERSION="v1.31.0"
HELM_VERSION="v3.16.2"
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
    if ! grep -qi microsoft /proc/version; then
        log_error "Este script está diseñado para WSL2"
        exit 1
    fi
}

# ============================================================================
# FASE 1: INSTALACIÓN DE DEPENDENCIAS
# ============================================================================
install_dependencies() {
    log_phase "FASE 1/7: Instalando dependencias del sistema"
    
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
        sudo service docker start 2>/dev/null || true
    fi
    
    # kubectl
    if ! command -v kubectl &> /dev/null; then
        log_info "Instalando kubectl ${KUBECTL_VERSION}..."
        curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
        sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
        rm kubectl
        log_success "kubectl instalado"
    else
        log_info "kubectl ya instalado"
    fi
    
    # kind
    if ! command -v kind &> /dev/null; then
        log_info "Instalando kind ${KIND_VERSION}..."
        curl -Lo ./kind "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-amd64"
        sudo install -o root -g root -m 0755 kind /usr/local/bin/kind
        rm kind
        log_success "kind instalado"
    else
        log_info "kind ya instalado"
    fi
    
    # helm
    if ! command -v helm &> /dev/null; then
        log_info "Instalando Helm ${HELM_VERSION}..."
        curl -fsSL https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz -o helm.tar.gz
        tar -zxf helm.tar.gz
        sudo install -o root -g root -m 0755 linux-amd64/helm /usr/local/bin/helm
        rm -rf helm.tar.gz linux-amd64
        log_success "Helm instalado"
    else
        log_info "Helm ya instalado"
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
    
    log_info "Configurando Argo CD para entorno de aprendizaje..."
    
    # Patch: servidor inseguro (HTTP)
    kubectl patch deployment argocd-server -n argocd --type='json' \
        -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--insecure"}]'
    
    # Patch: deshabilitar autenticación
    kubectl patch cm argocd-cm -n argocd --type=merge -p='{"data":{"users.anonymous.enabled":"true"}}'
    
    # Patch: dar permisos admin a usuario anónimo
    kubectl patch cm argocd-rbac-cm -n argocd --type=merge -p='{"data":{"policy.default":"role:admin"}}'
    
    # Patch: servicio NodePort en 30080
    kubectl patch svc argocd-server -n argocd --type='json' \
        -p='[
            {"op": "replace", "path": "/spec/type", "value": "NodePort"},
            {"op": "add", "path": "/spec/ports/0/nodePort", "value": 30080}
        ]'
    
    log_info "Esperando a que Argo CD esté completamente listo..."
    kubectl wait --for=condition=available --timeout=300s \
        deployment/argocd-server \
        deployment/argocd-repo-server \
        deployment/argocd-applicationset-controller \
        deployment/argocd-dex-server \
        -n argocd
    
    kubectl wait --for=condition=ready --timeout=300s \
        pod -l app.kubernetes.io/name=argocd-server -n argocd
    
    log_success "Argo CD instalado y configurado"
    log_info "URL: http://localhost:30080"
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
    
    # Crear y pushear gitops-manifests
    create_gitea_repo "gitops-manifests"
    push_to_gitea "gitops-manifests" "${SCRIPT_DIR}/gitops-manifests"
    
    # Crear y pushear aplicaciones de source code
    for app in app-reloj visor-gitops; do
        create_gitea_repo "${app}"
        push_to_gitea "${app}" "${SCRIPT_DIR}/gitops-source-code/${app}"
    done
    
    # Configurar credenciales de repositorio en Argo CD
    log_info "Configurando credenciales en Argo CD..."
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: gitea-repo-creds
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repo-creds
stringData:
  type: git
  url: ${GITEA_URL_INTERNAL}/${GITEA_USER}
  username: ${GITEA_USER}
  password: ${GITEA_PASSWORD}
EOF
    
    log_success "Repositorios inicializados en Gitea"
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
    
    # Forzar sync inicial
    kubectl patch app root -n argocd --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
    
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
    create_cluster
    install_argocd
    deploy_gitea
    initialize_gitea_repos
    bootstrap_gitops
    verify_deployment
}

# Ejecutar
main "$@"
