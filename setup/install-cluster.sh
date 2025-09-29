#!/bin/bash

# 🏗️ Cluster Kubernetes - Solo creación del cluster
# Crea cluster kind + ArgoCD básico

set -e

echo "🏗️ Creando cluster Kubernetes..."
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

wait_for_pods() {
    local namespace=$1
    local app=$2
    local timeout=${3:-300}
    
    log_step "Esperando a que los pods de $app estén listos..."
    kubectl wait --for=condition=ready pod -l app="$app" -n "$namespace" --timeout="${timeout}"s || \
    kubectl wait --for=condition=ready pod -l k8s-app="$app" -n "$namespace" --timeout="${timeout}"s || \
    log_info "Timeout esperando pods de $app"
}

# --- Crear cluster kind ---
log_step "Creando cluster kind..."
if ! kind get clusters | grep -q mini-cluster; then
    kind create cluster --name mini-cluster --config /home/asanchez/Code/dotfiles/config/kind-config.yaml
    log_success "Cluster kind creado y configurado"
else
    log_success "Cluster kind ya existe"
fi

# --- Instalar ArgoCD ---
log_step "Instalando ArgoCD..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

log_step "Esperando a que ArgoCD esté listo..."
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

# --- Configurar ArgoCD con credenciales admin/admin123 ---
log_step "Configurando credenciales de ArgoCD..."
kubectl delete secret argocd-initial-admin-secret -n argocd 2>/dev/null || true
ADMIN_PASSWORD_HASH=$(kubectl exec -n argocd deployment/argocd-server -- argocd account bcrypt --password admin123)
ADMIN_PASSWORD_B64=$(echo -n "$ADMIN_PASSWORD_HASH" | base64 -w 0)
ADMIN_TIME_B64=$(echo -n "$(date +%s)" | base64 -w 0)

kubectl patch secret argocd-secret -n argocd -p="{\"data\":{\"admin.password\":\"$ADMIN_PASSWORD_B64\",\"admin.passwordMtime\":\"$ADMIN_TIME_B64\"}}" --type=merge

# --- Configurar servicios como NodePort ---
log_step "Configurando servicios ArgoCD como NodePort..."
kubectl patch svc argocd-server -n argocd --type='json' -p='[{"op": "replace", "path": "/spec/type", "value": "NodePort"}, {"op": "replace", "path": "/spec/ports/0/nodePort", "value": 30080}, {"op": "replace", "path": "/spec/ports/1/nodePort", "value": 30443}]'

# --- Configurar ArgoCD para acceso HTTP sin TLS ---
log_step "Configurando ArgoCD para acceso HTTP sin TLS..."
kubectl patch configmap argocd-cmd-params-cm -n argocd --type merge -p='{"data":{"server.insecure":"true"}}'
kubectl rollout restart deployment argocd-server -n argocd
kubectl rollout status deployment argocd-server -n argocd --timeout=300s

# --- Instalar NGINX Ingress ---
log_step "Instalando NGINX Ingress Controller..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.0/deploy/static/provider/cloud/deploy.yaml
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=300s
kubectl patch svc ingress-nginx-controller -n ingress-nginx --type='json' -p='[{"op": "replace", "path": "/spec/type", "value": "NodePort"}, {"op": "replace", "path": "/spec/ports/0/nodePort", "value": 30090}]'

log_success "Cluster Kubernetes y ArgoCD instalados correctamente"
echo ""
echo "🌐 ArgoCD disponible en:"
echo "   HTTP:  http://localhost:30080 (admin/admin123)"
echo "   HTTPS: https://localhost:30443 (admin/admin123)"
echo ""
echo "💡 Siguiente paso: ./gitops/bootstrap/install-gitops.sh"