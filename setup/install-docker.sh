#!/bin/bash

# 🐳 Docker & Kubernetes - Solo containerización
# Instala Docker, kubectl, kind

set -e

echo "🐳 Instalando Docker y herramientas Kubernetes..."
echo "================================================="

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

# --- Instalar Docker ---
log_step "Instalando Docker..."
if ! command -v docker &> /dev/null; then
    # Agregar repositorio oficial de Docker
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Agregar usuario al grupo docker
    sudo usermod -aG docker $USER
    
    log_success "Docker instalado correctamente"
else
    log_success "Docker ya está instalado"
fi

# --- Instalar kubectl ---
log_step "Instalando kubectl..."
if ! command -v kubectl &> /dev/null; then
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm kubectl
    log_success "kubectl instalado correctamente"
else
    log_success "kubectl ya está instalado"
fi

# --- Instalar kind ---
log_step "Instalando kind..."
if ! command -v kind &> /dev/null; then
    curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.23.0/kind-linux-amd64
    sudo install -o root -g root -m 0755 kind /usr/local/bin/kind
    rm kind
    log_success "kind instalado correctamente"
else
    log_success "kind ya está instalado"
fi

# --- Verificar instalaciones ---
log_step "Verificando instalaciones..."
docker --version
kubectl version --client
kind version

log_success "Docker y herramientas Kubernetes instalados correctamente"
echo ""
echo "💡 IMPORTANTE: Reinicia tu terminal o ejecuta 'newgrp docker' para usar Docker"
echo "💡 Siguiente paso: ./setup/install-cluster.sh"