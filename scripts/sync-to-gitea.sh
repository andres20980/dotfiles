#!/bin/bash
# Script para sincronizar cambios locales con Gitea (flujo GitOps)
set -euo pipefail

log_info() { echo "ℹ️  $*"; }
log_success() { echo "✅ $*"; }
log_error() { echo "❌ $*"; }

sync_subtree() {
  local prefix="$1"
  local remote="$2"
  
  log_info "Sincronizando $prefix con $remote..."
  
  # Crear directorio temporal único
  local temp_dir
  temp_dir=$(mktemp -d /tmp/gitops-sync-XXXXXX)
  
  # Clonar repo de Gitea
  if ! git clone "$remote" "$temp_dir" 2>&1 | grep -v "Cloning into"; then
    log_error "Error clonando $remote"
    rm -rf "$temp_dir"
    return 1
  fi
  
  # Copiar archivos actuales
  rsync -a --delete --exclude='.git' "$prefix/" "$temp_dir/" 2>/dev/null || cp -r "$prefix"/* "$temp_dir/" 2>/dev/null || true
  
  # Commit y push
  (
    cd "$temp_dir"
    git config user.name "GitOps Sync"
    git config user.email "gitops@localhost"
    git add -A
    if git diff --staged --quiet; then
      log_info "$prefix sin cambios"
    else
      git commit -m "sync: update from local development" >/dev/null 2>&1
      if git push >/dev/null 2>&1; then
        log_success "$prefix sincronizado ✅"
      else
        log_error "Error haciendo push a $prefix"
        rm -rf "$temp_dir"
        return 1
      fi
    fi
  )
  
  # Cleanup
  rm -rf "$temp_dir"
}

main() {
  log_info "🔄 Sincronizando cambios locales con Gitea..."
  
  # Verificar que estemos en el directorio correcto
  if [[ ! -d "argo-config" ]] || [[ ! -d "manifests/infrastructure" ]]; then
    log_error "Ejecutar desde el directorio raíz del proyecto (donde están argo-config/ y manifests/)"
    exit 1
  fi
  
  # Obtener password de Gitea
  local gitea_password
  gitea_password=$(kubectl get secret gitea-admin-secret -n gitea -o jsonpath='{.data.password}' | base64 -d 2>/dev/null || echo "")
  
  if [[ -z "$gitea_password" ]]; then
    log_error "No se pudo obtener la contraseña de Gitea. ¿Está el cluster funcionando?"
    exit 1
  fi
  
  # Sincronizar ambos repos
  sync_subtree "argo-config" "http://gitops:${gitea_password}@localhost:30083/gitops/argo-config.git"
  sync_subtree "manifests/infrastructure" "http://gitops:${gitea_password}@localhost:30083/gitops/infrastructure.git"
  
  log_success "🎉 Sincronización completada. ArgoCD detectará los cambios automáticamente."
  log_info "💡 Puedes verificar en: http://localhost:30080"
}

main "$@"