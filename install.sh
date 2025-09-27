#!/bin/bash

# Script para configurar un nuevo entorno de desarrollo en Ubuntu

echo "🚀 Empezando la configuración..."

# --- Actualizar paquetes ---
echo "🔄 Actualizando lista de paquetes..."
sudo apt-get update

# --- Instalar paquetes esenciales con APT ---
echo "📦 Instalando paquetes esenciales (jq, pip, zsh, htop...)"
sudo apt-get install -y jq python3-pip zsh htop git curl wget build-essential libice6

# --- Instalar Oh My Zsh ---
if [ -d "$HOME/.oh-my-zsh" ]; then
    echo "✅ Oh My Zsh ya está instalado."
else
    echo "셸 Instalando Oh My Zsh..."
    sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

# --- Instalar plugins de Zsh ---
echo "🔌 Instalando plugins de Zsh..."
ZSH_CUSTOM=${ZSH_CUSTOM:-~/.oh-my-zsh/custom}

# Comprobar si el directorio del plugin ya existe
if [ ! -d "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting" ]; then
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting
else
    echo "✅ Plugin zsh-syntax-highlighting ya está instalado."
fi

if [ ! -d "${ZSH_CUSTOM}/plugins/zsh-autosuggestions" ]; then
    git clone https://github.com/zsh-users/zsh-autosuggestions.git ${ZSH_CUSTOM}/plugins/zsh-autosuggestions
else
    echo "✅ Plugin zsh-autosuggestions ya está instalado."
fi


# --- Instalar NVM ---
if [ -d "$HOME/.nvm" ]; then
    echo "✅ nvm ya está instalado."
else
    echo "📦 Instalando nvm (Node Version Manager)..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
fi

# --- Instalar Git Credential Manager (GCM) ---
echo "📦 Instalando Git Credential Manager..."
# Descargar el paquete
wget https://github.com/git-ecosystem/git-credential-manager/releases/download/v2.5.1/gcm-linux_amd64.2.5.1.deb -O /tmp/gcm.deb
# Instalar el paquete (requiere sudo)
sudo dpkg -i /tmp/gcm.deb
# Configurar Git para usar GCM y el almacén de texto plano
echo "🔧 Configurando Git para usar GCM..."
git config --global credential.helper manager
git config --global credential.credentialStore plaintext

# --- Instalar Herramientas Cloud Native (Docker, kubectl, kind) ---
echo "📦 Instalando herramientas Cloud Native..."

# Instalar Docker Engine
echo "    - Instalando Docker Engine..."
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Instalar kubectl (usando la versión que sabemos es estable)
echo "    - Instalando kubectl..."
curl -LO "https://dl.k8s.io/release/v1.34.1/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl

# Instalar kind
echo "    - Instalando kind..."
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.23.0/kind-linux-amd64
sudo install -o root -g root -m 0755 kind /usr/local/bin/kind
rm kind

echo "
✅ ¡Configuración completada!"
echo "NOTA: Cierra y vuelve a abrir tu terminal para que todos los cambios surtan efecto."