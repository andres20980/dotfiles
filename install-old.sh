#!/bin/bash
set -euo pipefail

# 🚀 Entorno de Aprendizaje GitOps - Instalación Completa
# 
# Este script instala TODO lo necesario desde WSL limpio:
# - Dependencias del sistema (Docker, kubectl, kind, helm)
# - Cluster Kubernetes local (Kind)
# - Gitea (Git Server - Source of Truth)
# - Repositorios locales → Gitea
# - Argo CD configurado para aprendizaje
# - Todas las herramientas GitOps desplegadas automáticamente desde Gitea
#
# Flujo: Dependencias → Cluster → Gitea → Push a Gitea → Argo CD → GitOps desde Gitea
#
# Uso: ./install.sh
# Tiempo estimado: 5-10 minutos
# Requisitos: WSL2 con Ubuntu (limpio)

CLUSTER_NAME="gitops-local"
ARGOCD_VERSION="v2.13.2"
KIND_VERSION="v0.24.0"
KUBECTL_VERSION="v1.31.0"
HELM_VERSION="v3.16.2"
GITEA_USER="gitops"
GITEA_PASSWORD="gitops"
GITEA_URL="http://localhost:30083"

# Directorios
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GITEA_TOKEN_FILE="$HOME/.gitops-credentials/gitea-token.txt"

# Colores para salida
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Funciones de utilidad
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

log_phase() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo ""
}

comprobar_wsl() {
    if ! grep -qi microsoft /proc/version; then
        log_error "Este script está diseñado para WSL2"
        exit 1
    fi
}

# ============================================
# FASE 1: INSTALACIÓN DE DEPENDENCIAS
# ============================================
instalar_dependencias() {
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
        curl -sLO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
        sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
        rm kubectl
        log_success "kubectl instalado"
    else
        log_info "kubectl ya instalado: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
    fi
    
    # kind
    if ! command -v kind &> /dev/null; then
        log_info "Instalando kind ${KIND_VERSION}..."
        curl -sLo ./kind "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-amd64"
        sudo install -o root -g root -m 0755 kind /usr/local/bin/kind
        rm kind
        log_success "kind instalado"
    else
        log_info "kind ya instalado: $(kind version)"
    fi
    
    # helm
    if ! command -v helm &> /dev/null; then
        log_info "Instalando Helm ${HELM_VERSION}..."
        curl -fsSL https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz -o helm.tar.gz
        tar -zxf helm.tar.gz
        sudo install -o root -g root -m 0755 linux-amd64/helm /usr/local/bin/helm
        rm -rf linux-amd64 helm.tar.gz
        log_success "Helm instalado"
    else
        log_info "Helm ya instalado: $(helm version --short)"
    fi
    
    log_success "Todas las dependencias instaladas correctamente"
}

# ============================================
# FASE 2: CREAR CLUSTER KUBERNETES
# ============================================
crear_cluster() {
    log_phase "FASE 2/7: Creando cluster Kubernetes local con Kind"
    
    if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
        log_warn "El cluster '${CLUSTER_NAME}' ya existe. Se eliminará y recreará."
        kind delete cluster --name "${CLUSTER_NAME}"
    fi
    
    log_info "Creando cluster con configuración personalizada..."
    kind create cluster --name "${CLUSTER_NAME}" --config "${SCRIPT_DIR}/config/kind-config.yaml"
    
    log_info "Esperando a que el cluster esté listo..."
    kubectl wait --for=condition=Ready nodes --all --timeout=120s
    
    log_success "Cluster '${CLUSTER_NAME}' creado y funcionando"
    kubectl get nodes
}

# ============================================
# FASE 3: INSTALAR ARGO CD
# ============================================
instalar_argocd() {
    log_phase "FASE 3/7: Instalando Argo CD (GitOps Engine)"
    
    log_info "Creando namespace argocd..."
    kubectl create namespace argocd 2>/dev/null || true
    
    log_info "Instalando Argo CD ${ARGOCD_VERSION}..."
    kubectl apply -n argocd -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"
    
    log_info "Configurando Argo CD para entorno de aprendizaje..."
    
    # Patch para modo HTTP sin autenticación
    kubectl patch configmap argocd-cmd-params-cm -n argocd --type merge -p '{
      "data": {
        "server.insecure": "true"
      }
    }'
    
    # Patch para acceso anónimo con permisos de admin
    kubectl patch configmap argocd-cm -n argocd --type merge -p '{
      "data": {
        "users.anonymous.enabled": "true"
      }
    }'
    
    kubectl patch configmap argocd-rbac-cm -n argocd --type merge -p '{
      "data": {
        "policy.default": "role:admin"
      }
    }'
    
    # Exponer vía NodePort
    log_info "Exponiendo Argo CD en puerto 30080..."
    kubectl patch service argocd-server -n argocd --type merge -p '{
      "spec": {
        "type": "NodePort",
        "ports": [
          {
            "name": "http",
            "port": 80,
            "targetPort": 8080,
            "nodePort": 30080,
            "protocol": "TCP"
          }
        ]
      }
    }'
    
    # Reiniciar pods para aplicar cambios
    log_info "Reiniciando componentes de Argo CD..."
    kubectl rollout restart deployment argocd-server -n argocd
    kubectl rollout restart deployment argocd-repo-server -n argocd
    kubectl rollout restart statefulset argocd-application-controller -n argocd
    
    log_info "Esperando a que Argo CD esté completamente listo..."
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-repo-server -n argocd
    kubectl wait --for=condition=ready --timeout=300s pod -l app.kubernetes.io/name=argocd-application-controller -n argocd
    
    log_success "Argo CD instalado y configurado"
    log_info "Acceso: http://localhost:30080"
}

# ============================================
# FASE 4: DESPLEGAR GITEA
# ============================================
desplegar_gitea() {
    log_phase "FASE 4/7: Desplegando Gitea (Git Server - Source of Truth)"
    
    log_info "Creando namespace gitea..."
    kubectl create namespace gitea 2>/dev/null || true
    
    log_info "Aplicando manifests de Gitea..."
    kubectl apply -f "${SCRIPT_DIR}/gitops-manifests/gitops-tools/gitea/"
    
    log_info "Esperando a que Gitea esté listo..."
    kubectl wait --for=condition=available --timeout=300s deployment/gitea -n gitea
    
    # Esperar a que el pod esté completamente Running
    log_info "Verificando que el pod de Gitea está Running..."
    while true; do
        POD_STATUS=$(kubectl get pods -n gitea -l app=gitea -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "")
        if [ "$POD_STATUS" = "Running" ]; then
            break
        fi
        echo -n "."
        sleep 2
    done
    echo ""
    
    # Esperar a que el servicio responda
    log_info "Esperando a que la API de Gitea responda..."
    MAX_RETRIES=30
    RETRY_COUNT=0
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        if curl -sf "${GITEA_URL}/api/v1/version" > /dev/null 2>&1; then
            break
        fi
        echo -n "."
        sleep 2
        RETRY_COUNT=$((RETRY_COUNT + 1))
    done
    echo ""
    
    if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
        log_error "Gitea no respondió en el tiempo esperado"
        exit 1
    fi
    
    log_success "Gitea desplegado y funcionando"
    log_info "Acceso: ${GITEA_URL}"
    log_info "Usuario: ${GITEA_USER} / Password: ${GITEA_PASSWORD}"
}

# ============================================
# FASE 5: INICIALIZAR REPOSITORIOS EN GITEA
# ============================================
inicializar_repos_gitea() {
    log_phase "FASE 5/7: Inicializando repositorios en Gitea"
    
    # Crear directorio para credenciales
    mkdir -p "$HOME/.gitops-credentials"
    
    # Obtener o crear token de API
    log_info "Configurando token de API..."
    if [ -f "$GITEA_TOKEN_FILE" ]; then
        GITEA_TOKEN=$(cat "$GITEA_TOKEN_FILE")
        log_info "Token existente encontrado"
    else
        log_info "Creando nuevo token de API..."
        GITEA_TOKEN=$(curl -s -X POST "${GITEA_URL}/api/v1/users/${GITEA_USER}/tokens" \
            -H "Content-Type: application/json" \
            -u "${GITEA_USER}:${GITEA_PASSWORD}" \
            -d "{
                \"name\": \"gitops-bootstrap-$(date +%s)\",
                \"scopes\": [\"write:repository\", \"write:user\"]
            }" | jq -r '.sha1')
        
        if [ -z "$GITEA_TOKEN" ] || [ "$GITEA_TOKEN" == "null" ]; then
            log_error "No se pudo crear el token de API"
            exit 1
        fi
        
        echo "$GITEA_TOKEN" > "$GITEA_TOKEN_FILE"
        chmod 600 "$GITEA_TOKEN_FILE"
    fi
    
    # Función para crear repo en Gitea
    crear_repo_gitea() {
        local repo_name=$1
        log_info "Creando repositorio: ${repo_name}"
        
        # Verificar si ya existe
        if curl -sf "${GITEA_URL}/api/v1/repos/${GITEA_USER}/${repo_name}" \
            -H "Authorization: token ${GITEA_TOKEN}" > /dev/null 2>&1; then
            log_warn "  Repositorio '${repo_name}' ya existe, saltando creación..."
            return 0
        fi
        
        # Crear repositorio
        curl -s -X POST "${GITEA_URL}/api/v1/user/repos" \
            -H "Authorization: token ${GITEA_TOKEN}" \
            -H "Content-Type: application/json" \
            -d "{
                \"name\": \"${repo_name}\",
                \"private\": false,
                \"auto_init\": false,
                \"default_branch\": \"main\"
            }" > /dev/null
        
        log_success "  Repositorio '${repo_name}' creado"
    }
    
    # Función para push a Gitea
    push_to_gitea() {
        local repo_name=$1
        local local_path=$2
        local gitea_url="http://${GITEA_USER}:${GITEA_TOKEN}@localhost:30083/${GITEA_USER}/${repo_name}.git"
        
        log_info "Haciendo push de ${repo_name}..."
        
        cd "${local_path}"
        
        # Inicializar git si no existe
        if [ ! -d ".git" ]; then
            git init
            git checkout -b main 2>/dev/null || git branch -M main
            git add .
            git commit -m "Initial commit: Bootstrap desde dotfiles local"
        fi
        
        # Configurar remote
        if git remote | grep -q "^gitea$"; then
            git remote set-url gitea "${gitea_url}"
        else
            git remote add gitea "${gitea_url}"
        fi
        
        # Push
        git push -u gitea main --force
        
        log_success "  Push completado: ${repo_name}"
    }
    
    # Crear repos en Gitea
    crear_repo_gitea "gitops-manifests"
    crear_repo_gitea "app-reloj"
    crear_repo_gitea "visor-gitops"
    
    # Push repositorios
    push_to_gitea "gitops-manifests" "${SCRIPT_DIR}/gitops-manifests"
    push_to_gitea "app-reloj" "${SCRIPT_DIR}/gitops-source-code/app-reloj"
    push_to_gitea "visor-gitops" "${SCRIPT_DIR}/gitops-source-code/visor-gitops"
    
    # Configurar credentials en Argo CD
    log_info "Configurando credenciales de Gitea en Argo CD..."
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
  url: http://gitea.gitea.svc.cluster.local:3000/gitops
  username: ${GITEA_USER}
  password: ${GITEA_PASSWORD}
EOF
    
    log_success "Repositorios inicializados en Gitea"
}

# ============================================
# FASE 6: BOOTSTRAP GITOPS (ROOT APP)
# ============================================
bootstrap_gitops() {
    log_phase "FASE 6/7: Activando GitOps desde Gitea"
    
    log_info "Aplicando root-app (App of Apps)..."
    kubectl apply -f "${SCRIPT_DIR}/bootstrap/root-app.yaml"
    
    log_info "Esperando a que root-app se sincronice..."
    sleep 10
    
    # Esperar a que las aplicaciones se creen
    log_info "Verificando que las aplicaciones se están desplegando..."
    kubectl wait --for=condition=available --timeout=60s application/root -n argocd 2>/dev/null || true
    
    log_success "GitOps activado - Argo CD ahora gestiona todo desde Gitea"
    log_info "Las aplicaciones se desplegarán automáticamente:"
    log_info "  - Sealed Secrets (gestión de secretos)"
    log_info "  - Docker Registry (almacenamiento de imágenes)"
    log_info "  - Todas las GitOps Tools (via ApplicationSet)"
    log_info "  - Custom Apps (via ApplicationSet)"
}

# ============================================
# FASE 7: VERIFICACIÓN
# ============================================
verificar_despliegue() {
    log_phase "FASE 7/7: Verificando despliegue completo"
    
    log_info "Esperando a que todas las aplicaciones se sincronicen..."
    sleep 20
    
    echo ""
    log_info "📋 Aplicaciones en Argo CD:"
    kubectl get applications -n argocd
    
    echo ""
    log_info "🔍 Pods en el cluster:"
    kubectl get pods --all-namespaces | grep -v "kube-system"
    
    echo ""
    log_success "¡Instalación completada!"
}

# ============================================
# FUNCIÓN PRINCIPAL
# ============================================
main() {
    clear
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║                                                               ║"
    echo "║        🚀 ENTORNO DE APRENDIZAJE GITOPS - BOOTSTRAP 🚀       ║"
    echo "║                                                               ║"
    echo "║  Este script instalará un entorno GitOps completo:           ║"
    echo "║  • Cluster Kubernetes (Kind)                                 ║"
    echo "║  • Gitea (Git Server interno - Source of Truth)              ║"
    echo "║  • Argo CD (GitOps Continuous Delivery)                      ║"
    echo "║  • Sealed Secrets (Gestión de secretos)                      ║"
    echo "║  • Docker Registry (Almacenamiento de imágenes)              ║"
    echo "║  • Todas las herramientas GitOps                             ║"
    echo "║                                                               ║"
    echo "║  Flujo: Local → Gitea → Argo CD → Kubernetes                 ║"
    echo "║                                                               ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
    
    comprobar_wsl
    
    # Ejecutar fases
    instalar_dependencias
    crear_cluster
    instalar_argocd
    desplegar_gitea
    inicializar_repos_gitea
    bootstrap_gitops
    verificar_despliegue
    
    # Resumen final
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}✨ ¡INSTALACIÓN COMPLETADA EXITOSAMENTE! ✨${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${BLUE}🌐 URLs de acceso:${NC}"
    echo "  • Argo CD:      http://localhost:30080"
    echo "  • Gitea:        http://localhost:30083"
    echo "    - Usuario:    ${GITEA_USER}"
    echo "    - Password:   ${GITEA_PASSWORD}"
    echo ""
    echo -e "${BLUE}📦 Repositorios en Gitea:${NC}"
    echo "  • http://localhost:30083/gitops/gitops-manifests"
    echo "  • http://localhost:30083/gitops/app-reloj"
    echo "  • http://localhost:30083/gitops/visor-gitops"
    echo ""
    echo -e "${BLUE}🎯 Próximos pasos:${NC}"
    echo "  1. Abre Argo CD y observa las aplicaciones sincronizándose"
    echo "  2. Explora Gitea y verifica los repositorios"
    echo "  3. Haz cambios en gitops-manifests/ y haz push a Gitea"
    echo "  4. Observa cómo Argo CD detecta y aplica los cambios automáticamente"
    echo ""
    echo -e "${YELLOW}💡 Tip: Todo está sincronizado desde Gitea (source of truth)${NC}"
    echo "     GitHub solo se usó para la distribución inicial del proyecto"
    echo ""
}

# Ejecutar
main "$@"
