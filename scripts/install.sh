#!/bin/bash

# 🚀 Master GitOps Installer - Orquestador principal
# Ejecuta toda la instalación en orden correcto

set -e

echo "🚀 INSTALADOR MASTER GITOPS"
echo "=============================================="
echo "Este script instalará un entorno GitOps completo:"
echo ""
echo "📋 Componentes a instalar:"
echo "  🔧 Sistema base (zsh, git, herramientas)"  
echo "  🐳 Docker + kubectl + kind"
echo "  🏗️ Cluster Kubernetes + ArgoCD"
echo "  🚀 GitOps (Gitea + aplicaciones)"
echo ""
echo "📊 Stack de observabilidad:"
echo "  📈 Prometheus (métricas)"
echo "  📊 Grafana (dashboards)"
echo "  🎯 Hello World moderna (con métricas)"
echo "  📱 Kubernetes Dashboard"
echo ""
echo "⏱️ Tiempo estimado: 15-20 minutos"
echo ""

read -p "¿Continuar con la instalación? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Instalación cancelada"
    exit 1
fi

DOTFILES_DIR="/home/asanchez/Code/dotfiles"
cd "$DOTFILES_DIR"

# --- Funciones auxiliares ---
log_step() {
    echo ""
    echo "🚀 PASO: $1"
    echo "----------------------------------------"
}

log_success() {
    echo "✅ $1"
}

log_error() {
    echo "❌ ERROR: $1" >&2
}

# --- Verificar prerequisitos ---
log_step "Verificando prerequisitos"

if [ ! -f "setup/install-system.sh" ]; then
    log_error "Scripts de setup no encontrados. ¿Estás en el directorio dotfiles?"
    exit 1
fi

if ! id -nG | grep -qw "sudo"; then
    log_error "Tu usuario necesita permisos sudo"
    exit 1
fi

log_success "Prerequisitos verificados"

# --- PASO 0: Aplicar fixes GitOps ---
log_step "Aplicando fixes GitOps para instalación desatendida"
if ! ./scripts/apply-fixes.sh; then
    log_error "Falló la aplicación de fixes GitOps"
    exit 1
fi

# --- PASO 1: Sistema base ---
log_step "Instalando sistema base (herramientas Linux)"
if ! ./setup/install-system.sh; then
    log_error "Falló la instalación del sistema base"
    exit 1
fi

# --- PASO 2: Docker y K8s tools ---
log_step "Instalando Docker y herramientas Kubernetes"  
if ! ./setup/install-docker.sh; then
    log_error "Falló la instalación de Docker"
    exit 1
fi

# --- PASO 3: Cluster ---
log_step "Creando cluster Kubernetes + ArgoCD"
if ! ./setup/install-cluster.sh; then
    log_error "Falló la creación del cluster"
    exit 1
fi

# --- PASO 4: GitOps completo ---
log_step "Configurando GitOps completo"
if ! ./gitops/bootstrap/install-gitops.sh; then
    log_error "Falló la configuración GitOps"
    exit 1
fi

# --- PASO 5: Scripts de acceso ---
log_step "Configurando scripts de acceso"

# Crear scripts de acceso rápido
cat > "$DOTFILES_DIR/scripts/dashboard.sh" << 'EOF'
#!/bin/bash
# Acceso rápido al Dashboard con skip login
echo "🚀 Abriendo Kubernetes Dashboard..."
echo "💡 En la pantalla de login, haz click en 'SKIP'"
cmd.exe /c start https://$(hostname -I | awk '{print $1}'):30081 2>/dev/null || \
xdg-open https://$(hostname -I | awk '{print $1}'):30081 2>/dev/null || \
echo "🌐 Abre manualmente: https://$(hostname -I | awk '{print $1}'):30081"
EOF

cat > "$DOTFILES_DIR/scripts/open-dashboard.sh" << 'EOF'  
#!/bin/bash
# Dashboard con token automático
echo "🔑 Generando token de Dashboard..."
TOKEN=$(kubectl -n kubernetes-dashboard create token admin-user 2>/dev/null || echo "ERROR")
if [ "$TOKEN" != "ERROR" ]; then
    echo "$TOKEN" | clip.exe 2>/dev/null || echo "$TOKEN" | xclip -selection clipboard 2>/dev/null || echo "Token: $TOKEN"
    echo "✅ Token copiado al portapapeles"
fi
echo "🚀 Abriendo Dashboard..."
cmd.exe /c start https://$(hostname -I | awk '{print $1}'):30081
EOF

cat > "$DOTFILES_DIR/scripts/check-status.sh" << 'EOF'
#!/bin/bash
# Verificador de estado del sistema
echo "🔍 Estado del entorno GitOps"
echo "============================"
echo ""
echo "🏗️ Cluster:"
kubectl cluster-info --context kind-mini-cluster 2>/dev/null && echo "  ✅ Activo" || echo "  ❌ Inactivo"
echo ""
echo "📊 Aplicaciones ArgoCD:"
kubectl get applications -n argocd 2>/dev/null || echo "  ❌ Error obteniendo aplicaciones"
echo ""
echo "🌐 Servicios expuestos:"
kubectl get services --all-namespaces | grep NodePort
echo ""
WSL_IP=$(hostname -I | awk '{print $1}')
echo "🔗 URLs de acceso:"
echo "   ArgoCD:     http://$WSL_IP:30080"
echo "   Gitea:      http://$WSL_IP:30083"  
echo "   Dashboard:  https://$WSL_IP:30081"
echo "   Hello World: http://$WSL_IP:30082"
echo "   Prometheus: http://$WSL_IP:30092"
echo "   Grafana:    http://$WSL_IP:30093"
EOF

# Hacer ejecutables
chmod +x "$DOTFILES_DIR/scripts"/*.sh

# --- Configurar aliases ---
log_step "Configurando aliases de acceso rápido"

cat > "$DOTFILES_DIR/.gitops_aliases" << 'EOF'
# 🚀 Aliases GitOps
alias dashboard='~/dotfiles/scripts/dashboard.sh'
alias dashboard-full='~/dotfiles/scripts/open-dashboard.sh' 
alias k8s-dash='~/dotfiles/scripts/dashboard.sh'
alias check-gitops='~/dotfiles/scripts/check-status.sh'

# Servicios principales
alias argocd='cmd.exe /c start http://$(hostname -I | awk "{print \$1}"):30080 2>/dev/null || echo "ArgoCD: http://$(hostname -I | awk "{print \$1}"):30080"'
alias gitea='cmd.exe /c start http://$(hostname -I | awk "{print \$1}"):30083 2>/dev/null || echo "Gitea: http://$(hostname -I | awk "{print \$1}"):30083"'
alias prometheus='cmd.exe /c start http://$(hostname -I | awk "{print \$1}"):30092 2>/dev/null || echo "Prometheus: http://$(hostname -I | awk "{print \$1}"):30092"'
alias grafana='cmd.exe /c start http://$(hostname -I | awk "{print \$1}"):30093 2>/dev/null || echo "Grafana: http://$(hostname -I | awk "{print \$1}"):30093"'

echo "🚀 Aliases GitOps cargados:"
echo "   dashboard      - Dashboard con skip login"
echo "   dashboard-full - Dashboard con token"
echo "   check-gitops   - Verificar estado"
echo "   argocd         - Abrir ArgoCD"
echo "   gitea          - Abrir Gitea"  
echo "   prometheus     - Abrir Prometheus"
echo "   grafana        - Abrir Grafana"
EOF

# Agregar al zshrc si no existe
if ! grep -q "GitOps aliases" ~/.zshrc 2>/dev/null; then
    {
        echo ""
        echo "# 🚀 GitOps aliases"
        echo "source $DOTFILES_DIR/.gitops_aliases"
    } >> ~/.zshrc
fi

# --- Verificar instalación final ---
log_step "Verificando instalación final"

echo ""
echo "📊 Estado de aplicaciones ArgoCD:"
kubectl get applications -n argocd 2>/dev/null || echo "❌ Error obteniendo aplicaciones"

sleep 5

# Forzar sincronización
echo ""
echo "🔄 Forzando sincronización de aplicaciones..."
kubectl patch application kubernetes-dashboard -n argocd --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' 2>/dev/null || true
kubectl patch application hello-world -n argocd --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' 2>/dev/null || true
kubectl patch application prometheus -n argocd --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' 2>/dev/null || true
kubectl patch application grafana -n argocd --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' 2>/dev/null || true

echo ""
echo "🎉 ¡INSTALACIÓN COMPLETADA!"
echo "=============================================="
echo ""
echo "🌐 URLs de acceso (desde Windows):"
WSL_IP=$(hostname -I | awk '{print $1}')
echo "   📍 Desde WSL/Linux:"
echo "      ArgoCD:       http://$WSL_IP:30080 (admin/[SECURE_PASSWORD])"
echo "      Gitea:        http://$WSL_IP:30083 (gitops/[SECURE_PASSWORD])"
echo "      Dashboard:    https://$WSL_IP:30081 (SKIP login)"
echo "      Hello World:  http://$WSL_IP:30082 (con métricas)"
echo "      Prometheus:   http://$WSL_IP:30092 (métricas)"
echo "      Grafana:      http://$WSL_IP:30093 (admin/[SECURE_PASSWORD])"
echo ""
echo "   🪟 Desde Windows:"
echo "      ArgoCD:       http://localhost:30080"
echo "      Gitea:        http://localhost:30083" 
echo "      Dashboard:    https://localhost:30081"
echo "      Hello World:  http://localhost:30082"
echo "      Prometheus:   http://localhost:30092"
echo "      Grafana:      http://localhost:30093"
echo ""
echo "🚀 Comandos de acceso rápido (después de reiniciar terminal):"
echo "   dashboard       - Dashboard con skip login"
echo "   argocd          - ArgoCD UI"
echo "   prometheus      - Métricas"
echo "   grafana         - Dashboards"
echo "   check-gitops    - Verificar estado"
echo ""
echo "💡 IMPORTANTE:"
echo "   - Reinicia tu terminal para cargar aliases: 'source ~/.zshrc'"
echo "   - Todas las apps deberían mostrar 'Synced & Healthy' en ArgoCD"
echo "   - Para Windows: usa URLs con 'localhost' (mejor compatibilidad)"
echo ""
echo "🔍 Verificar estado: ./scripts/check-status.sh"
echo "📚 Documentación completa: README.md"

log_success "¡Entorno GitOps enterprise listo para usar!"