#!/bin/bash
set -euo pipefail

# 🚀 Entorno de Aprendizaje GitOps - Instalación Completa
# 
# Este script instala TODO lo necesario desde WSL limpio:
# - Dependencias del sistema (Docker, kubectl, kind, helm)
# - Cluster Kubernetes local (Kind)
# - Argo CD configurado para aprendizaje
# - Todas las herramientas GitOps desplegadas automáticamente
#
# Uso: ./install.sh
# Tiempo estimado: 5-10 minutos
# Requisitos: WSL2 con Ubuntu (limpio)

CLUSTER_NAME="gitops-local"
ARGOCD_VERSION="v2.13.2"
KIND_VERSION="v0.24.0"
KUBECTL_VERSION="v1.31.0"
HELM_VERSION="v3.16.2"

# Colores para salida
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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
    log_info "📦 FASE 1/4: Instalando dependencias del sistema..."
    echo ""
    
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
        chmod +x ./kind
        sudo mv ./kind /usr/local/bin/kind
        log_success "kind instalado"
    else
        log_info "kind ya instalado"
    fi
    
    # helm
    if ! command -v helm &> /dev/null; then
        log_info "Instalando Helm ${HELM_VERSION}..."
        curl -fsSL https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz -o helm.tar.gz
        tar -zxf helm.tar.gz
        sudo mv linux-amd64/helm /usr/local/bin/helm
        rm -rf linux-amd64 helm.tar.gz
        log_success "Helm instalado"
    else
        log_info "Helm ya instalado"
    fi
    
    log_success "Todas las dependencias instaladas correctamente"
    echo ""
}

# ============================================
# FASE 2: CREAR CLUSTER KUBERNETES
# ============================================
crear_cluster() {
    log_info "🎯 FASE 2/4: Creando cluster Kubernetes '${CLUSTER_NAME}'..."
    echo ""
    
    if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
        log_warn "El cluster '${CLUSTER_NAME}' ya existe"
        read -p "¿Quieres eliminarlo y crear uno nuevo? (s/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[SsYy]$ ]]; then
            log_info "Eliminando cluster existente..."
            kind delete cluster --name="${CLUSTER_NAME}"
        else
            log_info "Usando cluster existente"
            return 0
        fi
    fi
    
    log_info "Creando cluster (esto puede tardar 2-3 minutos)..."
    kind create cluster --name="${CLUSTER_NAME}" --config=config/kind-config.yaml --wait 5m
    
    log_info "Verificando cluster..."
    kubectl cluster-info --context "kind-${CLUSTER_NAME}"
    kubectl get nodes
    
    log_success "Cluster Kubernetes creado correctamente"
    echo ""
}

# ============================================
# FASE 3: INSTALAR Y CONFIGURAR ARGO CD
# ============================================
instalar_argocd() {
    log_info "🔧 FASE 3/4: Instalando Argo CD ${ARGOCD_VERSION}..."
    echo ""
    
    log_info "Creando namespace argocd..."
    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
    
    log_info "Instalando componentes de Argo CD..."
    kubectl apply -n argocd -f \
        "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"
    
    log_info "Esperando CRDs de Argo CD..."
    sleep 10
    
    log_info "Configurando Argo CD para entorno de aprendizaje..."
    
    # 1. Modo inseguro (HTTP sin TLS)
    kubectl patch configmap argocd-cmd-params-cm -n argocd --type merge -p '{
      "data": {
        "server.insecure": "true"
      }
    }'
    
    # 2. Acceso anónimo habilitado + reconciliación cada 3 minutos
    kubectl patch configmap argocd-cm -n argocd --type merge -p '{
      "data": {
        "users.anonymous.enabled": "true",
        "timeout.reconciliation": "180s"
      }
    }'
    
    # 3. Usuarios anónimos con rol admin
    kubectl patch configmap argocd-rbac-cm -n argocd --type merge -p '{
      "data": {
        "policy.default": "role:admin"
      }
    }'
    
    # 4. Exponer en NodePort 30080
    log_info "Exponiendo Argo CD en NodePort 30080..."
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
    
    log_info "Reiniciando servidor de Argo CD..."
    kubectl rollout restart deployment argocd-server -n argocd
    
    log_info "Esperando a que Argo CD esté completamente funcional (puede tardar 2-3 minutos)..."
    kubectl wait --for=condition=available --timeout=300s \
        deployment/argocd-server -n argocd
    kubectl wait --for=condition=available --timeout=300s \
        deployment/argocd-repo-server -n argocd
    kubectl wait --for=condition=available --timeout=300s \
        deployment/argocd-applicationset-controller -n argocd
    
    log_success "Argo CD instalado y configurado correctamente"
    echo ""
}

# ============================================
# FASE 4: DESPLEGAR APLICACIONES GITOPS
# ============================================
desplegar_aplicaciones_gitops() {
    log_info "🌳 FASE 4/4: Desplegando aplicaciones GitOps (patrón App of Apps)..."
    echo ""
    
    log_info "Aplicando Root Application..."
    kubectl apply -f bootstrap/root-app.yaml
    
    log_info "Esperando sincronización inicial..."
    sleep 5
    
    log_info "Estado de aplicaciones en Argo CD:"
    kubectl get applications -n argocd 2>/dev/null || log_warn "Aplicaciones aún no creadas (esto es normal)"
    
    log_success "Root Application desplegada"
    log_info "Argo CD está sincronizando todas las aplicaciones automáticamente..."
    echo ""
}

# ============================================
# MOSTRAR INFORMACIÓN FINAL
# ============================================
mostrar_informacion_final() {
    echo ""
    echo "╔═══════════════════════════════════════════════════════════════════╗"
    echo "║                                                                   ║"
    echo "║         ✨ INSTALACIÓN COMPLETADA EXITOSAMENTE ✨                ║"
    echo "║                                                                   ║"
    echo "╚═══════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "🌐 ACCESO A SERVICIOS:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  🎯 Argo CD (Motor GitOps)"
    echo "     👉 http://localhost:30080"
    echo "     ℹ️  Sin login necesario - acceso anónimo habilitado"
    echo ""
    echo "  Una vez que Argo CD sincronice todo (~2-3 minutos), tendrás:"
    echo ""
    echo "  🔧 Gitea (Servidor Git)"
    echo "     👉 http://localhost:30083"
    echo "     🔑 Usuario: gitops / Contraseña: gitops"
    echo ""
    echo "  📦 Docker Registry (Registro Interno)"
    echo "     👉 localhost:30087"
    echo ""
    echo "  ⚙️  Argo Workflows (CI/CD)"
    echo "     👉 http://localhost:30091"
    echo ""
    echo "  📊 Prometheus (Métricas)"
    echo "     👉 http://localhost:30092"
    echo ""
    echo "  📈 Grafana (Dashboards)"
    echo "     👉 http://localhost:30093"
    echo ""
    echo "  🎛️  Kubernetes Dashboard"
    echo "     �� http://localhost:30085"
    echo ""
    echo "  🚀 Aplicaciones de Ejemplo:"
    echo "     👉 app-reloj:      http://localhost:30098"
    echo "     👉 visor-gitops:   http://localhost:30099"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "📋 PRÓXIMOS PASOS:"
    echo ""
    echo "  1. Abre Argo CD: http://localhost:30080"
    echo "  2. Observa cómo sincroniza todas las aplicaciones automáticamente"
    echo "  3. Espera ~3 minutos hasta que todo esté en estado 'Synced' y 'Healthy'"
    echo "  4. ¡Explora el entorno GitOps completo!"
    echo ""
    echo "📖 DOCUMENTACIÓN:"
    echo "  • README.md - Arquitectura y flujos GitOps explicados"
    echo "  • Experimenta con los ejemplos de la documentación"
    echo ""
    echo "🆘 RESOLUCIÓN DE PROBLEMAS:"
    echo "  • Ver apps:        kubectl get applications -n argocd"
    echo "  • Ver pods:        kubectl get pods -A"
    echo "  • Logs Argo CD:    kubectl logs -n argocd deploy/argocd-server"
    echo "  • Forzar sync:     kubectl patch app <NOMBRE> -n argocd -p '{\"operation\":{\"sync\":{}}}' --type merge"
    echo ""
    echo "💡 CONSEJO: Mantén Argo CD abierto mientras trabajas para ver GitOps en acción"
    echo ""
}

# ============================================
# SCRIPT PRINCIPAL
# ============================================
main() {
    clear
    echo "╔═══════════════════════════════════════════════════════════════════╗"
    echo "║                                                                   ║"
    echo "║         🚀 Instalador del Entorno de Aprendizaje GitOps 🚀       ║"
    echo "║                                                                   ║"
    echo "║                    100% Best Practices GitOps                     ║"
    echo "║                                                                   ║"
    echo "╚═══════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Este script instalará un entorno GitOps completo en tu WSL:"
    echo ""
    echo "  • Docker + kubectl + kind + helm"
    echo "  • Cluster Kubernetes local"
    echo "  • Argo CD + Herramientas GitOps"
    echo "  • Aplicaciones de ejemplo"
    echo ""
    echo "⏱️  Tiempo estimado: 5-10 minutos"
    echo ""
    read -p "¿Continuar con la instalación? (S/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[SsYy]$ ]] && [[ ! -z $REPLY ]]; then
        log_info "Instalación cancelada"
        exit 0
    fi
    
    echo ""
    log_info "🚀 Iniciando instalación..."
    echo ""
    
    comprobar_wsl
    instalar_dependencias
    crear_cluster
    instalar_argocd
    desplegar_aplicaciones_gitops
    mostrar_informacion_final
}

# Ejecutar script principal
main
