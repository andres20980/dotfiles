#!/bin/bash

# 🔐 GitOps Secure Installation - FLUJO COMPLETO SEGURO
# Instala GitOps completo con credenciales seguras generadas dinámicamente
# Elimina TODAS las credenciales hardcodeadas

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "🔐 INSTALACIÓN GITOPS SEGURA"
echo "============================"
echo "📁 Directorio: $DOTFILES_DIR"
echo ""

# --- Validar herramientas necesarias ---
if ! command -v openssl >/dev/null 2>&1; then
    echo "❌ ERROR: openssl no encontrado (necesario para generar passwords)"
    exit 1
fi

if ! command -v envsubst >/dev/null 2>&1; then
    echo "❌ ERROR: envsubst no encontrado (necesario para templates)"
    sudo apt-get update && sudo apt-get install -y gettext-base
fi

# --- Paso 1: Configurar credenciales seguras ---
echo "🎲 Generando credenciales seguras..."

generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-20
}

export GITEA_ADMIN_PASSWORD=$(generate_password)
export ARGOCD_ADMIN_PASSWORD=$(generate_password)
export GRAFANA_ADMIN_PASSWORD=$(generate_password)

echo "✅ Credenciales generadas:"
echo "   Gitea: gitops / $GITEA_ADMIN_PASSWORD"
echo "   ArgoCD: admin / $ARGOCD_ADMIN_PASSWORD"
echo "   Grafana: admin / $GRAFANA_ADMIN_PASSWORD"
echo ""

# Guardar para uso posterior
cat > /tmp/.gitops-credentials-secure <<EOF
# GitOps Secure Credentials - Generated $(date)
export GITEA_ADMIN_PASSWORD='$GITEA_ADMIN_PASSWORD'
export ARGOCD_ADMIN_PASSWORD='$ARGOCD_ADMIN_PASSWORD'
export GRAFANA_ADMIN_PASSWORD='$GRAFANA_ADMIN_PASSWORD'
EOF

echo "💾 Credenciales guardadas en: /tmp/.gitops-credentials-secure"
echo ""

# --- Paso 2: Instalar sistema base ---
echo "🔧 Instalando herramientas base..."
if [[ -f "$DOTFILES_DIR/setup/install-system.sh" ]]; then
    "$DOTFILES_DIR/setup/install-system.sh"
else
    echo "⚠️  Script de sistema no encontrado, continuando..."
fi

# --- Paso 3: Instalar Docker ---
echo "🐳 Instalando Docker..."
if [[ -f "$DOTFILES_DIR/setup/install-docker.sh" ]]; then
    "$DOTFILES_DIR/setup/install-docker.sh"
else
    echo "⚠️  Script de Docker no encontrado, continuando..."
fi

# --- Paso 4: Instalar cluster Kubernetes ---
echo "☸️  Instalando cluster Kubernetes..."
if [[ -f "$DOTFILES_DIR/setup/install-cluster.sh" ]]; then
    "$DOTFILES_DIR/setup/install-cluster.sh"
else
    echo "⚠️  Script de cluster no encontrado, continuando..."
fi

# --- Paso 5: Instalar GitOps con credenciales seguras ---
echo "🚀 Instalando GitOps con credenciales SEGURAS..."
if [[ -f "$DOTFILES_DIR/gitops/bootstrap/install-gitops.sh" ]]; then
    "$DOTFILES_DIR/gitops/bootstrap/install-gitops.sh"
else
    echo "❌ ERROR: Script GitOps no encontrado"
    exit 1
fi

echo ""
echo "🎉 INSTALACIÓN GITOPS SEGURA COMPLETA"
echo "====================================="
echo ""
echo "🔑 CREDENCIALES (guárdalas en un gestor de passwords):"
echo "   Gitea Admin: gitops / $GITEA_ADMIN_PASSWORD"
echo "   ArgoCD Admin: admin / $ARGOCD_ADMIN_PASSWORD"
echo "   Grafana Admin: admin / $GRAFANA_ADMIN_PASSWORD"
echo ""
echo "🌐 URLs de acceso:"
echo "   🗃️  Gitea:   http://localhost:30083"
echo "   🚀 ArgoCD:   http://localhost:30080"
echo "   📊 Grafana:  http://localhost:30093"
echo "   📱 Dashboard: https://localhost:30081"
echo ""
echo "🔐 Para usar credenciales en otros terminales:"
echo "   source /tmp/.gitops-credentials-secure"
echo ""
echo "⚠️  IMPORTANTE:"
echo "   • Las credenciales NO están en el código fuente"
echo "   • Se generan aleatoriamente en cada instalación"
echo "   • Guárdalas en un gestor de passwords seguro"
echo "   • El archivo temporal se elimina al reiniciar"