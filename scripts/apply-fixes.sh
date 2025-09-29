#!/bin/bash

# 🔧 Apply GitOps Fixes Script
# Aplica todos los fixes identificados para que la instalación funcione 100% desatendida
# Este script debe ejecutarse DESPUÉS de clonar el repo pero ANTES de install-gitops.sh

set -e

echo "🔧 APLICANDO FIXES GITOPS"
echo "====================================="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

log_step() {
    echo "📋 $1"
}

log_success() {
    echo "✅ $1"
}

log_error() {
    echo "❌ ERROR: $1" >&2
}

# --- FIX 1: SEALED-SECRETS IMAGE REGISTRY ---
log_step "Aplicando fix sealed-secrets: cambiar quay.io → docker.io"

SEALED_SECRETS_FILE="$DOTFILES_DIR/manifests/infrastructure/sealed-secrets/controller.yaml"
if [[ -f "$SEALED_SECRETS_FILE" ]]; then
    # Cambiar quay.io a docker.io para evitar ImagePullBackOff
    sed -i 's|quay.io/bitnami/sealed-secrets-controller:v0.24.5|docker.io/bitnami/sealed-secrets-controller:v0.24.5|g' "$SEALED_SECRETS_FILE"
    log_success "sealed-secrets: imagen cambiada a docker.io registry"
else
    log_error "sealed-secrets controller.yaml no encontrado"
    exit 1
fi

# --- FIX 2: ARGO-ROLLOUTS VERSION & ARGS ---
log_step "Aplicando fix argo-rollouts: actualizar versión y argumentos"

ARGO_DEPLOYMENT="$DOTFILES_DIR/manifests/infrastructure/argo-rollouts/deployment.yaml"
if [[ -f "$ARGO_DEPLOYMENT" ]]; then
    # Actualizar versión v1.6.6 → v1.8.3
    sed -i 's|quay.io/argoproj/argo-rollouts:v1.6.6|quay.io/argoproj/argo-rollouts:v1.8.3|g' "$ARGO_DEPLOYMENT"
    
    # Cambiar argumento incompatible --prometheus-listen-port → --metricsport
    sed -i 's|--prometheus-listen-port=8090|--metricsport=8090|g' "$ARGO_DEPLOYMENT"
    
    log_success "argo-rollouts deployment: versión actualizada a v1.8.3 con argumentos correctos"
else
    log_error "argo-rollouts deployment.yaml no encontrado"
    exit 1
fi

# --- FIX 3: ARGO-ROLLOUTS DASHBOARD VERSION & ARGS ---
log_step "Aplicando fix argo-rollouts dashboard: versión y argumentos"

ARGO_DASHBOARD="$DOTFILES_DIR/manifests/infrastructure/argo-rollouts/dashboard.yaml"
if [[ -f "$ARGO_DASHBOARD" ]]; then
    # Actualizar versión v1.6.6 → v1.8.3
    sed -i 's|quay.io/argoproj/kubectl-argo-rollouts:v1.6.6|quay.io/argoproj/kubectl-argo-rollouts:v1.8.3|g' "$ARGO_DASHBOARD"
    
    # Eliminar flag --insecure que no existe en v1.8.3
    sed -i '/--insecure/d' "$ARGO_DASHBOARD"
    
    log_success "argo-rollouts dashboard: versión actualizada y flag --insecure eliminado"
else
    log_error "argo-rollouts dashboard.yaml no encontrado"
    exit 1
fi

# --- FIX 4: ARGO-ROLLOUTS RBAC PERMISSIONS ---
log_step "Aplicando fix argo-rollouts RBAC: agregar permisos faltantes"

ARGO_RBAC="$DOTFILES_DIR/manifests/infrastructure/argo-rollouts/rbac.yaml"
if [[ -f "$ARGO_RBAC" ]]; then
    # Agregar permisos para leases (coordination.k8s.io)
    if ! grep -q "coordination.k8s.io" "$ARGO_RBAC"; then
        # Encontrar la línea después de ingresses y agregar leases permissions
        sed -i '/- patch$/a\
- apiGroups:\
  - coordination.k8s.io\
  resources:\
  - leases\
  verbs:\
  - get\
  - list\
  - watch\
  - create\
  - update\
  - patch\
  - delete' "$ARGO_RBAC"
        
        log_success "argo-rollouts RBAC: permisos para leases agregados"
    fi
    
    # Agregar permisos completos para replicasets
    if ! grep -A10 "replicasets" "$ARGO_RBAC" | grep -q "create"; then
        # Reemplazar permisos limitados de replicasets con permisos completos
        sed -i '/- apps/,/- watch$/c\
- apiGroups:\
  - apps\
  resources:\
  - replicasets\
  verbs:\
  - get\
  - list\
  - watch\
  - create\
  - update\
  - patch\
  - delete' "$ARGO_RBAC"
        
        log_success "argo-rollouts RBAC: permisos completos para replicasets agregados"
    fi
    
    # Agregar permisos para pods si no existen
    if ! grep -q "pods" "$ARGO_RBAC"; then
        # Agregar después de services
        sed -i '/- patch$/a\
- apiGroups:\
  - ""\
  resources:\
  - pods\
  verbs:\
  - get\
  - list\
  - watch\
  - create\
  - update\
  - patch\
  - delete' "$ARGO_RBAC"
        
        log_success "argo-rollouts RBAC: permisos para pods agregados"
    fi
else
    log_error "argo-rollouts rbac.yaml no encontrado"
    exit 1
fi

# --- FIX 5: HELLO-WORLD ROLLOUT STRATEGY (OPCIONAL) ---
log_step "Verificando hello-world configuration..."

HELLO_WORLD_APP="$DOTFILES_DIR/manifests/applications/hello-world"
if [[ -d "$HELLO_WORLD_APP" ]]; then
    log_success "hello-world manifests encontrados - se procesarán después de la infraestructura"
else
    log_success "hello-world manifests no encontrados - se crearán automáticamente"
fi

# --- VERIFICAR QUE TODOS LOS FIXES SE APLICARON ---
log_step "Verificando que todos los fixes se aplicaron correctamente..."

# Verificar sealed-secrets
if grep -q "docker.io/bitnami/sealed-secrets-controller:v0.24.5" "$SEALED_SECRETS_FILE"; then
    log_success "✓ sealed-secrets: imagen docker.io verificada"
else
    log_error "sealed-secrets: fix de imagen no aplicado correctamente"
    exit 1
fi

# Verificar argo-rollouts deployment
if grep -q "quay.io/argoproj/argo-rollouts:v1.8.3" "$ARGO_DEPLOYMENT" && grep -q "\-\-metricsport=8090" "$ARGO_DEPLOYMENT"; then
    log_success "✓ argo-rollouts deployment: versión y argumentos verificados"
else
    log_error "argo-rollouts deployment: fixes no aplicados correctamente"
    exit 1
fi

# Verificar argo-rollouts dashboard
if grep -q "quay.io/argoproj/kubectl-argo-rollouts:v1.8.3" "$ARGO_DASHBOARD" && ! grep -q "\-\-insecure" "$ARGO_DASHBOARD"; then
    log_success "✓ argo-rollouts dashboard: versión y argumentos verificados"
else
    log_error "argo-rollouts dashboard: fixes no aplicados correctamente"
    exit 1
fi

# Verificar argo-rollouts RBAC
if grep -q "coordination.k8s.io" "$ARGO_RBAC" && grep -A20 "replicasets" "$ARGO_RBAC" | grep -q "create" && grep -q "pods" "$ARGO_RBAC"; then
    log_success "✓ argo-rollouts RBAC: todos los permisos verificados"
else
    log_error "argo-rollouts RBAC: permisos no aplicados correctamente"
    exit 1
fi

echo ""
echo "🎉 TODOS LOS FIXES APLICADOS EXITOSAMENTE"
echo "========================================="
echo "✅ sealed-secrets: imagen docker.io registry"
echo "✅ argo-rollouts: versión v1.8.3 + argumentos correctos"
echo "✅ argo-rollouts dashboard: versión v1.8.3 sin --insecure"
echo "✅ argo-rollouts RBAC: permisos completos (leases, replicasets, pods)"
echo ""
echo "📋 PRÓXIMOS PASOS:"
echo "1. Ejecutar: ./scripts/install.sh"
echo "2. La instalación debería llegar automáticamente a infraestructura 100% Healthy"
echo ""