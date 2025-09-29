#!/bin/bash

# 🚀 GitOps Bootstrap Simplificado - Solo manifests locales
# Aplica manifests directamente desde el sistema de archivos (agnóstico al usuario)

set -e

echo "🚀 Configurando GitOps simplificado..."
echo "================================="

# --- Funciones auxiliares ---
log_step() {
    echo "📋 $1"
}

log_success() {
    echo "✅ $1"
}

log_info() {
    echo "💡 $1"
}

# Detectar directorio base automáticamente (agnóstico al usuario)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "📁 Directorio base detectado: $DOTFILES_DIR"

# --- Verificar prerequisitos ---
log_step "Verificando prerequisitos..."

if ! command -v kubectl &> /dev/null; then
    log_info "kubectl no está instalado"
    exit 1
fi

if ! kubectl cluster-info &> /dev/null; then
    log_info "No hay cluster Kubernetes disponible"
    exit 1
fi

if [[ ! -d "$DOTFILES_DIR/manifests" ]]; then
    log_info "Error: No se encontró $DOTFILES_DIR/manifests/"
    exit 1
fi

# --- Construir imagen hello-world-modern ---
log_step "Construyendo imagen hello-world-modern..."
if [[ -d "$DOTFILES_DIR/source-code/hello-world-modern" ]]; then
    cd "$DOTFILES_DIR/source-code/hello-world-modern"
    docker build -t hello-world-modern:latest . || log_info "Error construyendo imagen"

    log_step "Cargando imagen en cluster kind..."
    kind load docker-image hello-world-modern:latest --name mini-cluster || log_info "Error cargando imagen en kind"
else
    log_info "No se encontró código fuente de hello-world-modern"
fi

# --- Aplicar manifests directamente ---
log_step "Aplicando manifests desde: $DOTFILES_DIR/manifests/"

# Aplicar manifests en orden correcto (namespaces primero)
log_step "Desplegando infraestructura..."
if [[ -d "$DOTFILES_DIR/manifests/infrastructure" ]]; then
    # Primero aplicar namespaces
    find "$DOTFILES_DIR/manifests/infrastructure" -name "*namespace*" -type f -exec kubectl apply -f {} \; 2>/dev/null || true
    
    # Luego aplicar todo lo demás
    kubectl apply -f "$DOTFILES_DIR/manifests/infrastructure/" --recursive || log_info "Algunos manifests de infraestructura fallaron"
else
    log_info "No se encontró directorio de infraestructura"
fi

# Aplicar aplicaciones (Hello World, etc.)
log_step "Desplegando aplicaciones..." 
if [[ -d "$DOTFILES_DIR/manifests/applications" ]]; then
    # Crear namespace hello-world si no existe
    kubectl create namespace hello-world --dry-run=client -o yaml | kubectl apply -f -
    
    # Aplicar manifests de aplicaciones
    kubectl apply -f "$DOTFILES_DIR/manifests/applications/" --recursive || log_info "Algunos manifests de aplicaciones fallaron"
else
    log_info "No se encontró directorio de aplicaciones"
fi

# --- Configurar Dashboard con skip-login ---
log_step "Configurando Dashboard con skip-login..."
kubectl create clusterrolebinding kubernetes-dashboard-admin \
    --clusterrole=cluster-admin \
    --serviceaccount=kubernetes-dashboard:kubernetes-dashboard \
    --dry-run=client -o yaml | kubectl apply -f -

# --- Esperar a que los pods estén funcionando ---
log_step "Esperando a que todos los servicios estén listos..."

# Esperar a Dashboard
kubectl wait --for=condition=available --timeout=120s deployment/kubernetes-dashboard -n kubernetes-dashboard 2>/dev/null || log_info "Dashboard aún iniciando"

# Esperar a Prometheus  
kubectl wait --for=condition=available --timeout=120s deployment/prometheus -n monitoring 2>/dev/null || log_info "Prometheus aún iniciando"

# Esperar a Grafana
kubectl wait --for=condition=available --timeout=120s deployment/grafana -n monitoring 2>/dev/null || log_info "Grafana aún iniciando"

# Esperar a Hello World
kubectl wait --for=condition=available --timeout=120s deployment/hello-world -n default 2>/dev/null || log_info "Hello World aún iniciando"

log_success "GitOps simplificado configurado correctamente"
echo ""
echo "🎉 Ecosistema GitOps completo instalado!"
echo ""
echo "🌐 URLs disponibles:"
echo "   ArgoCD:      http://localhost:30080 (admin/admin123)"
echo "   Dashboard:   https://localhost:30081 (skip login habilitado)"
echo "   Hello World: http://localhost:30082 (con métricas Prometheus)"
echo "   Prometheus:  http://localhost:30092 (métricas del cluster)"
echo "   Grafana:     http://localhost:30093 (admin/admin123)"
echo ""
echo "📊 Verificar estado:"
echo "   kubectl get pods --all-namespaces"
echo "   kubectl get svc --all-namespaces"
echo ""
echo "✨ Entorno educativo GitOps listo para aprender!"
echo "💡 Modo simplificado: Manifests aplicados directamente (sin repositorios Git)"