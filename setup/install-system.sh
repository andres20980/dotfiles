#!/bin/bash

# 🔧 Sistema Base - Solo herramientas del sistema Linux/WSL
# NO incluye Docker ni Kubernetes

set -e

echo "🔧 Instalando herramientas base del sistema..."
echo "=============================================="

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

# --- Actualizar sistema ---
log_step "Actualizando sistema Ubuntu/WSL..."
sudo apt update -y
sudo apt upgrade -y

# --- Instalar herramientas básicas ---
log_step "Instalando herramientas básicas..."
sudo apt install -y \
    curl \
    wget \
    git \
    unzip \
    ca-certificates \
    gnupg \
    lsb-release \
    jq \
    tree \
    htop \
    vim \
    zsh

# --- Instalar Oh My Zsh ---
log_step "Instalando Oh My Zsh..."
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    log_success "Oh My Zsh instalado"
else
    log_success "Oh My Zsh ya está instalado"
fi

# --- Configurar zsh como shell por defecto ---
log_step "Configurando zsh como shell por defecto..."
if [ "$SHELL" != "/usr/bin/zsh" ]; then
    chsh -s /usr/bin/zsh
    log_success "zsh configurado como shell por defecto"
else
    log_success "zsh ya es el shell por defecto"
fi

# --- Instalar Git Credential Manager ---
log_step "Instalando Git Credential Manager..."
if ! command -v git-credential-manager &> /dev/null; then
    curl -L https://aka.ms/gcm/linux-install-source.sh | sh
    git-credential-manager configure
    log_success "Git Credential Manager instalado y configurado"
else
    log_success "Git Credential Manager ya está instalado"
fi

# --- Configurar aliases básicos ---
log_step "Configurando aliases básicos..."
cat >> ~/.zshrc << 'EOF'

# Aliases básicos
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias ..='cd ..'
alias ...='cd ../..'
alias grep='grep --color=auto'
EOF

log_success "Sistema base instalado correctamente"
echo ""
echo "💡 NOTA: Reinicia tu terminal para aplicar los cambios de zsh"
echo "💡 Siguiente paso: ./setup/install-docker.sh"