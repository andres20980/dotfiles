#!/bin/bash

# 🚀 GitOps Installation Script - Single Point of Entry
# Instala un entorno GitOps completo de forma totalmente desatendida
# 
# Uso: ./install.sh
# 
# Este script consolida toda la lógica de instalación en un solo lugar
# siguiendo mejores prácticas de scripting modular.

set -euo pipefail

# =============================================================================
# CONFIGURACIÓN Y CONSTANTES
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export DEBIAN_FRONTEND=noninteractive

# Cargar configuración externa PRIMERO (antes de marcar variables como readonly)
if [[ -f "${SCRIPT_DIR}/config.env" ]]; then
  # shellcheck source=config.env
  source "${SCRIPT_DIR}/config.env"
fi

# Declarar constantes después de cargar config.env (con valores por defecto)
readonly SCRIPT_DIR
readonly DOTFILES_DIR="${DOTFILES_DIR:-$SCRIPT_DIR}"
readonly CLUSTER_NAME="${CLUSTER_NAME:-gitops-local}"
readonly GITEA_NAMESPACE="${GITEA_NAMESPACE:-gitea}"
readonly BASE_DIR="${BASE_DIR:-$SCRIPT_DIR}"

# Controla si se gestionan aplicaciones personalizadas (demo-api, etc.)
ENABLE_CUSTOM_APPS="${ENABLE_CUSTOM_APPS:-false}"
readonly ENABLE_CUSTOM_APPS

# Variables de configuración adicionales
readonly INSTALL_TIMEOUT="${INSTALL_TIMEOUT:-1800}" # 30 minutos por defecto
readonly VERBOSE_LOGGING="${VERBOSE_LOGGING:-false}"
readonly SKIP_SYSTEM_CHECK="${SKIP_SYSTEM_CHECK:-false}"

# Activar modo debug si está configurado
if [[ "${DEBUG_MODE:-false}" == "true" ]]; then
  set -x  # Activar xtrace para debugging completo
  export VERBOSE_LOGGING=true
  echo "🐛 Modo DEBUG activado"
fi

# =============================================================================
# FUNCIONES DE UTILIDAD
# =============================================================================

# Capturar estado del cluster para debugging
capture_cluster_state() {
  local output_dir="${DEBUG_LOG_DIR:-/tmp/gitops-debug}-$(date +%s)"
  mkdir -p "$output_dir"
  
  log_info "📸 Capturando estado del cluster en $output_dir..."
  
  # Información general del cluster
  {
    echo "=== CLUSTER INFO ==="
    kubectl version --short 2>&1 || echo "kubectl version failed"
    echo ""
    echo "=== NODES ==="
    kubectl get nodes -o wide 2>&1 || echo "get nodes failed"
    echo ""
    echo "=== NAMESPACES ==="
    kubectl get namespaces 2>&1 || echo "get namespaces failed"
  } > "$output_dir/cluster-info.txt" 2>&1
  
  # Pods de todos los namespaces
  kubectl get pods -A -o wide > "$output_dir/pods.txt" 2>&1 || true
  
  # Eventos recientes ordenados
  kubectl get events -A --sort-by='.lastTimestamp' > "$output_dir/events.txt" 2>&1 || true
  
  # Estado de aplicaciones ArgoCD
  kubectl get applications -n argocd -o yaml > "$output_dir/argocd-applications.yaml" 2>&1 || true
  kubectl get applications -n argocd -o wide > "$output_dir/argocd-apps-status.txt" 2>&1 || true
  
  # Logs de componentes críticos
  if kubectl get namespace argocd >/dev/null 2>&1; then
    kubectl logs -n argocd deployment/argocd-server --tail=100 > "$output_dir/argocd-server.log" 2>&1 || true
    kubectl logs -n argocd deployment/argocd-application-controller --tail=100 > "$output_dir/argocd-controller.log" 2>&1 || true
    kubectl logs -n argocd deployment/argocd-repo-server --tail=100 > "$output_dir/argocd-repo-server.log" 2>&1 || true
  fi
  
  if kubectl get namespace gitea >/dev/null 2>&1; then
    kubectl logs -n gitea deployment/gitea --tail=100 > "$output_dir/gitea.log" 2>&1 || true
  fi
  
  # Services y endpoints
  kubectl get svc -A -o wide > "$output_dir/services.txt" 2>&1 || true
  kubectl get endpoints -A > "$output_dir/endpoints.txt" 2>&1 || true
  
  # ConfigMaps y Secrets (solo nombres, no contenido sensible)
  kubectl get configmaps -A > "$output_dir/configmaps-list.txt" 2>&1 || true
  kubectl get secrets -A > "$output_dir/secrets-list.txt" 2>&1 || true
  
  # Estado de Docker y kind
  {
    echo "=== DOCKER INFO ==="
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>&1 || echo "docker ps failed"
    echo ""
    echo "=== KIND CLUSTERS ==="
    kind get clusters 2>&1 || echo "kind get clusters failed"
  } > "$output_dir/docker-kind.txt" 2>&1
  
  log_success "Estado capturado en: $output_dir"
  echo "$output_dir"
}

# Limpieza en caso de error crítico
cleanup_on_error() {
    local exit_code="$?"
    if [[ $exit_code -ne 0 ]]; then
        log_error "Instalación interrumpida con código de salida: $exit_code"
        
        # Limpiar archivos temporales
        rm -rf /tmp/gitops-sync-* /tmp/kargo-sealed-secret.yaml /tmp/kubeseal 2>/dev/null || true
        
        # Capturar estado del cluster para debugging
        if [[ "${CAPTURE_STATE_ON_ERROR:-true}" == "true" ]]; then
            local debug_dir
            debug_dir=$(capture_cluster_state)
            log_error "📋 Debug info guardado en: $debug_dir"
            log_info "💡 Revisa los logs para diagnosticar el problema"
        fi
        
        log_warning "⚠️  El cluster y repositorios se mantienen para debugging"
        log_info "💡 Para limpiar manualmente: kind delete cluster --name $CLUSTER_NAME && rm -rf ~/gitops-repos"
    fi
}

# Configurar trap para capturar errores
trap 'cleanup_on_error' EXIT

log_step() {
    local message="$1"
    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "▶️  $message"
    echo "════════════════════════════════════════════════════════════"
}

log_info() {
    local message="$1"
    echo "   ℹ️  $message"
}

log_success() {
    local message="$1"
    echo "   ✅ $message"
}

log_warning() {
    local message="$1"
    echo "   ⚠️  $message"
}

log_error() {
    local message="$1"
    echo "   ❌ $message" >&2
}

log_verbose() {
    local message="$1"
    if [[ "$VERBOSE_LOGGING" == "true" ]]; then
        echo "   🔍 [DEBUG] $message" >&2
    fi
}

# Ejecutar comando kubectl con manejo de errores mejorado
kubectl_safe() {
    local description="$1"
    shift
    if kubectl "$@" >/dev/null 2>&1; then
        return 0
    else
        log_warning "$description falló: kubectl $*"
        return 1
    fi
}

open_url() {
  local url="$1"
  if command -v xdg-open >/dev/null 2>&1; then
    if xdg-open "$url" >/dev/null 2>&1; then
      return 0
    fi
  fi
  if command -v cmd.exe >/dev/null 2>&1; then
    if cmd.exe /c start "$url" >/dev/null 2>&1; then
      return 0
    fi
  fi
  return 1
}

ensure_shell_alias() {
  local shell_file="$1"
  local alias_name="$2"
  local alias_command="$3"

  if [[ ! -f "$shell_file" ]]; then
    return
  fi

  local alias_line
  alias_line="alias ${alias_name}='${alias_command}'"

  if grep -q "^alias ${alias_name}=" "$shell_file"; then
    sed -i "s|^alias ${alias_name}=.*|${alias_line}|" "$shell_file"
  else
    printf '%s\n' "$alias_line" >> "$shell_file"
  fi
}

open_service() {
  local service="$1"
  local url=""
  local label=""
  local note=""

  case "$service" in
    dashboard)
      url="http://localhost:30085"
      label="Kubernetes Dashboard"
      note="En la pantalla de login, pulsa 'SKIP'"
      ;;
    argocd)
      url="http://localhost:30080"
      label="ArgoCD UI"
      ;;
    gitea)
      url="http://localhost:30083"
      label="Gitea"
      ;;
    grafana)
      url="http://localhost:30093"
      label="Grafana"
      ;;
    prometheus)
      url="http://localhost:30092"
      label="Prometheus"
      ;;
    rollouts|argo-rollouts)
      url="http://localhost:30084"
      label="Argo Rollouts"
      ;;
    kargo)
      url="http://localhost:30094"
      label="Kargo"
      note="Default credentials: admin/admin123"
      ;;
    *)
      log_error "Servicio desconocido: $service"
      return 1
      ;;
  esac

  log_info "Abriendo ${label} en ${url}"
  if open_url "$url"; then
    if [[ -n "$note" ]]; then
      log_info "$note"
    fi
  else
    log_warning "No se pudo abrir automáticamente ${label}. URL disponible: ${url}"
  fi
}

bootstrap_local_repo() {
  local source_dir="$1"
  local target_dir="$2"
  local commit_message="$3"
  local skip_disabled="${4:-true}"

  rm -rf "$target_dir"
  mkdir -p "$target_dir"

  shopt -s dotglob nullglob
  for item in "$source_dir"/*; do
    local name
    name=$(basename "$item")
    if [[ "$skip_disabled" == true && "$name" == *.disabled ]]; then
      log_info "   Omitiendo ${name} (marcado como .disabled)"
      continue
    fi
    cp -r "$item" "$target_dir/"
  done
  shopt -u dotglob
  shopt -u nullglob

  if [[ ! -e "$target_dir/.gitkeep" ]]; then
    touch "$target_dir/.gitkeep"
  fi

  (
    cd "$target_dir" || exit 1
    git init -b main >/dev/null 2>&1
    git checkout -B main >/dev/null 2>&1
    git config user.name "GitOps Setup"
    git config user.email "gitops@localhost"
    git add .
    git commit -m "$commit_message" >/dev/null 2>&1 || true
  )
}

push_repo_to_gitea() {
  local repo_dir="$1"
  local repo_name="$2"

  (
    cd "$repo_dir" || exit 1
    git remote remove origin >/dev/null 2>&1 || true
    git remote add origin "http://gitops:${GITEA_ADMIN_PASSWORD}@localhost:30083/gitops/${repo_name}.git"
    git push --set-upstream origin main --force >/dev/null 2>&1
  )
}

install_python_bcrypt() {
  if ! command -v python3 >/dev/null 2>&1; then
    log_error "python3 no está instalado"
    return 1
  fi
  
  if python3 -c "import bcrypt" >/dev/null 2>&1; then
    log_info "bcrypt ya está instalado"
    return 0
  fi
  
  log_info "Instalando python bcrypt..."
  
  # Intentar con pip3
  if command -v pip3 >/dev/null 2>&1; then
    if pip3 install --user bcrypt >/dev/null 2>&1; then
      log_success "bcrypt instalado correctamente"
      return 0
    fi
  fi
  
  # Intentar con python3 -m pip
  if python3 -m pip install --user bcrypt >/dev/null 2>&1; then
    log_success "bcrypt instalado correctamente"
    return 0
  fi
  
  log_error "No se pudo instalar bcrypt"
  return 1
}

install_kubeseal() {
  if command -v kubeseal >/dev/null 2>&1; then
    log_info "kubeseal ya está instalado"
    return 0
  fi
  
  log_info "Instalando kubeseal CLI..."
  local kubeseal_version="${KUBESEAL_VERSION:-v0.32.2}"
  local kubeseal_url="https://github.com/bitnami-labs/sealed-secrets/releases/download/${kubeseal_version}/kubeseal-0.32.2-linux-amd64.tar.gz"
  
  # Retry lógic para descarga con verificación
  local max_retries=3
  local retry=0
  local temp_file="/tmp/kubeseal-$$.tar.gz"
  
  while [[ $retry -lt $max_retries ]]; do
    if curl -fsSL --max-time 30 "$kubeseal_url" -o "$temp_file"; then
      # Verificar que el archivo no esté vacío
      if [[ -s "$temp_file" ]] && tar -tzf "$temp_file" >/dev/null 2>&1; then
        tar -xzf "$temp_file" -C /tmp/
        sudo mv /tmp/kubeseal /usr/local/bin/kubeseal
        chmod +x /usr/local/bin/kubeseal
        rm -f "$temp_file"
        log_success "kubeseal instalado correctamente"
        return 0
      else
        log_warning "Archivo descargado inválido o corrupto"
      fi
    fi
    retry=$((retry + 1))
    log_warning "Intento $retry/$max_retries falló, reintentando..."
    sleep 2
  done
  
  rm -f "$temp_file"
  
  log_error "No se pudo instalar kubeseal después de $max_retries intentos"
  return 1
}

create_kargo_secret_workaround() {
  log_info "Generando SealedSecret para Kargo con clave del cluster actual..."
  
  # Instalar herramientas necesarias
  install_python_bcrypt || {
    log_error "No se pudo instalar python bcrypt"
    return 1
  }
  install_kubeseal || {
    log_error "No se pudo instalar kubeseal"
    return 1
  }
  
  # Verificar que el namespace kargo existe (debería haber sido creado por create_gitops_namespaces)
  if ! kubectl get namespace kargo >/dev/null 2>&1; then
    log_error "Namespace 'kargo' no existe. Debería haber sido creado por create_gitops_namespaces()"
    return 1
  fi
  
  # Verificar que sealed-secrets controller responde (en kube-system)
  if ! kubectl get pods -n kube-system -l name=sealed-secrets-controller --field-selector=status.phase=Running 2>/dev/null | grep -q "sealed-secrets-controller"; then
    log_error "Sealed Secrets Controller no está Running en kube-system"
    return 1
  fi
  
  # Generar password seguro
  local kargo_password
  kargo_password=$(generate_secure_password 16)
  
  # Generar hash bcrypt para el password
  local password_hash
  if command -v python3 >/dev/null 2>&1 && python3 -c "import bcrypt" >/dev/null 2>&1; then
    password_hash=$(python3 -c "import bcrypt; print(bcrypt.hashpw('${kargo_password}'.encode('utf-8'), bcrypt.gensalt(rounds=10)).decode('utf-8'))")
    log_info "Password hash generado dinámicamente para: ${kargo_password}"
  else
    log_error "bcrypt no disponible, no se puede generar hash"
    return 1
  fi
  
  # Generar token signing key seguro
  local token_key
  token_key=$(generate_secure_password 32)
  
  # Crear Secret temporal con TODOS los campos necesarios
  local temp_secret_file="/tmp/kargo-temp-secret-$$.yaml"
  local sealed_secret_file="/tmp/kargo-sealed-secret-$$.yaml"
  
  kubectl create secret generic kargo-api -n kargo \
    --from-literal=ADMIN_ACCOUNT_ENABLED='true' \
    --from-literal=ADMIN_ACCOUNT_USERNAME='admin' \
    --from-literal=ADMIN_ACCOUNT_PASSWORD="${kargo_password}" \
    --from-literal=ADMIN_ACCOUNT_PASSWORD_HASH="${password_hash}" \
    --from-literal=ADMIN_ACCOUNT_TOKEN_SIGNING_KEY="${token_key}" \
    --from-literal=ADMIN_ACCOUNT_TOKEN_ISSUER='kargo-api' \
    --from-literal=ADMIN_ACCOUNT_TOKEN_AUDIENCE='kargo-api' \
    --from-literal=ADMIN_ACCOUNT_TOKEN_TTL='24h' \
    --dry-run=client -o yaml > "${temp_secret_file}"
  
  # Convertir a SealedSecret
  if ! kubeseal --format=yaml < "${temp_secret_file}" > "${sealed_secret_file}" 2>/dev/null; then
    log_error "No se pudo generar SealedSecret con kubeseal"
    rm -f "${temp_secret_file}" "${sealed_secret_file}"
    return 1
  fi
  
  # Aplicar al cluster
  if ! kubectl apply -f "${sealed_secret_file}" >/dev/null 2>&1; then
    log_error "No se pudo aplicar SealedSecret"
    rm -f "${temp_secret_file}" "${sealed_secret_file}"
    return 1
  fi
  
  # Guardar en manifests para GitOps
  mkdir -p "$SCRIPT_DIR/manifests/gitops-tools/kargo"
  cp "${sealed_secret_file}" "$SCRIPT_DIR/manifests/gitops-tools/kargo/sealed-secret.yaml"
  
  # Crear archivo con credenciales para el usuario
  mkdir -p "$HOME/.gitops-credentials"
  cat > "$HOME/.gitops-credentials/kargo-admin.txt" << EOF
Kargo Admin Credentials
=======================
URL: http://localhost:30094
User: admin
Pass: ${kargo_password}

Generated: $(date)
EOF
  chmod 600 "$HOME/.gitops-credentials/kargo-admin.txt"
  
  rm -f "${temp_secret_file}" "${sealed_secret_file}"
  
  log_success "SealedSecret de Kargo generado y aplicado"
  log_info "   Credenciales guardadas en: ~/.gitops-credentials/kargo-admin.txt"
  log_info "   Usuario: admin | Password: ${kargo_password}"
  
  return 0
}

create_grafana_secret() {
  log_info "Generando SealedSecret para Grafana..."
  
  # Verificar que el namespace grafana existe (debería haber sido creado por create_gitops_namespaces)
  if ! kubectl get namespace grafana >/dev/null 2>&1; then
    log_warning "Namespace 'grafana' no existe. Grafana usará password hardcoded"
    return 0  # No es crítico, Grafana tiene fallback
  fi
  
  # Verificar que sealed-secrets controller responde (en kube-system)
  if ! kubectl get pods -n kube-system -l name=sealed-secrets-controller --field-selector=status.phase=Running 2>/dev/null | grep -q "sealed-secrets-controller"; then
    log_warning "Sealed Secrets Controller no disponible"
    log_warning "Grafana usará password hardcoded del deployment"
    return 0  # No es crítico
  fi
  
  # Generar password seguro para admin
  local grafana_password
  grafana_password=$(generate_secure_password 16)
  
  # Crear Secret temporal
  local temp_secret_file="/tmp/grafana-temp-secret-$$.yaml"
  local sealed_secret_file="/tmp/grafana-sealed-secret-$$.yaml"
  
  kubectl create secret generic grafana-admin -n grafana \
    --from-literal=GF_SECURITY_ADMIN_PASSWORD="${grafana_password}" \
    --dry-run=client -o yaml > "${temp_secret_file}"
  
  # Convertir a SealedSecret
  if ! kubeseal --format=yaml < "${temp_secret_file}" > "${sealed_secret_file}" 2>/dev/null; then
    log_error "No se pudo generar SealedSecret con kubeseal"
    rm -f "${temp_secret_file}" "${sealed_secret_file}"
    return 1
  fi
  
  # Aplicar al cluster
  if ! kubectl apply -f "${sealed_secret_file}" >/dev/null 2>&1; then
    log_error "No se pudo aplicar SealedSecret"
    rm -f "${temp_secret_file}" "${sealed_secret_file}"
    return 1
  fi
  
  # Guardar en manifests para GitOps
  mkdir -p "$SCRIPT_DIR/manifests/gitops-tools/grafana"
  cp "${sealed_secret_file}" "$SCRIPT_DIR/manifests/gitops-tools/grafana/sealed-secret.yaml"
  
  # Crear archivo con credenciales para el usuario
  mkdir -p "$HOME/.gitops-credentials"
  cat > "$HOME/.gitops-credentials/grafana-admin.txt" << EOF
Grafana Admin Credentials
=========================
URL: http://localhost:30003
User: admin
Pass: ${grafana_password}

Note: Anonymous access is enabled (no login required for viewing)

Generated: $(date)
EOF
  chmod 600 "$HOME/.gitops-credentials/grafana-admin.txt"
  
  rm -f "${temp_secret_file}" "${sealed_secret_file}"
  
  log_success "SealedSecret de Grafana generado y aplicado"
  log_info "   Credenciales guardadas en: ~/.gitops-credentials/grafana-admin.txt"
  log_info "   Usuario: admin | Password: ${grafana_password}"
  
  return 0
}

sync_sealedsecret_to_gitea() {
  log_info "Sincronizando SealedSecrets actualizados a Gitea..."
  
  # Verificar que al menos un archivo exista
  local kargo_secret="$SCRIPT_DIR/manifests/gitops-tools/kargo/sealed-secret.yaml"
  local grafana_secret="$SCRIPT_DIR/manifests/gitops-tools/grafana/sealed-secret.yaml"
  
  if [[ ! -f "$kargo_secret" ]] && [[ ! -f "$grafana_secret" ]]; then
    log_warning "No hay SealedSecrets para sincronizar"
    return 0
  fi
  
  # Push directo del directorio gitops-tools actualizado
  (
    cd "$SCRIPT_DIR/manifests/gitops-tools" || exit 1
    [[ -f "$kargo_secret" ]] && git add kargo/sealed-secret.yaml
    [[ -f "$grafana_secret" ]] && git add grafana/sealed-secret.yaml
    git commit -m "feat: update SealedSecrets with cluster key" >/dev/null 2>&1 || true
    git remote remove gitea 2>/dev/null || true
    git remote add gitea "http://gitops:$GITEA_ADMIN_PASSWORD@localhost:30083/gitops/infrastructure.git"
    git push gitea HEAD:main --force >/dev/null 2>&1
  )
  
  log_success "SealedSecrets sincronizados a Gitea"
}

check_mapping_sanity() {
  log_step "Comprobando mapeos de puertos (sanity)"

  local node_container
  node_container=$(docker ps --format '{{.Names}}' | grep "${CLUSTER_NAME}-control-plane" || true)
  if [[ -z "$node_container" ]]; then
    log_warning "No se encontró el contenedor del control-plane. No puedo verificar mapeos."
    return 1
  fi

  local issues=0
  local mapping
  mapping=$(docker port "$node_container" 2>/dev/null || true)

  if kubectl get svc argocd-server -n argocd >/dev/null 2>&1; then
    local nodePort
    nodePort=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}{.spec.ports[?(@.port==443)].nodePort}' 2>/dev/null | awk '{print $1}')
    if [[ -z "$nodePort" ]]; then
      nodePort=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.spec.ports[?(@.nodePort)].nodePort}' 2>/dev/null | awk '{print $1}')
    fi
    log_info "argocd-server nodePort: ${nodePort:-none}"

    if [[ -z "$nodePort" ]]; then
      log_warning "argocd-server aún no es NodePort"
      issues=$((issues+1))
    elif ! echo "$mapping" | grep -q ":${nodePort}"; then
      log_warning "NodePort ${nodePort} de argocd-server no aparece en 'docker port' del nodo $node_container"
      issues=$((issues+1))
    else
  if curl -fsS -o /dev/null -w "%{http_code}" --max-time 3 "http://127.0.0.1:${nodePort}" | grep -q "^2\|^3"; then
        log_success "ArgoCD responde en http://localhost:${nodePort}"
      else
        log_warning "ArgoCD no responde todavía en http://localhost:${nodePort}"
        issues=$((issues+1))
      fi
    fi
  else
    log_warning "Service argocd-server no existe aún; omitiendo comprobación específica"
    issues=$((issues+1))
  fi

  for item in "${GITEA_NAMESPACE}:gitea" "monitoring:grafana" "monitoring:prometheus"; do
    IFS=':' read -r ns svc <<< "$item"
    if kubectl get svc -n "$ns" "$svc" >/dev/null 2>&1; then
      local nodePort
      nodePort=$(kubectl get svc -n "$ns" "$svc" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
      if [[ -n "$nodePort" ]]; then
        if ! echo "$mapping" | grep -q ":${nodePort}"; then
          log_warning "NodePort ${nodePort} para $svc (ns: $ns) no visible en docker port del nodo"
          issues=$((issues+1))
        else
          log_info "NodePort ${nodePort} para $svc visible en host"
        fi
      fi
    fi
  done

  if [[ $issues -gt 0 ]]; then
    log_warning "Se detectaron $issues posibles problemas en los mapeos de puertos"
    return 1
  fi

  log_success "Mapeos de puertos verificados correctamente"
  return 0
}

configure_argocd_bootstrap() {
  log_info "Configurando ArgoCD para bootstrapping (NodePort 30080)..."
  
  # Solo ArgoCD - necesario para el bootstrapping inicial del cluster
  local i=0
  while [[ $i -lt 5 ]]; do
    kubectl patch svc argocd-server -n argocd --type merge -p '{
      "spec": {
        "type": "NodePort",
        "ports": [{
          "name": "http",
          "port": 80,
          "protocol": "TCP",
          "targetPort": 8080,
          "nodePort": 30080
        }]
      }
    }' >/dev/null 2>&1 || true

    local type
    type=$(kubectl -n argocd get svc argocd-server -o jsonpath='{.spec.type}' 2>/dev/null || echo "")
    local np
    np=$(kubectl -n argocd get svc argocd-server -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}' 2>/dev/null || echo "")
    if [[ "$type" == "NodePort" && "$np" == "30080" ]]; then
      break
    fi
    sleep 2
    i=$((i+1))
  done

  # Verificar que ArgoCD esté accesible (con reintentos silenciosos)
  log_info "Verificando accesibilidad de ArgoCD..."
  wait_for_condition "curl -fsS -o /dev/null -w '%{http_code}' --max-time 3 http://127.0.0.1:30080 2>/dev/null | grep -q '^2\|^3'" 120 5 || true
  
  log_success "ArgoCD disponible en http://localhost:30080 (sin auth)"
  log_info "📝 Otros servicios configurarán sus NodePorts via manifests GitOps"
}

wait_for_condition() {
    local condition_command="$1"
    local timeout="${2:-300}"
    local initial_interval="${3:-2}"
    local max_interval="${4:-10}"
    local elapsed=0
    local interval="$initial_interval"
    local attempt=1

    while [[ $elapsed -lt $timeout ]]; do
        if eval "$condition_command"; then
            return 0
        fi
        
        # Exponential backoff con límite
        if [[ $attempt -gt 3 && $interval -lt $max_interval ]]; then
            interval=$((interval * 2))
            if [[ $interval -gt $max_interval ]]; then
                interval=$max_interval
            fi
        fi
        
        sleep "$interval"
        elapsed=$((elapsed + interval))
        attempt=$((attempt + 1))
    done

    log_warning "Condición no cumplida después de ${timeout}s: $condition_command"
    return 1
}

wait_for_gitea_readiness() {
  log_info "Esperando a que Gitea esté listo..."
  if ! kubectl -n "$GITEA_NAMESPACE" rollout status deployment/gitea --timeout=300s >/dev/null 2>&1; then
    log_error "El deployment de Gitea no alcanzó el estado Ready en el tiempo esperado"
    return 1
  fi

  log_info "Esperando a que Gitea API esté completamente funcional..."
  if ! wait_for_condition "curl -fsS --max-time 5 http://localhost:30083/api/v1/version >/dev/null 2>&1" 240 5 20; then
    log_error "Gitea API no respondió a tiempo tras el despliegue"
    return 1
  fi

  log_success "Gitea responde correctamente en http://localhost:30083"
}

generate_gitea_actions_token() {
  local token

  # Usar el CLI de Gitea directamente para generar el token (más confiable que REST API en 1.22)
  token=$(kubectl -n "$GITEA_NAMESPACE" exec deployment/gitea -- su git -c "gitea --work-path /data/gitea actions generate-runner-token" 2>/dev/null | grep -oE '[A-Za-z0-9]{40}' | head -1)

  if [[ -z "$token" || "$token" == "null" ]]; then
    log_warning "No se pudo generar token de registro para Actions via CLI"
    return 1
  fi

  echo "$token"
  return 0
}

cleanup_existing_gitea_runner() {
  local runner_name="$1"
  local runners_json

  runners_json=$(curl -fsS -u "gitops:${GITEA_ADMIN_PASSWORD}" "http://localhost:30083/api/v1/admin/actions/runners" 2>/dev/null || true)

  if [[ -z "$runners_json" ]]; then
    return 0
  fi

  if ! command -v python3 >/dev/null 2>&1; then
    log_warning "python3 no disponible; no se puede limpiar runners antiguos"
    return 0
  fi

  mapfile -t runner_ids < <(printf '%s' "$runners_json" | TARGET_RUNNER_NAME="$runner_name" python3 - <<'PY'
import json, os, sys

name = os.environ.get("TARGET_RUNNER_NAME")
try:
  data = json.load(sys.stdin)
except Exception:
  sys.exit(0)

for item in data:
  if item.get("name") == name and item.get("id") is not None:
    print(item["id"])
PY
  )

  if [[ ${#runner_ids[@]} -eq 0 ]]; then
    return 0
  fi

  for runner_id in "${runner_ids[@]}"; do
    curl -fsS -X DELETE -u "gitops:${GITEA_ADMIN_PASSWORD}" \
      "http://localhost:30083/api/v1/admin/actions/runners/${runner_id}" >/dev/null 2>&1 || true
    log_info "Runner existente eliminado (ID ${runner_id})"
  done
}

# Verificar y actualizar versiones de GitOps tools desde GitHub
check_and_update_versions() {
  log_info "🔍 Verificando versiones de componentes..."
  echo ""
  
  # Verificar dependencias
  if ! command -v jq >/dev/null 2>&1; then
    log_warning "jq no está instalado, usando versiones de config.env"
    return 0
  fi

  local config_file="$SCRIPT_DIR/config.env"
  local temp_file="${config_file}.tmp"
  cp "$config_file" "$temp_file"

  # Función helper para obtener última versión de GitHub (silenciosa)
  get_latest_github_version() {
    local repo="$1"
    local var_name="$2"
    
    local version
    version=$(curl -fsSL "https://api.github.com/repos/$repo/releases" 2>/dev/null | \
              jq -r '.[0].tag_name // empty' 2>/dev/null)
    
    if [[ -n "$version" ]]; then
      sed -i "s|^${var_name}=.*|${var_name}=${version}|" "$temp_file"
      echo "$version"
    else
      # Devolver versión actual si falla
      grep "^${var_name}=" "$config_file" | cut -d'=' -f2
    fi
  }

  # Obtener todas las versiones (silenciosamente)
  local argocd_ver=$(get_latest_github_version "argoproj/argo-cd" "ARGOCD_VERSION")
  local rollouts_ver=$(get_latest_github_version "argoproj/argo-rollouts" "ARGO_ROLLOUTS_VERSION")
  local workflows_ver=$(get_latest_github_version "argoproj/argo-workflows" "ARGO_WORKFLOWS_VERSION")
  local events_ver=$(get_latest_github_version "argoproj/argo-events" "ARGO_EVENTS_VERSION")
  local imgupd_ver=$(get_latest_github_version "argoproj-labs/argocd-image-updater" "ARGO_IMAGE_UPDATER_VERSION")
  local kubeseal_ver=$(get_latest_github_version "bitnami-labs/sealed-secrets" "KUBESEAL_VERSION")
  local kargo_ver=$(get_latest_github_version "akuity/kargo" "KARGO_VERSION")
  local prom_ver=$(get_latest_github_version "prometheus/prometheus" "PROMETHEUS_VERSION")
  local grafana_ver=$(get_latest_github_version "grafana/grafana" "GRAFANA_VERSION")
  local dash_ver=$(get_latest_github_version "kubernetes/dashboard" "K8S_DASHBOARD_VERSION")
  local gitea_ver=$(get_latest_github_version "go-gitea/gitea" "GITEA_VERSION")
  local kind_ver=$(get_latest_github_version "kubernetes-sigs/kind" "KIND_VERSION")

  # Mostrar versiones agrupadas
  log_success "Bootstrap (no gestionadas por ArgoCD):"
  echo "      • Kind $kind_ver"
  echo "      • Gitea $gitea_ver"
  echo "      • Sealed Secrets $kubeseal_ver"
  echo ""
  
  log_success "GitOps Core:"
  echo "      • ArgoCD $argocd_ver"
  echo "      • Argo Rollouts $rollouts_ver"
  echo "      • Argo Workflows $workflows_ver"
  echo "      • Argo Events $events_ver"
  echo "      • Argo Image Updater $imgupd_ver"
  echo "      • Kargo $kargo_ver"
  echo ""
  
  log_success "Observabilidad:"
  echo "      • Prometheus $prom_ver"
  echo "      • Grafana $grafana_ver"
  echo "      • Dashboard $dash_ver"
  echo ""

  # Aplicar cambios si hubo actualizaciones
  if ! diff -q "$config_file" "$temp_file" >/dev/null 2>&1; then
    mv "$temp_file" "$config_file"
    log_success "config.env actualizado con las últimas versiones"
    # Recargar configuración
    source "${SCRIPT_DIR}/config.env"
  else
    rm -f "$temp_file"
  fi
}

# Generar password seguro con múltiples fuentes de entropía
generate_secure_password() {
  local length="${1:-16}"
  
  # Prioridad: 1. /dev/urandom, 2. openssl, 3. fallback
  if [[ -c /dev/urandom ]]; then
    # Evitar SIGPIPE con || true
    tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c "$length" || true
  elif command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 "$((length * 2))" | tr -d "=+/\n" | cut -c1-"$length"
  else
    # Fallback: usar timestamp + random + hostname
    local entropy
    entropy="$(date +%s%N)$(shuf -i 10000-99999 -n 1 2>/dev/null || echo $RANDOM)$(hostname)"
    echo "$entropy" | sha256sum | cut -c1-"$length"
  fi
}

# Crear snapshot del estado del cluster
create_snapshot() {
  local snapshot_name="${1:-auto-$(date +%Y%m%d-%H%M%S)}"
  local snapshot_dir="${SNAPSHOT_DIR:-$HOME/.gitops-snapshots}/$snapshot_name"
  
  log_info "📸 Creando snapshot del cluster: $snapshot_name"
  mkdir -p "$snapshot_dir"
  
  # Exportar estado completo del cluster
  log_info "   Exportando recursos de Kubernetes..."
  kubectl get all -A -o yaml > "$snapshot_dir/all-resources.yaml" 2>/dev/null || true
  kubectl get applications -n argocd -o yaml > "$snapshot_dir/argocd-applications.yaml" 2>/dev/null || true
  kubectl get appprojects -n argocd -o yaml > "$snapshot_dir/argocd-projects.yaml" 2>/dev/null || true
  kubectl get configmaps -A -o yaml > "$snapshot_dir/configmaps.yaml" 2>/dev/null || true
  
  # Información del cluster
  {
    echo "Snapshot: $snapshot_name"
    echo "Fecha: $(date -Iseconds)"
    echo "Cluster: $CLUSTER_NAME"
    echo "Kubernetes Version: $(kubectl version --short 2>/dev/null | grep Server || echo 'N/A')"
    echo ""
    echo "=== Applications Status ==="
    kubectl get applications -n argocd -o wide 2>/dev/null || echo "No applications found"
  } > "$snapshot_dir/snapshot-info.txt"
  
  # Backup de repos Gitea via git bundle
  local gitops_base_dir="${GITOPS_BASE_DIR:-$HOME/gitops-repos}"
  if [[ -d "$gitops_base_dir" ]]; then
    log_info "   Respaldando repositorios GitOps..."
    for repo_path in "$gitops_base_dir"/gitops-*; do
      if [[ -d "$repo_path/.git" ]]; then
        local repo_name
        repo_name=$(basename "$repo_path")
        git -C "$repo_path" bundle create "$snapshot_dir/${repo_name}.bundle" --all 2>/dev/null || true
      fi
    done
  fi
  
  # Crear tarball comprimido del snapshot
  tar -czf "${snapshot_dir}.tar.gz" -C "$(dirname "$snapshot_dir")" "$(basename "$snapshot_dir")" 2>/dev/null || true
  
  log_success "Snapshot creado: ${snapshot_dir}.tar.gz"
  echo "$snapshot_dir"
}

# Restaurar desde snapshot
restore_snapshot() {
  local snapshot_path="$1"
  
  if [[ ! -d "$snapshot_path" && -f "${snapshot_path}.tar.gz" ]]; then
    log_info "📦 Descomprimiendo snapshot..."
    tar -xzf "${snapshot_path}.tar.gz" -C "$(dirname "$snapshot_path")" 2>/dev/null || {
      log_error "No se pudo descomprimir el snapshot"
      return 1
    }
  fi
  
  if [[ ! -d "$snapshot_path" ]]; then
    log_error "Snapshot no encontrado: $snapshot_path"
    return 1
  fi
  
  log_info "⏮️  Restaurando desde snapshot: $snapshot_path"
  
  # Restaurar Applications de ArgoCD
  if [[ -f "$snapshot_path/argocd-applications.yaml" ]]; then
    log_info "   Restaurando Applications de ArgoCD..."
    kubectl apply -f "$snapshot_path/argocd-applications.yaml" >/dev/null 2>&1 || log_warning "Fallo al restaurar applications"
  fi
  
  # Restaurar Projects
  if [[ -f "$snapshot_path/argocd-projects.yaml" ]]; then
    log_info "   Restaurando Projects de ArgoCD..."
    kubectl apply -f "$snapshot_path/argocd-projects.yaml" >/dev/null 2>&1 || log_warning "Fallo al restaurar projects"
  fi
  
  # Forzar hard refresh de todas las apps
  log_info "   Forzando sincronización de aplicaciones..."
  kubectl get app -n argocd -o name 2>/dev/null | while read -r app; do
    kubectl patch "$app" -n argocd \
      -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' \
      --type merge >/dev/null 2>&1 || true
  done
  
  log_success "Snapshot restaurado. Verifica el estado con: kubectl get applications -n argocd"
}

# Ejecutar smoke tests post-instalación
run_smoke_tests() {
  log_step "🧪 Ejecutando smoke tests de validación"
  
  local tests_passed=0
  local tests_failed=0
  local tests_total=0
  
  run_test() {
    local name="$1"
    local command="$2"
    local optional="${3:-false}"
    
    ((tests_total++))
    
    if eval "$command" >/dev/null 2>&1; then
      log_success "$name"
      ((tests_passed++))
      return 0
    else
      if [[ "$optional" == "true" ]]; then
        log_info "⏭️  $name (opcional - omitido)"
      else
        log_error "❌ $name"
        ((tests_failed++))
      fi
      return 1
    fi
  }
  
  # Tests de infraestructura básica
  log_info "🔧 Tests de infraestructura:"
  run_test "Cluster kind activo" "kind get clusters 2>/dev/null | grep -q '^${CLUSTER_NAME}$'"
  run_test "Kubectl responde" "kubectl cluster-info >/dev/null 2>&1"
  run_test "ArgoCD namespace existe" "kubectl get namespace argocd"
  run_test "Gitea namespace existe" "kubectl get namespace ${GITEA_NAMESPACE}"
  
  # Tests de APIs
  log_info "🌐 Tests de APIs:"
  run_test "ArgoCD API responde" "curl -fsS --max-time 5 http://localhost:${ARGOCD_PORT:-30080}/api/version"
  run_test "Gitea API responde" "curl -fsS --max-time 5 http://localhost:${GITEA_PORT:-30083}/api/v1/version"
  run_test "Prometheus responde" "curl -fsS --max-time 5 http://localhost:${PROMETHEUS_PORT:-30092}/-/healthy" true
  run_test "Grafana responde" "curl -fsS --max-time 5 http://localhost:${GRAFANA_PORT:-30093}/api/health" true
  
  # Tests de ArgoCD Applications
  log_info "📦 Tests de ArgoCD Applications:"
  run_test "Al menos 1 Application existe" "[[ \$(kubectl get app -n argocd --no-headers 2>/dev/null | wc -l) -gt 0 ]]"
  
  if command -v jq >/dev/null 2>&1; then
    run_test "Todas las apps están Synced" "[[ \$(kubectl get app -n argocd -o json 2>/dev/null | jq -r '.items[] | select(.status.sync.status != \"Synced\") | .metadata.name' | wc -l) -eq 0 ]]" true
    run_test "Todas las apps están Healthy" "[[ \$(kubectl get app -n argocd -o json 2>/dev/null | jq -r '.items[] | select(.status.health.status != \"Healthy\") | .metadata.name' | wc -l) -eq 0 ]]" true
  fi
  
  # Tests de componentes clave
  log_info "🔐 Tests de componentes de seguridad:"
  run_test "Sealed Secrets controller Running" "kubectl get pods -n kube-system -l name=sealed-secrets-controller -o json 2>/dev/null | jq -r '.items[].status.phase' | grep -q Running"
  run_test "CRD SealedSecrets existe" "kubectl get crd sealedsecrets.bitnami.com"
  
  # Resumen final
  echo ""
  log_info "📊 Resultados de smoke tests:"
  log_info "   Total:   $tests_total tests"
  log_success "   Passed:  $tests_passed"
  
  if [[ $tests_failed -gt 0 ]]; then
    log_error "   Failed:  $tests_failed ❌"
    log_warning "⚠️  Algunos tests fallaron. Revisa los logs para más detalles."
    return 1
  else
    log_success "🎉 ¡Todos los tests pasaron correctamente!"
    return 0
  fi
}

# Validación de conectividad de red
check_network_connectivity() {
  log_info "🌐 Verificando conectividad de red..."
  
  local test_urls=(
    "https://dl.k8s.io/release/stable.txt"
    "https://get.docker.com"
    "https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"
    "https://github.com/bitnami-labs/sealed-secrets/releases"
  )
  
  local failed=()
  local timeout=10
  
  for url in "${test_urls[@]}"; do
    if ! curl -fsS --max-time "$timeout" --head "$url" >/dev/null 2>&1; then
      failed+=("$url")
    fi
  done
  
  if (( ${#failed[@]} > 0 )); then
    log_warning "⚠️  URLs no accesibles:"
    for url in "${failed[@]}"; do
      log_warning "   ❌ $url"
    done
    log_warning ""
    log_warning "La instalación puede fallar por falta de conectividad."
    log_warning "Verifica tu conexión a Internet o configuración de proxy."
    
    if [[ "${CI_MODE:-false}" != "true" ]]; then
      log_warning ""
      read -p "¿Deseas continuar de todos modos? (y/N): " -r response
      if [[ ! "$response" =~ ^[Yy]$ ]]; then
        log_error "Instalación cancelada por el usuario"
        exit 1
      fi
    fi
    return 1
  fi
  
  log_success "Conectividad de red verificada"
  return 0
}

# Validación de recursos del sistema
check_system_resources() {
    local min_memory_gb=4
    local min_disk_gb=10
    
    # Verificar memoria disponible
    local available_memory_gb
    available_memory_gb=$(awk '/MemAvailable/ {printf "%.0f", $2/1024/1024}' /proc/meminfo 2>/dev/null || echo "0")
    if [[ $available_memory_gb -lt $min_memory_gb ]]; then
        log_warning "Memoria disponible: ${available_memory_gb}GB. Recomendado: ${min_memory_gb}GB+"
    fi
    
    # Verificar espacio en disco
    local available_disk_gb
    available_disk_gb=$(df -BG . | awk 'NR==2 {print int($4)}')
    if [[ $available_disk_gb -lt $min_disk_gb ]]; then
        log_warning "Espacio disponible: ${available_disk_gb}GB. Recomendado: ${min_disk_gb}GB+"
    fi
}

validate_prerequisites() {
  if [[ "$(uname -s)" != "Linux" ]]; then
    log_error "Este instalador está soportado solo en sistemas Linux."
    exit 1
  fi

  if [[ ! -f "$DOTFILES_DIR/install.sh" ]]; then
    log_error "Debes ejecutar este script desde la raíz del repositorio dotfiles"
    exit 1
  fi

  if [[ $EUID -eq 0 ]]; then
    log_warning "Se recomienda ejecutar el script como usuario normal con acceso a sudo."
  fi

  if ! id -nG "$USER" | grep -qw "sudo"; then
    log_error "Tu usuario necesita pertenecer al grupo sudo"
    exit 1
  fi

  # Verificar conectividad de red
  check_network_connectivity || log_warning "Continuando sin verificación completa de conectividad..."

  # Verificar recursos del sistema (si no está deshabilitado)
  if [[ "$SKIP_SYSTEM_CHECK" != "true" ]]; then
    check_system_resources
  else
    log_verbose "Verificación de recursos del sistema omitida (SKIP_SYSTEM_CHECK=true)"
  fi

  local required=(sudo apt-get curl git openssl python3)
  local missing=()
  for cmd in "${required[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing+=("$cmd")
    fi
  done

  if (( ${#missing[@]} > 0 )); then
    log_warning "Herramientas faltantes: ${missing[*]}. Se instalarán en la fase siguiente si es posible."
  else
    log_info "Sistema validado - Herramientas encontradas:"
    for cmd in "${required[@]}"; do
      if command -v "$cmd" >/dev/null 2>&1; then
        log_info "   • $cmd"
      fi
    done
  fi

  if ! id -nG "$USER" | grep -qw "docker"; then
    log_warning "El usuario no pertenece al grupo docker. Se añadirá durante la instalación."
  fi

  log_success "Prerequisitos validados"
}

# =============================================================================
# FUNCIONES DE INSTALACIÓN
# =============================================================================

install_system_base() {
    # Actualizar sistema
    log_info "Actualizando sistema Ubuntu/WSL..."
    sudo apt-get update -y >/dev/null 2>&1
    sudo apt-get upgrade -y >/dev/null 2>&1

    # Herramientas básicas
    log_info "Instalando herramientas básicas..."
    sudo apt-get install -y \
        curl wget git unzip ca-certificates gnupg lsb-release \
        jq tree htop vim zsh yamllint shellcheck >/dev/null 2>&1

    # Oh My Zsh
    if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
        log_info "Instalando Oh My Zsh..."
        sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended >/dev/null 2>&1
    fi

    # Configurar zsh como shell por defecto
    if [[ "$SHELL" != */zsh ]]; then
        log_info "Configurando zsh como shell por defecto..."
        sudo chsh -s "$(which zsh)" "$USER" >/dev/null 2>&1
    fi

    log_success "Sistema base instalado"
}

install_docker_and_tools() {
    # Docker (debe ir primero y secuencialmente)
  if ! command -v docker >/dev/null 2>&1; then
    log_info "Instalando Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh >/dev/null 2>&1
    sudo usermod -aG docker "$USER"
    rm get-docker.sh
  else
    log_info "Docker ya está instalado"
  fi

    # Instalación paralela de kubectl, kind y helm (si está habilitado)
    if [[ "${PARALLEL_INSTALL:-true}" == "true" ]]; then
      log_info "Instalando herramientas en paralelo..."
      
      # Función auxiliar para instalación en background con logging
      install_tool() {
        local tool_name="$1"
        shift
        if "$@" 2>&1 | tee "/tmp/install-${tool_name}.log" >/dev/null; then
          log_success "${tool_name} instalado"
          return 0
        else
          log_error "Error instalando ${tool_name}"
          return 1
        fi
      }
      
      # kubectl (debe instalarse primero - dependencia de kind)
      local kubectl_pid=""
      if ! command -v kubectl >/dev/null 2>&1; then
        (
          install_tool "kubectl" bash -c '
            curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
            sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
            rm kubectl
          '
        ) &
        kubectl_pid=$!
      else
        log_info "kubectl ya está instalado"
      fi
      
      # Helm (independiente - puede ir en paralelo con kubectl)
      if ! command -v helm >/dev/null 2>&1; then
        (
          install_tool "helm" bash -c '
            curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
          '
        ) &
      else
        log_info "Helm ya está instalado"
      fi
      
      # Esperar a kubectl antes de instalar kind (dependencia)
      if [[ -n "$kubectl_pid" ]]; then
        wait "$kubectl_pid"
      fi
      
      # kind (depende de kubectl para health checks)
      if ! command -v kind >/dev/null 2>&1; then
        (
          install_tool "kind" bash -c '
            if [[ "$(uname -m)" == "x86_64" ]]; then
              curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.30.0/kind-linux-amd64
              sudo install -o root -g root -m 0755 kind /usr/local/bin/kind
              rm kind
            else
              echo "Arquitectura $(uname -m) no soportada"
              exit 1
            fi
          '
        ) &
      else
        log_info "kind ya está instalado"
      fi
      
      # Esperar a que todas las instalaciones paralelas terminen
      wait
      
      # Verificar que todas las herramientas estén disponibles
      local tools_ok=true
      for tool in kubectl kind helm; do
        if ! command -v "$tool" >/dev/null 2>&1; then
          log_error "$tool no se instaló correctamente"
          tools_ok=false
        fi
      done
      
      if [[ "$tools_ok" != "true" ]]; then
        log_error "Algunas herramientas no se instalaron correctamente"
        exit 1
      fi
    else
      # Instalación secuencial (modo legacy)
      log_info "Instalando herramientas secuencialmente..."
      
      # kubectl
      if ! command -v kubectl >/dev/null 2>&1; then
        log_info "Instalando kubectl..."
        curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
        sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
        rm kubectl
      else
        log_info "kubectl ya está instalado"
      fi

      # kind
      if ! command -v kind >/dev/null 2>&1; then
        log_info "Instalando kind..."
        if [[ "$(uname -m)" == "x86_64" ]]; then
          curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.30.0/kind-linux-amd64
          sudo install -o root -g root -m 0755 kind /usr/local/bin/kind
          rm kind
        else
          log_error "Arquitectura $(uname -m) no soportada para kind"
          exit 1
        fi
      else
        log_info "kind ya está instalado"
      fi

      # Helm
      if ! command -v helm >/dev/null 2>&1; then
        log_info "Instalando Helm..."
        curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash >/dev/null 2>&1
      else
        log_info "Helm ya está instalado"
      fi
    fi

    log_success "Docker y herramientas Kubernetes instaladas"
}

create_cluster() {
    # Verificar si el cluster ya existe
    if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
        log_info "Cluster $CLUSTER_NAME ya existe, eliminando..."
        kind delete cluster --name "$CLUSTER_NAME" >/dev/null 2>&1
    fi

    # Crear cluster con configuración de puertos
    log_info "Creando cluster kind con puertos mapeados..."
    cat <<EOF | kind create cluster --name "$CLUSTER_NAME" --config=- >/dev/null 2>&1
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  # Rango completo NodePorts (30000-30100) para GitOps tools
  # Cada herramienta GitOps define su propio NodePort en sus manifests
  # ArgoCD usa 30080 para bootstrapping inicial
  - containerPort: 30000
    hostPort: 30000
    protocol: TCP
  - containerPort: 30001
    hostPort: 30001
    protocol: TCP  
  - containerPort: 30002
    hostPort: 30002
    protocol: TCP
  - containerPort: 30003
    hostPort: 30003
    protocol: TCP
  - containerPort: 30004
    hostPort: 30004
    protocol: TCP
  - containerPort: 30005
    hostPort: 30005
    protocol: TCP
  - containerPort: 30010
    hostPort: 30010
    protocol: TCP
  - containerPort: 30020
    hostPort: 30020
    protocol: TCP
  - containerPort: 30022
    hostPort: 30022
    protocol: TCP
  - containerPort: 30030
    hostPort: 30030
    protocol: TCP
  - containerPort: 30040
    hostPort: 30040
    protocol: TCP
  - containerPort: 30050
    hostPort: 30050
    protocol: TCP
  - containerPort: 30060
    hostPort: 30060
    protocol: TCP  
  - containerPort: 30070
    hostPort: 30070
    protocol: TCP
  # ArgoCD bootstrapping - puerto crítico para acceso inicial
  - containerPort: 30080
    hostPort: 30080
    protocol: TCP
  - containerPort: 30081
    hostPort: 30081
    protocol: TCP
  - containerPort: 30082
    hostPort: 30082
    protocol: TCP
  - containerPort: 30083
    hostPort: 30083
    protocol: TCP
  - containerPort: 30084
    hostPort: 30084
    protocol: TCP
  - containerPort: 30085
    hostPort: 30085
    protocol: TCP
  - containerPort: 30086
    hostPort: 30086
    protocol: TCP
  - containerPort: 30087
    hostPort: 30087
    protocol: TCP
  - containerPort: 30088
    hostPort: 30088
    protocol: TCP
  - containerPort: 30089
    hostPort: 30089
    protocol: TCP
  - containerPort: 30090
    hostPort: 30090
    protocol: TCP
  - containerPort: 30091
    hostPort: 30091
    protocol: TCP
  - containerPort: 30092
    hostPort: 30092
    protocol: TCP
  - containerPort: 30093
    hostPort: 30093
    protocol: TCP
  - containerPort: 30094
    hostPort: 30094
    protocol: TCP
  - containerPort: 30095
    hostPort: 30095
    protocol: TCP
  - containerPort: 30096
    hostPort: 30096
    protocol: TCP
  - containerPort: 30097
    hostPort: 30097
    protocol: TCP
  - containerPort: 30098
    hostPort: 30098
    protocol: TCP
  - containerPort: 30099
    hostPort: 30099
    protocol: TCP
  - containerPort: 30100
    hostPort: 30100
    protocol: TCP
EOF

    log_success "Cluster kind creado"
    
    # Esperar a que el nodo esté listo antes de continuar
    log_info "Esperando a que el nodo esté listo..."
    kubectl wait --for=condition=Ready nodes --all --timeout=120s >/dev/null 2>&1
    log_success "Nodo listo"

    # Esperar a que CoreDNS esté listo (esencial para que funcione el cluster)
    log_info "Esperando a que CoreDNS esté listo..."
    kubectl wait --for=condition=Ready pod -l k8s-app=kube-dns -n kube-system --timeout=120s >/dev/null 2>&1
    log_success "CoreDNS listo"

    # Instalar ArgoCD
    log_info "🔧 Instalando ArgoCD ${ARGOCD_VERSION:-v3.2.0-rc3}..."
    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1
    local argocd_version="${ARGOCD_VERSION:-v3.2.0-rc3}"
    
    log_info "   📥 Descargando manifests desde GitHub..."
    if ! kubectl apply -n argocd -f "https://raw.githubusercontent.com/argoproj/argo-cd/${argocd_version}/manifests/install.yaml" --validate=false >/dev/null 2>&1; then
        log_error "Error al instalar ArgoCD ${argocd_version}"
        exit 1
    fi
    log_success "   Manifests aplicados (34 recursos creados)"

    # Aplicar ConfigMaps de configuración inmediatamente (sin SSL, sin auth)
    log_info "   ⚙️  Configurando modo insecure (sin TLS ni autenticación)..."
    kubectl apply -f "$DOTFILES_DIR/argo-config/configmaps/argocd-cmd-params-cm.yaml" >/dev/null 2>&1
    kubectl apply -f "$DOTFILES_DIR/argo-config/configmaps/argocd-cm.yaml" >/dev/null 2>&1
    log_success "   Configuración aplicada"

    # Reiniciar ArgoCD para que lea la nueva configuración
    log_info "   🔄 Reiniciando componentes..."
    kubectl rollout restart deployment/argocd-server -n argocd >/dev/null 2>&1 || true
    kubectl rollout restart deployment/argocd-repo-server -n argocd >/dev/null 2>&1 || true
    sleep 3

  # Esperar a que ArgoCD esté listo con la nueva configuración (robusto)
  log_info "   ⏳ Esperando pods de ArgoCD (0/7 Ready)..."
  local argocd_components=(
    "deploy/argocd-server"
    "deploy/argocd-repo-server"
    "deploy/argocd-applicationset-controller"
    "deploy/argocd-dex-server"
    "deploy/argocd-notifications-controller"
    "deploy/argocd-redis"
    "sts/argocd-application-controller"
  )

  local ready_count=0
  for component in "${argocd_components[@]}"; do
    kubectl -n argocd rollout status "$component" --timeout=600s >/dev/null 2>&1 && ((ready_count++)) || true
    log_info "   ⏳ Esperando pods de ArgoCD ($ready_count/7 Ready)..."
  done
  
  log_success "   🎉 ArgoCD instalado (7/7 pods Ready)"

  # Configurar solo ArgoCD para bootstrapping (otros servicios usan manifests GitOps)
  configure_argocd_bootstrap

    # Verificar mapeos de puertos (sanity check)
    if ! check_mapping_sanity; then
        log_warning "Problemas detectados en el mapeo de puertos; revisa los mensajes previos"
    fi

    # Chequeo adicional de conflictos de NodePort
    check_nodeport_conflicts || true

    # Instalar Sealed Secrets Controller (bootstrap - antes de GitOps)
    install_sealed_secrets_bootstrap

    log_success "Cluster y ArgoCD creados (acceso sin autenticación)"
}

# Instalar Sealed Secrets Controller como bootstrap (antes de GitOps)
install_sealed_secrets_bootstrap() {
  log_info "📦 Instalando Sealed Secrets Controller (bootstrap)..."
  
  # El controller.yaml oficial instala en kube-system (no crear namespace custom)
  local sealed_secrets_url="https://github.com/bitnami-labs/sealed-secrets/releases/download/${KUBESEAL_VERSION}/controller.yaml"
  
  if ! kubectl apply -f "$sealed_secrets_url" >/dev/null 2>&1; then
    log_error "No se pudo instalar Sealed Secrets Controller"
    return 1
  fi
  
  log_info "Esperando a que Sealed Secrets Controller esté listo..."
  
  # Esperar a que el deployment esté listo (en kube-system)
  if ! kubectl -n kube-system rollout status deployment/sealed-secrets-controller --timeout=180s >/dev/null 2>&1; then
    log_warning "Sealed Secrets Controller tardó más de lo esperado"
    # Verificar si al menos existe el pod
    if kubectl get pods -n kube-system -l name=sealed-secrets-controller 2>/dev/null | grep -q "sealed-secrets-controller"; then
      log_info "Pod de Sealed Secrets Controller encontrado, continuando..."
      return 0
    fi
    return 1
  fi
  
  # Verificar que el pod esté Running
  local retries=30
  while [[ $retries -gt 0 ]]; do
    if kubectl get pods -n kube-system -l name=sealed-secrets-controller --field-selector=status.phase=Running 2>/dev/null | grep -q "sealed-secrets-controller"; then
      log_success "Sealed Secrets Controller listo y funcionando"
      return 0
    fi
    sleep 2
    retries=$((retries - 1))
  done
  
  log_warning "Sealed Secrets Controller no responde pero continuamos"
  return 0
}


build_and_load_images() {
  if [[ "$ENABLE_CUSTOM_APPS" != "true" ]]; then
    log_info "Fase de imágenes de aplicaciones personalizadas deshabilitada (ENABLE_CUSTOM_APPS=${ENABLE_CUSTOM_APPS})."
    log_success "Imágenes personalizadas omitidas"
    return 0
  fi
    
    # Verificar si existe la estructura de repositorios
    local gitops_base_dir="$HOME/gitops-repos"
    local source_dir
    
  if [[ -d "$gitops_base_dir/sourcecode-apps/demo-api" ]]; then
    source_dir="$gitops_base_dir/sourcecode-apps/demo-api"
        log_info "Usando código fuente desde: $source_dir"
  else
    source_dir="$DOTFILES_DIR/sourcecode-apps/demo-api"
        log_info "Usando código fuente desde dotfiles: $source_dir"
    fi
    
    # Verificar que el directorio existe
    if [[ ! -d "$source_dir" ]]; then
        log_error "Directorio de código fuente no encontrado: $source_dir"
        return 1
    fi
    
  # Determinar tag de la imagen en base a package.json (si existe)
  local image_name="demo-api"
  local version=""
  if [[ -f "$source_dir/package.json" ]]; then
    version=$(jq -r '.version // empty' "$source_dir/package.json" 2>/dev/null || echo "")
    if [[ -z "$version" || "$version" == "null" ]]; then
      version="1.0.0"
    fi
  else
    version="1.0.0"
  fi

  local registry_host="localhost:30500"
  local local_tag="${image_name}:v${version}"
  local registry_tag="${registry_host}/${local_tag}"

  log_info "Construyendo imagen ${local_tag}..."
  (
    cd "$source_dir" || exit 1
    docker build -t "$local_tag" -t "$registry_tag" . >/dev/null 2>&1
  )

  # Verificar que el registry está disponible
  log_info "Verificando registry en ${registry_host}..."
  # Primero esperar a que el Deployment del registry tenga al menos 1 ready replica
  if ! wait_for_condition "kubectl -n registry get deploy docker-registry -o jsonpath='{.status.readyReplicas}' 2>/dev/null | grep -q '^1$'" 180 5 10; then
    log_warning "El Deployment del registry no parece tener réplicas listas aún"
  fi

  # Luego comprobar el endpoint HTTP del registry (tolerante a race conditions)
  if ! wait_for_condition "curl -fsS --max-time 5 http://${registry_host}/v2/ >/dev/null 2>&1" 180 5 10; then
    log_error "Registry no está disponible en ${registry_host} después de esperar"
    return 1
  fi

  # Push a registry local
  log_info "Publicando ${registry_tag} en registry..."
  if ! docker push "$registry_tag" >/dev/null 2>&1; then
    log_error "No se pudo publicar la imagen en el registry"
    return 1
  fi

  log_success "Imagen construida y publicada: ${registry_tag}"

  # Actualizar manifest de demo-api con el nuevo tag
  local manifest_dir="$gitops_base_dir/gitops-custom-apps/demo-api"
  if [[ -d "$manifest_dir" ]]; then
    log_info "Actualizando manifest de demo-api con tag: ${registry_tag}"
    
    # Buscar y actualizar la referencia de imagen en deployment.yaml
    if [[ -f "$manifest_dir/deployment.yaml" ]]; then
  # Actualizar referencia de imagen y policy si existe
  sed -i "s|image:.*demo-api.*|image: ${registry_tag}|g" "$manifest_dir/deployment.yaml" || true
  sed -i "s|imagePullPolicy:.*|imagePullPolicy: IfNotPresent|g" "$manifest_dir/deployment.yaml" || true
      
      # Commit y push del cambio
      (
        cd "$manifest_dir/.." || exit 1
        git add demo-api/deployment.yaml
        git commit -m "chore: update demo-api image to ${registry_tag}" >/dev/null 2>&1 || true
        git push >/dev/null 2>&1 || true
      )
      
      log_success "Manifest actualizado y sincronizado con Gitea"
    else
      log_warning "No se encontró deployment.yaml en $manifest_dir"
    fi
  else
    log_warning "Directorio de manifests no encontrado: $manifest_dir"
  fi

  log_success "Proceso de construcción e integración completado"
}

setup_gitops() {
    # Asegurar que kubectl esté configurado para el cluster correcto
    if ! kubectl config current-context >/dev/null 2>&1; then
        log_info "Configurando contexto kubectl para cluster kind..."
        kubectl config use-context "kind-${CLUSTER_NAME}" >/dev/null 2>&1 || {
            log_error "No se pudo configurar el contexto de kubectl. ¿Existe el cluster?"
            kubectl config get-contexts
            exit 1
        }
    fi
    
    # Generar credenciales automáticamente
  local gitea_password=""
  local existing_secret
  existing_secret=$(kubectl -n "$GITEA_NAMESPACE" get secret gitea-admin-secret -o jsonpath="{.data.password}" 2>/dev/null || true)
  if [[ -n "$existing_secret" ]]; then
    gitea_password=$(echo "$existing_secret" | base64 -d 2>/dev/null || echo "")
    if [[ -n "$gitea_password" ]]; then
      log_info "Usando password existente para Gitea."
    fi
  fi

  if [[ -z "$gitea_password" ]]; then
    gitea_password=$(generate_secure_password 16)
    log_info "Password generado para Gitea: $gitea_password"
  fi

  export GITEA_ADMIN_PASSWORD="$gitea_password"
  log_info "Password para Gitea: $gitea_password"

  # Instalar Gitea
  install_gitea

    # Configurar e instalar Gitea Actions con runner
    if install_gitea_actions; then
      log_success "Gitea Actions instalado/configurado correctamente"
    else
      log_warning "Gitea Actions: instalación/config con advertencias; revisa la configuración"
    fi
    
    # Crear repositorios y subir manifests
    create_gitops_repositories
    
    # Configurar ApplicationSets
    setup_application_sets

    log_success "GitOps configurado completamente"
}

install_gitea() {
    log_info "🔧 Instalando Gitea..."
    
    kubectl create namespace "$GITEA_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1

    # Crear secret con password
    kubectl create secret generic gitea-admin-secret \
        --from-literal=password="$GITEA_ADMIN_PASSWORD" \
        -n "$GITEA_NAMESPACE" \
        --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1

    # Aplicar manifests de Gitea
    kubectl apply -f - >/dev/null 2>&1 <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: gitea-pvc
  namespace: $GITEA_NAMESPACE
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 2Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gitea
  namespace: $GITEA_NAMESPACE
  labels:
    app: gitea
spec:
  replicas: 1
  selector:
    matchLabels:
      app: gitea
  template:
    metadata:
      labels:
        app: gitea
    spec:
      containers:
      - name: gitea
        image: gitea/gitea:1.22
        ports:
        - containerPort: 3000
        - containerPort: 22
        env:
        - name: GITEA__database__DB_TYPE
          value: sqlite3
        - name: GITEA__security__INSTALL_LOCK
          value: "true"
        - name: GITEA__service__DISABLE_REGISTRATION
          value: "true"
        - name: GITEA__service__REQUIRE_SIGNIN_VIEW
          value: "false"
        - name: GITEA__openid__ENABLE_OPENID_SIGNIN
          value: "false"
        - name: GITEA__openid__ENABLE_OPENID_SIGNUP
          value: "false"
        - name: GITEA__actions__ENABLED
          value: "true"
        - name: GITEA__actions__DEFAULT_ACTIONS_URL
          value: "github"
        volumeMounts:
        - name: gitea-storage
          mountPath: /data
      volumes:
      - name: gitea-storage
        persistentVolumeClaim:
          claimName: gitea-pvc
---
apiVersion: v1
kind: Service
metadata:
  name: gitea
  namespace: $GITEA_NAMESPACE
spec:
  type: NodePort
  ports:
  - port: 3000
    targetPort: 3000
    nodePort: 30083
    name: http
  - port: 22
    targetPort: 22
    nodePort: 30022
    name: ssh
  selector:
    app: gitea
EOF

  log_success "Manifests de Gitea aplicados"
  wait_for_gitea_readiness
}

### Gitea Actions support - enable in app.ini and deploy a simple runner
install_gitea_actions() {
  log_step "Configurando Gitea Actions (habilitar y desplegar runner)"

  # Actions ya está habilitado via env vars en el deployment
  log_info "Gitea Actions habilitado via variables de entorno (Gitea 1.22)"

  local runner_token=""
  if runner_token=$(generate_gitea_actions_token); then
    log_success "Token de registro de Actions generado via CLI"
    deploy_actions_runner "$runner_token" || {
      log_warning "No se pudo desplegar runner de Actions. Revisa manualmente."
      return 1
    }
    
    # Verificar que el runner quedó registrado correctamente
    log_info "Verificando que el runner esté operativo..."
    sleep 10  # Dar tiempo al runner para registrarse
    
    if kubectl -n "$GITEA_NAMESPACE" get pods -l app=gitea-actions-runner --field-selector=status.phase=Running | grep -q Running; then
      log_success "Gitea Actions configurado - Runner operativo y listo para ejecutar workflows"
      return 0
    else
      log_warning "Runner desplegado pero puede necesitar más tiempo para estar operativo"
      return 1
    fi
  else
    log_error "No se pudo generar token de registro para Actions"
    return 1
  fi
}

deploy_actions_runner() {
  local runner_token="$1"
  log_info "Desplegando runner básico para Gitea Actions (pod en cluster)"

  if [[ -z "$runner_token" ]]; then
    log_warning "Token de registro vacío; no se desplegará runner"
    return 0
  fi

  # Creamos un ServiceAccount y un Deployment que ejecute un runner ligero (imagen oficial o community)
  # Nota: En entornos offline, el usuario debe proveer la imagen del runner

  if [[ -n "$runner_token" ]]; then
    kubectl -n "$GITEA_NAMESPACE" create secret generic gitea-actions-runner-token \
      --from-literal=token="$runner_token" \
      --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1 || true
  fi

  cleanup_existing_gitea_runner "kind-runner-1"

  kubectl -n "$GITEA_NAMESPACE" apply -f - <<EOF >/dev/null 2>&1
apiVersion: v1
kind: ServiceAccount
metadata:
  name: gitea-actions-runner
  namespace: $GITEA_NAMESPACE
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gitea-actions-runner
  namespace: $GITEA_NAMESPACE
spec:
  replicas: 1
  selector:
    matchLabels:
      app: gitea-actions-runner
  template:
    metadata:
      labels:
        app: gitea-actions-runner
    spec:
      serviceAccountName: gitea-actions-runner
      containers:
      - name: runner
        image: gitea/act_runner:nightly
        command:
        - /bin/sh
        - -c
        - |
          set -eo pipefail
          act_runner register \
            --no-interactive \
            --instance "\$GITEA_URL" \
            --token "\$RUNNER_TOKEN" \
            --name "\$RUNNER_NAME" \
            --labels "\$RUNNER_LABELS"
          exec act_runner daemon
        env:
        - name: GITEA_URL
          value: "http://gitea.gitea.svc.cluster.local:3000"
        - name: RUNNER_NAME
          value: "kind-runner-1"
        - name: RUNNER_LABELS
          value: "self-hosted,kubernetes"
        - name: RUNNER_TOKEN
          valueFrom:
            secretKeyRef:
              name: gitea-actions-runner-token
              key: token
              optional: true
        resources:
          limits:
            cpu: "200m"
            memory: "256Mi"
          requests:
            cpu: "50m"
            memory: "64Mi"
      restartPolicy: Always
EOF

  if ! kubectl -n "$GITEA_NAMESPACE" rollout status deployment/gitea-actions-runner --timeout=180s >/dev/null 2>&1; then
    log_warning "El runner no alcanzó estado Ready; revisa los logs con: kubectl logs -n $GITEA_NAMESPACE deployment/gitea-actions-runner"
    return 1
  fi

  log_success "Runner registrado y desplegado"
  return 0
}

create_gitops_repositories() {
    log_info "Creando repositorios GitOps en Gitea..."
    
    # Directorio base para repositorios GitOps (fuera de dotfiles)
    local gitops_base_dir="$HOME/gitops-repos"
    
    # Esperar a que Gitea API esté disponible
    log_info "Esperando a que Gitea API esté disponible..."
  if ! wait_for_condition "curl -fsS --output /dev/null http://localhost:30083/api/v1/version" 180 3 15; then
    log_error "Gitea API no respondió a tiempo. Revisa el estado con: kubectl logs -n $GITEA_NAMESPACE deployment/gitea"
    return 1
  fi
    
    # Crear usuario gitops usando la base de datos SQLite directamente via kubectl exec
    log_info "Creando usuario admin 'gitops' directamente en Gitea..."
    local pod_name
    pod_name=$(kubectl get pods -n "$GITEA_NAMESPACE" -l app=gitea -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [[ -n "$pod_name" ]]; then
      # Usar el comando gitea admin user create con --config para evitar el check de root
      kubectl exec -n "$GITEA_NAMESPACE" "$pod_name" -- sh -c \
        "su -s /bin/sh git -c 'gitea --config /data/gitea/conf/app.ini admin user create --username gitops --password $GITEA_ADMIN_PASSWORD --email gitops@localhost --admin --must-change-password=false'" \
        2>/dev/null || log_info "Usuario gitops ya existe o no se pudo crear via CLI"
    fi
    
    # Verificar si el usuario existe intentando hacer login
    local login_check
    login_check=$(curl -fsS -X POST "http://localhost:30083/api/v1/users/gitops/tokens" \
      -H "Content-Type: application/json" \
      -u "gitops:${GITEA_ADMIN_PASSWORD}" \
      -d '{"name":"test"}' 2>/dev/null || echo "")
    
    if [[ -z "$login_check" ]]; then
      log_warning "No se pudo verificar usuario gitops, intentando creación alternativa..."
      # Fallback: habilitar registro temporalmente, crear usuario, deshabilitar
      kubectl exec -n "$GITEA_NAMESPACE" "$pod_name" -- sh -c \
        "echo 'DISABLE_REGISTRATION = false' >> /data/gitea/conf/app.ini" 2>/dev/null || true
      
      sleep 2
      
      curl -X POST "http://localhost:30083/user/sign_up" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "user_name=gitops&email=gitops@localhost&password=$GITEA_ADMIN_PASSWORD&retype=$GITEA_ADMIN_PASSWORD" \
        >/dev/null 2>&1 || true
        
      sleep 2
      
      kubectl exec -n "$GITEA_NAMESPACE" "$pod_name" -- sh -c \
        "sed -i 's/DISABLE_REGISTRATION = false/DISABLE_REGISTRATION = true/' /data/gitea/conf/app.ini" 2>/dev/null || true
    fi
    
    log_success "Usuario 'gitops' creado/verificado en Gitea"
    
    # Esperar un momento para que la cuenta se active
    sleep 2

    # Crear estructuras de repositorios persistentes
    mkdir -p "$gitops_base_dir"
    
    # Crear repositorios GitOps
  local repo_definitions=(
    "gitops-tools|$DOTFILES_DIR/manifests/gitops-tools|GitOps tools manifests"
    "custom-apps|$DOTFILES_DIR/manifests/custom-apps|GitOps custom applications manifests"
    "argo-config|$DOTFILES_DIR/argo-config|GitOps ArgoCD configuration"
  )

  for definition in "${repo_definitions[@]}"; do
    IFS='|' read -r repo src_dir description <<< "$definition"
    log_info "Creando repositorio: $repo"

    curl -X POST "http://localhost:30083/api/v1/user/repos" \
      -H "Content-Type: application/json" \
      -u "gitops:${GITEA_ADMIN_PASSWORD}" \
      -d "{\"name\": \"$repo\", \"description\": \"$description\", \"auto_init\": true, \"private\": false}" >/dev/null 2>&1 || true

    local repo_dir
    case "$repo" in
      infrastructure)
        repo_dir="$gitops_base_dir/gitops-infrastructure"
        ;;
      custom-apps)
        repo_dir="$gitops_base_dir/gitops-custom-apps"
        ;;
      argo-config)
        repo_dir="$gitops_base_dir/argo-config"
        ;;
      *)
        repo_dir="$gitops_base_dir/$repo"
        ;;
    esac

    local skip_disabled=true
    if [[ "$repo" == "argo-config" ]]; then
      skip_disabled=false
    fi

    bootstrap_local_repo "$src_dir" "$repo_dir" "Initial $repo contents" "$skip_disabled"

    if [[ "$repo" == "argo-config" && "$ENABLE_CUSTOM_APPS" != "true" ]]; then
      local custom_file="$repo_dir/applications/custom-apps.yaml"
      if [[ -f "$custom_file" ]]; then
        rm -f "$custom_file"
        (
          cd "$repo_dir" || exit 1
          git add -u applications/custom-apps.yaml
          git commit --amend --no-edit >/dev/null 2>&1 || true
        )
        log_info "   ApplicationSet custom-apps eliminado (ENABLE_CUSTOM_APPS=false)"
      fi
    fi

    push_repo_to_gitea "$repo_dir" "$repo"
  log_success "$repo → $repo_dir"
  done

    # Crear repositorios de código fuente para desarrollo
    create_source_repositories "$gitops_base_dir"
    
    # Nota: La generación del SealedSecret de Kargo se ejecuta tras desplegar sealed-secrets
    cd "$DOTFILES_DIR"
}

create_source_repositories() {
    local base_dir="$1"
    log_info "Creando repositorios de código fuente para desarrollo..."

  local apps_dir="$base_dir/sourcecode-apps"
  mkdir -p "$apps_dir"

  if [[ "$ENABLE_CUSTOM_APPS" != "true" ]]; then
    log_info "Se omite la creación de repositorios de aplicaciones personalizadas (ENABLE_CUSTOM_APPS=${ENABLE_CUSTOM_APPS})."
    return 0
  fi
    
  # Directorio para aplicaciones de desarrollo
    
  # Crear repositorio demo-api para desarrollo
  local app_dir="$apps_dir/demo-api"
    rm -rf "$app_dir"
    mkdir -p "$app_dir"
    
  # Copiar código fuente desde dotfiles
  cp -r "$DOTFILES_DIR/sourcecode-apps/demo-api/"* "$app_dir/"
    
    # Inicializar repositorio git para desarrollo
    (
        cd "$app_dir" || exit 1
        git init -b main >/dev/null 2>&1
        git checkout -B main >/dev/null 2>&1
        git config user.name "Developer"
        git config user.email "dev@localhost"
        git add .
  git commit -m "Initial demo-api application

- API Node.js demo para GitOps
- Dockerfile listo para pipelines CI/CD
- Health checks y readiness probes
- Configuración preparada para ArgoCD" >/dev/null 2>&1
    )
    
    # Crear repositorio en Gitea para el código fuente
    curl -X POST "http://localhost:30083/api/v1/user/repos" \
        -H "Content-Type: application/json" \
        -u "gitops:$GITEA_ADMIN_PASSWORD" \
        -d "{
            \"name\": \"demo-api\",
            \"description\": \"Demo API Application Source Code\",
            \"auto_init\": false,
            \"private\": false
    }" >/dev/null 2>&1 || true

    # Subir código fuente a Gitea
    (
        cd "$app_dir" || exit 1
        git remote remove origin >/dev/null 2>&1 || true
  git remote add origin "http://gitops:$GITEA_ADMIN_PASSWORD@localhost:30083/gitops/demo-api.git"
    git push --set-upstream origin main --force >/dev/null 2>&1
    )
    
  log_success "demo-api → $app_dir"
    log_info "📁 Estructura creada:"
    log_info "   $base_dir/gitops-infrastructure/  (manifests K8s)"
    log_info "   $base_dir/gitops-custom-apps/     (manifests apps)"
  log_info "   $base_dir/sourcecode-apps/demo-api/ (código fuente)"
}

setup_application_sets() {
  log_info "Registrando ArgoCD self-management (siguiendo ArgoCD Best Practices)..."

  # Primero crear el proyecto para self-management
  log_info "Creando proyecto argocd-config para self-management..."
  kubectl apply -f "$DOTFILES_DIR/argo-config/projects/argocd-config.yaml" >/dev/null 2>&1
  
  # Application ArgoCD self-management: cubre proyectos, apps, repos y configmaps
  kubectl apply -f - >/dev/null 2>&1 <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: argocd-self-config
  namespace: argocd
  annotations:
    argocd.argoproj.io/managed-by: bootstrap
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: argocd-config
  sources:
    - repoURL: http://gitea.gitea.svc.cluster.local:3000/gitops/argo-config.git
      targetRevision: HEAD
      path: projects
      directory:
        recurse: true
    - repoURL: http://gitea.gitea.svc.cluster.local:3000/gitops/argo-config.git
      targetRevision: HEAD
      path: applications
      directory:
        recurse: true
    - repoURL: http://gitea.gitea.svc.cluster.local:3000/gitops/argo-config.git
      targetRevision: HEAD
      path: repositories
      directory:
        recurse: true
    - repoURL: http://gitea.gitea.svc.cluster.local:3000/gitops/argo-config.git
      targetRevision: HEAD
      path: configmaps
      directory:
        recurse: true
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
    - PrunePropagationPolicy=foreground
    - PruneLast=true
  ignoreDifferences:
    # Ignorar diferencias en Applications hijo para permitir debug manual
    - group: "argoproj.io"
      kind: "Application"
      namespace: "argocd"
      jsonPointers:
        - /spec/syncPolicy/automated
        - /metadata/annotations/argocd.argoproj.io~1refresh
        - /operation
EOF

  log_success "ArgoCD self-config registrado"
  log_info "Esperando a que ArgoCD self-config esté Synced/Healthy..."
  wait_for_condition "kubectl -n argocd get app argocd-self-config -o jsonpath='{.status.sync.status} {.status.health.status}' 2>/dev/null | grep -q 'Synced Healthy'" 180 5 || log_warning "argocd-self-config todavía no está totalmente sincronizado"

  # Crear namespaces antes de que ArgoCD intente desplegar aplicaciones
  create_gitops_namespaces

  # Generar SealedSecrets ANTES de sincronizar aplicaciones (Kargo y Grafana necesitan sus secrets)
  log_info "🔐 Generando SealedSecrets para aplicaciones..."
  
  if ! create_kargo_secret_workaround; then
    log_error "❌ No se pudo crear el SealedSecret de Kargo"
    log_error "   Kargo no podrá arrancar sin este secret"
    return 1
  fi
  
  create_grafana_secret || log_warning "No se pudo crear SealedSecret de Grafana (continuando...)"
  sync_sealedsecret_to_gitea || log_warning "No se pudo sincronizar SealedSecrets a Gitea"

  # Ahora sí, sincronizar aplicaciones (los secrets ya están listos)
  wait_and_sync_applications

  # Hard refresh selectivo si namespaces fueron recreados recientemente
  hard_refresh_if_recent "kargo" "kargo" 900
  hard_refresh_if_recent "prometheus" "prometheus" 900
  hard_refresh_if_recent "grafana" "grafana" 900
  hard_refresh_if_recent "dashboard" "kubernetes-dashboard" 900
  hard_refresh_if_recent "argo-rollouts" "argo-rollouts" 900

  # Verificar servicios desplegados (NodePorts configurados via manifests GitOps)
  verify_gitops_services
  
  # Aplicar fixes críticos post-instalación
  apply_critical_fixes
}

apply_critical_fixes() {
  log_info "🔧 Aplicando fixes críticos para Argo Workflows + Events..."
  
  # FIX 1: ClusterRoleBinding para workflow-controller (necesario para WorkflowTemplates)
  log_info "📋 Creando ClusterRoleBinding para workflow-controller..."
  if ! kubectl get clusterrolebinding argo-workflow-controller-binding >/dev/null 2>&1; then
    kubectl create clusterrolebinding argo-workflow-controller-binding \
      --clusterrole=argo-cluster-role \
      --serviceaccount=argo-workflows:argo >/dev/null 2>&1 && \
      log_success "  ✅ ClusterRoleBinding creado (permite leer WorkflowTemplates)" || \
      log_warning "  ⚠️  No se pudo crear ClusterRoleBinding"
  else
    log_info "  ✅ ClusterRoleBinding ya existe"
  fi
  
  # FIX 2: Parche para Sensor (workaround bug Argo Events v1.9.7)
  log_info "🔨 Aplicando workaround RBAC para Argo Events Sensor..."
  
  # Esperar a que el sensor esté desplegado
  local sensor_ready=false
  for i in {1..30}; do
    if kubectl get sensor gitea-workflow-trigger -n argo-events >/dev/null 2>&1; then
      sensor_ready=true
      break
    fi
    sleep 2
  done
  
  if [[ "$sensor_ready" == true ]]; then
    sleep 5  # Dar tiempo a que se cree el deployment
    
    # Obtener nombre del deployment generado por el sensor
    local sensor_deployment
    sensor_deployment=$(kubectl get deployment -n argo-events --no-headers 2>/dev/null | \
      grep gitea-workflow-trigger-sensor | awk '{print $1}' | head -1)
    
    if [[ -n "$sensor_deployment" ]]; then
      log_info "  Parcheando deployment: $sensor_deployment"
      kubectl patch deployment "$sensor_deployment" -n argo-events \
        -p '{"spec":{"template":{"spec":{"serviceAccountName":"argo-events-sensor-sa"}}}}' \
        >/dev/null 2>&1 && \
        log_success "  ✅ ServiceAccount inyectado en sensor deployment" || \
        log_warning "  ⚠️  No se pudo parchear sensor deployment"
    else
      log_warning "  ⚠️  No se encontró deployment del sensor (se creará cuando se sincronice)"
    fi
  else
    log_warning "  ⚠️  Sensor no encontrado (se aplicará cuando ArgoCD lo sincronice)"
  fi
  
  log_success "🎯 Fixes críticos aplicados"
}

verify_gitops_services() {
  log_info "Verificando arquitectura GitOps desplegada..."
  
  # Verificar ArgoCD self-management
  log_info "🔄 ArgoCD Self-Management:"
  local self_app_status
  self_app_status=$(kubectl -n argocd get app argocd-self-config -o jsonpath='{.status.sync.status}/{.status.health.status}' 2>/dev/null || echo "Unknown/Unknown")
  if [[ "$self_app_status" == "Synced/Healthy" ]]; then
    log_success "  argocd-self-config: $self_app_status (siguiendo Best Practices)"
  else
    log_warning "  ⚠️  argocd-self-config: $self_app_status"
  fi
  
  # Verificar GitOps tools desplegadas
  log_info "🛠️  GitOps Tools (con NodePorts definidos en manifests):"
  local tools=(
    "argocd:argocd-server:30080"
    "grafana:grafana:30093" 
    "prometheus:prometheus:30092"
    "kubernetes-dashboard:kubernetes-dashboard:30085"
    "kargo:kargo:30091"
  )
  
  for tool_def in "${tools[@]}"; do
    IFS=':' read -r ns svc expected_port <<< "$tool_def"
    
    if kubectl get svc "$svc" -n "$ns" >/dev/null 2>&1; then
      local svc_type actual_port
      svc_type=$(kubectl get svc "$svc" -n "$ns" -o jsonpath='{.spec.type}' 2>/dev/null || echo "ClusterIP")
      actual_port=$(kubectl get svc "$svc" -n "$ns" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "none")
      
      if [[ "$svc_type" == "NodePort" && "$actual_port" == "$expected_port" ]]; then
        log_success "  $ns/$svc: NodePort $actual_port → http://localhost:$actual_port"
      else
        log_info "  ⏳ $ns/$svc: $svc_type (NodePort será configurado por manifest)"
      fi
    else
      log_info "  ⏳ $ns/$svc: Pendiente de despliegue"
    fi
  done
  
  log_success "🎯 Arquitectura GitOps: Cluster → ArgoCD (bootstrap) → Manifests (declarativo)"
}

create_gitops_namespaces() {
  log_info "Creando namespaces para aplicaciones GitOps..."
  
  local namespaces_created=0
  
  # Escanear manifests/gitops-tools
  if [[ -d "$SCRIPT_DIR/manifests/gitops-tools" ]]; then
    for dir in "$SCRIPT_DIR/manifests/gitops-tools"/*/; do
      if [[ -d "$dir" ]]; then
        local ns_name
        ns_name=$(basename "$dir")
        
        # Saltar sealed-secrets (ya está en kube-system)
        if [[ "$ns_name" == "sealed-secrets" ]]; then
          log_info "   ⏭️  Omitiendo namespace 'sealed-secrets' (ya existe en kube-system)"
          continue
        fi
        
        # Crear namespace si no existe
        if ! kubectl get namespace "$ns_name" >/dev/null 2>&1; then
          kubectl create namespace "$ns_name" >/dev/null 2>&1
          log_info "   ✅ Namespace '$ns_name' creado"
          namespaces_created=$((namespaces_created + 1))
        else
          log_info "   ℹ️  Namespace '$ns_name' ya existe"
        fi
      fi
    done
  fi
  
  # Escanear manifests/custom-apps (aplicaciones personalizadas)
  if [[ -d "$SCRIPT_DIR/manifests/custom-apps" ]]; then
    for dir in "$SCRIPT_DIR/manifests/custom-apps"/*/; do
      if [[ -d "$dir" ]]; then
        local ns_name
        ns_name=$(basename "$dir")
        
        # Crear namespace si no existe
        if ! kubectl get namespace "$ns_name" >/dev/null 2>&1; then
          kubectl create namespace "$ns_name" >/dev/null 2>&1
          log_info "   ✅ Namespace '$ns_name' creado (custom app)"
          namespaces_created=$((namespaces_created + 1))
        else
          log_info "   ℹ️  Namespace '$ns_name' ya existe"
        fi
      fi
    done
  fi
  
  log_success "Namespaces preparados ($namespaces_created creados)"
}




wait_and_sync_applications() {
    log_info "Esperando y sincronizando aplicaciones..."
    
    # Esperar a que se generen las aplicaciones
    log_info "Esperando a que ApplicationSets generen aplicaciones..."
    local attempts=0
    while [ $attempts -lt 30 ]; do
        local app_count
        app_count=$(kubectl get applications -n argocd --no-headers 2>/dev/null | wc -l || echo "0")
        if [ "$app_count" -gt 0 ]; then
            log_success "$app_count aplicaciones generadas"
            break
        fi
        sleep 5
        attempts=$((attempts + 1))
    done
    
  # Obtener contraseña de admin de ArgoCD (no crítico si no existe en modo no-auth)
  local argocd_password=""
  argocd_password=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null || echo "")

  # Intentar login y sync, pero no fallar si auth está deshabilitado
  if [ -n "$argocd_password" ]; then
    kubectl exec -n argocd deployment/argocd-server -- argocd login localhost:8080 --username admin --password "$argocd_password" --insecure >/dev/null 2>&1 || true
  fi
  # Sincronizar aplicaciones de infraestructura igualmente (no requiere login en modo no-auth)
  log_info "Sincronizando aplicaciones de infraestructura..."
  # Asegura que el CRD de Rollouts exista antes de sincronizar workloads que lo usan
  wait_for_condition "kubectl get crd rollouts.argoproj.io >/dev/null 2>&1" 180 5 || true

  local desired_apps=(argo-rollouts sealed-secrets dashboard grafana prometheus kargo)
  if [[ "$ENABLE_CUSTOM_APPS" == "true" ]]; then
    desired_apps+=(demo-api)
  fi

  local apps_to_sync=()
  for app in "${desired_apps[@]}"; do
    if kubectl -n argocd get app "$app" >/dev/null 2>&1; then
      apps_to_sync+=("$app")
    fi
  done

  if ((${#apps_to_sync[@]} > 0)); then
    kubectl exec -n argocd deployment/argocd-server -- argocd app sync "${apps_to_sync[@]}" --insecure --server localhost:8080 >/dev/null 2>&1 || true
  else
    log_warning "No se encontraron aplicaciones de infraestructura para sincronizar."
  fi

  # Esperar a que las aplicaciones alcancen estado saludable
  log_info "Esperando a que las aplicaciones alcancen estado saludable..."
  sleep 30

    # Esperar a que apps clave estén Healthy
  local apps=()
  for app in "${desired_apps[@]}"; do
    if kubectl -n argocd get app "$app" >/dev/null 2>&1; then
      apps+=("$app")
    fi
  done

  if ((${#apps[@]} > 0)); then
    local apps_list
    apps_list=$(printf "%s, " "${apps[@]}" | sed 's/, $//')
    log_info "Esperando a que apps estén Synced+Healthy (${apps_list})..."
  else
    log_warning "No hay aplicaciones ArgoCD que monitorear."
  fi
    local timeout=300
    local interval=5
  local start_ts
  start_ts=$(date +%s)
    while :; do
      local all_ok=true
      for app in "${apps[@]}"; do
        local s h
        s=$(kubectl -n argocd get app "$app" -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "")
        h=$(kubectl -n argocd get app "$app" -o jsonpath='{.status.health.status}' 2>/dev/null || echo "")
        if [[ "$s" != "Synced" || "$h" != "Healthy" ]]; then
          all_ok=false
          break
        fi
      done
      if [[ "$all_ok" == true ]]; then
        break
      fi
  local now
  now=$(date +%s)
      if (( now - start_ts > timeout )); then
        log_warning "Algunas apps siguen no-Healthy tras $timeout s; continuando..."
        break
      fi
      sleep "$interval"
    done

    # Asegurar despliegue del Dashboard listo (por salud y SSL)
    kubectl -n kubernetes-dashboard rollout status deploy/kubernetes-dashboard --timeout=120s >/dev/null 2>&1 || true

    # Mostrar estado final
    log_success "📊 Estado final de aplicaciones:"
    kubectl get applications -n argocd 2>/dev/null | grep -E "NAME|Synced|Healthy" || true
}

ensure_sealed_secrets_ready() {
  log_info "Esperando a sealed-secrets (CRD + controller) desplegado por ArgoCD..."
  # Esperar CRD
  wait_for_condition "kubectl get crd sealedsecrets.bitnami.com >/dev/null 2>&1" 300 5 15 || {
    log_warning "CRD sealedsecrets.bitnami.com no disponible tras la espera"
  }
  # Esperar Deployment del controller Ready
  if ! kubectl -n sealed-secrets rollout status deploy/sealed-secrets-controller --timeout=300s >/dev/null 2>&1; then
    log_warning "sealed-secrets-controller no alcanzó estado Ready a tiempo"
    return 1
  fi
  log_success "sealed-secrets listo"
  return 0
}

ns_created_within() {
  # ns_created_within <namespace> <seconds>
  local ns="$1"; local seconds="$2"
  local ts
  ts=$(kubectl get ns "$ns" -o jsonpath='{.metadata.creationTimestamp}' 2>/dev/null || true)
  if [[ -z "$ts" ]]; then
    return 1
  fi
  local created epoch_now
  created=$(date -d "$ts" +%s 2>/dev/null || echo 0)
  epoch_now=$(date +%s)
  local age=$((epoch_now - created))
  [[ $age -ge 0 && $age -le $seconds ]]
}

hard_refresh_if_recent() {
  # hard_refresh_if_recent <app> <namespace> <seconds>
  local app="$1" ns="$2" seconds="${3:-600}"
  if ns_created_within "$ns" "$seconds"; then
    log_info "Namespace $ns reciente; aplicando hard refresh a app $app"
    kubectl -n argocd patch application "$app" --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' >/dev/null 2>&1 || true
  fi
}

check_nodeport_conflicts() {
  log_step "Chequeando conflictos de NodePort"
  declare -A seen
  local conflicts=0
  # Listar todos los NodePorts actuales
  while IFS=',' read -r ns name nodePort; do
    [[ -z "$nodePort" ]] && continue
    if [[ -n "${seen[$nodePort]:-}" ]]; then
      log_warning "Conflicto: ${seen[$nodePort]} y $ns/$name comparten NodePort $nodePort"
      conflicts=$((conflicts+1))
    else
      seen[$nodePort]="$ns/$name"
    fi
  done < <(kubectl get svc -A -o jsonpath='{range .items[?(@.spec.type=="NodePort")]}{.metadata.namespace},{.metadata.name},{.spec.ports[0].nodePort}{"\n"}{end}' 2>/dev/null || true)

  if [[ $conflicts -gt 0 ]]; then
    log_warning "Detectados $conflicts conflictos de NodePort. Ajusta los manifests para evitar solapamientos."
    return 1
  fi
  log_success "Sin conflictos de NodePort detectados"
}

# =============================================================================
# CONTROL DE FASES Y UTILIDADES CLI
# =============================================================================

declare -ar STAGE_ORDER=(
  prereqs
  system
  docker
  cluster
  gitops
  images
  access
)

declare -Ar STAGE_FUNCS=(
  [prereqs]=validate_prerequisites
  [system]=install_system_base
  [docker]=install_docker_and_tools
  [cluster]=create_cluster
  [images]=build_and_load_images
  [gitops]=setup_gitops
  [access]=show_final_report
)

declare -Ar STAGE_TITLES=(
  [prereqs]="Prerequisitos del entorno"
  [system]="Instalación de herramientas base"
  [docker]="Docker + kubectl + kind"
  [cluster]="Creación de cluster y ArgoCD"
  [gitops]="Configuración completa GitOps"
  [images]="Construcción y publicación de imágenes"
  [access]="Accesos rápidos"
)

print_stage_list() {
  echo ""
  echo "🧩 Fases disponibles:"
  for stage in "${STAGE_ORDER[@]}"; do
    printf "  %-12s %s\n" "$stage" "${STAGE_TITLES[$stage]}"
  done
  echo ""
}

stage_exists() {
  local stage="$1"
  [[ -n "${STAGE_FUNCS[$stage]:-}" ]]
}

run_stage() {
  local stage="$1"
  local func="${STAGE_FUNCS[$stage]}"
 
  local title="${STAGE_TITLES[$stage]}"
  local start_ts
  start_ts=$(date +%s)
  
  # Progress indicator
  local current_stage_idx=0
  local total_stages=${#STAGE_ORDER[@]}
  for i in "${!STAGE_ORDER[@]}"; do
    if [[ "${STAGE_ORDER[$i]}" == "$stage" ]]; then
      current_stage_idx=$((i + 1))
      break
    fi
  done

  log_step "[$current_stage_idx/$total_stages] $title"
  "$func"

  local end_ts
  end_ts=$(date +%s)
  local elapsed=$(( end_ts - start_ts ))
  local end_time=$(date '+%H:%M:%S')
  log_success "[$current_stage_idx/$total_stages] $title completado en ${elapsed}s ($end_time)"
}

print_usage() {
  cat <<'EOF'
Uso: ./install.sh [opciones]

Opciones de instalación:
  --unattended           Ejecuta todas las fases sin pedir confirmación
  --stage <fase>         Ejecuta solo la fase indicada (ver --list-stages)
  --start-from <fase>    Ejecuta desde la fase indicada hasta el final
  --list-stages          Muestra las fases disponibles

Opciones de acceso rápido:
  --open <servicio>      Abre rápidamente la URL de un servicio
                         Servicios: argocd, dashboard, gitea, grafana, prometheus, 
                                   rollouts, kargo

Opciones de snapshot y recuperación:
  --snapshot [nombre]    Crea un snapshot del estado actual del cluster
  --restore <path>       Restaura el cluster desde un snapshot

Opciones de ayuda:
  -h, --help             Muestra esta ayuda y termina

Variables de entorno (ver config.env para más):
  DEBUG_MODE=true        Activa trazas completas de ejecución
  VERBOSE_LOGGING=true   Muestra logs detallados
  SKIP_CLEANUP_ON_ERROR=true  Preserva cluster en caso de error
  ENABLE_CUSTOM_APPS=false    Deshabilita aplicaciones de ejemplo
  PARALLEL_INSTALL=false      Instala herramientas secuencialmente
  RUN_SMOKE_TESTS=false       Omite smoke tests automáticos

Ejemplos:
  # Instalación completa desatendida
  ./install.sh --unattended

  # Ejecutar solo una fase específica
  ./install.sh --stage gitops

  # Abrir dashboard rápidamente
  ./install.sh --open dashboard

  # Continuar desde una fase
  ./install.sh --start-from gitops --unattended

  # Crear snapshot del cluster actual
  ./install.sh --snapshot mi-backup

  # Restaurar desde un snapshot
  ./install.sh --restore ~/.gitops-snapshots/mi-backup

  # Modo debug completo
  DEBUG_MODE=true VERBOSE_LOGGING=true ./install.sh --stage cluster

  # Usar configuración personalizada
  source config.env && ./install.sh --unattended
EOF
}

configure_gitops_remotes() {
  log_info "Configurando remotos GitOps para flujo local → Gitea → ArgoCD..."
  
  # Verificar si ya existen los remotos de Gitea
  if git remote | grep -q "gitea-"; then
    log_info "Remotos de Gitea ya configurados."
  else
    log_info "Configurando remotos de Gitea..."
    
    # Configurar remotos para el flujo GitOps
    git remote add gitea-argo-config "http://gitops:${GITEA_ADMIN_PASSWORD}@localhost:30083/gitops/argo-config.git" 2>/dev/null || true
    git remote add gitea-gitops-tools "http://gitops:${GITEA_ADMIN_PASSWORD}@localhost:30083/gitops/gitops-tools.git" 2>/dev/null || true
    
    log_info "✅ Remotos configurados:"
    log_info "   - gitea-argo-config: Configuración de ArgoCD"
    log_info "   - gitea-gitops-tools: Manifests de GitOps tools"
  fi
  
  # Crear script de sincronización
  cat > "${SCRIPT_DIR}/scripts/sync-to-gitea.sh" << 'EOF'
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
  
  # Crear directorio temporal
  local temp_dir="/tmp/gitops-sync-$$"
  mkdir -p "$temp_dir"
  
  # Clonar repo de Gitea
  git clone "$remote" "$temp_dir" >/dev/null 2>&1
  
  # Copiar archivos actuales
  cp -r "$prefix"/* "$temp_dir/"
  
  # Commit y push
  cd "$temp_dir"
  git add .
  if git commit -m "sync: update from local development" >/dev/null 2>&1; then
    git push >/dev/null 2>&1
    log_success "$prefix sincronizado"
  else
    log_info "$prefix sin cambios"
  fi
  
  # Cleanup
  rm -rf "$temp_dir"
}

main() {
  log_info "🔄 Sincronizando cambios locales con Gitea..."
  
  # Verificar que estemos en el directorio correcto
  if [[ ! -d "argo-config" ]] || [[ ! -d "manifests/gitops-tools" ]]; then
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
  sync_subtree "manifests/gitops-tools" "http://gitops:${gitea_password}@localhost:30083/gitops/gitops-tools.git"
  
  log_success "🎉 Sincronización completada. ArgoCD detectará los cambios automáticamente."
  log_info "💡 Puedes verificar en: http://localhost:30080"
}

main "$@"
EOF
  
  chmod +x "${BASE_DIR}/scripts/sync-to-gitea.sh"
  log_success "Script de sincronización creado: ./scripts/sync-to-gitea.sh"
}

show_final_report() {
  echo ""
  echo "════════════════════════════════════════════════════════════════════════════════"
  echo "                    🎉 INSTALACIÓN COMPLETADA EXITOSAMENTE 🎉"
  echo "════════════════════════════════════════════════════════════════════════════════"
  echo ""
  
  # =============================================================================
  # SECCIÓN 1: ESTADO DE APLICACIONES GITOPS
  # =============================================================================
  echo "┌────────────────────────────────────────────────────────────────────────────┐"
  echo "│ 📊 ESTADO DE APLICACIONES GITOPS                                          │"
  echo "└────────────────────────────────────────────────────────────────────────────┘"
  echo ""
  
  local argocd_pods_ready
  argocd_pods_ready=$(kubectl get pods -n argocd --no-headers 2>/dev/null | awk '{if($2 ~ /\/.*/ && $3=="Running") print $1}' | wc -l || echo "0")
  echo "🔵 ArgoCD Core: $argocd_pods_ready/7 pods Running"
  echo ""
  
  local total_apps=0
  local healthy_apps=0
  local synced_apps=0
  
  echo "🔵 Aplicaciones desplegadas:"
  while read -r app sync health _; do
    total_apps=$((total_apps + 1))
    local status_icon="⏳"
    if [[ "$sync" == "Synced" ]]; then
      synced_apps=$((synced_apps + 1))
    fi
    if [[ "$sync" == "Synced" && "$health" == "Healthy" ]]; then
      status_icon="✅"
      healthy_apps=$((healthy_apps + 1))
    elif [[ "$sync" == "Synced" ]]; then
      status_icon="🟡"
    fi
    printf "   %s %-30s [%s + %s]\n" "$status_icon" "$app" "$sync" "$health"
  done < <(kubectl get applications -n argocd --no-headers 2>/dev/null) || echo "   ⏳ Aplicaciones iniciándose..."
  
  echo ""
  if [[ $total_apps -gt 0 ]]; then
    echo "   📈 Resumen: $healthy_apps/$total_apps Healthy | $synced_apps/$total_apps Synced"
  fi
  echo ""

  # =============================================================================
  # SECCIÓN 2: GITOPS TOOLS - INTERFACES WEB Y CREDENCIALES
  # =============================================================================
  echo "┌────────────────────────────────────────────────────────────────────────────┐"
  echo "│ 🌐 GITOPS TOOLS - INTERFACES WEB Y CREDENCIALES                           │"
  echo "└────────────────────────────────────────────────────────────────────────────┘"
  echo ""
  
  # Obtener credenciales
  local argocd_password
  argocd_password=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null || echo "[obteniendo...]")
  local gitea_pw="${GITEA_ADMIN_PASSWORD:-admin123}"
  local grafana_admin_pw
  if [[ -f "$HOME/.gitops-credentials/grafana-admin.txt" ]]; then
    grafana_admin_pw=$(grep "Password:" "$HOME/.gitops-credentials/grafana-admin.txt" | awk '{print $2}')
  else
    grafana_admin_pw="admin"
  fi
  local kargo_admin_pw
  if [[ -f "$HOME/.gitops-credentials/kargo-admin.txt" ]]; then
    kargo_admin_pw=$(grep "Password:" "$HOME/.gitops-credentials/kargo-admin.txt" | awk '{print $2}')
  else
    kargo_admin_pw="admin123"
  fi

  # Función auxiliar para verificar URLs
  CHECK_URL_LAST_CODE="000"
  check_url() {
    local url="$1"; local name="$2"; local expected_http="${3:-200}"; local quiet="${4:-false}"
    local curl_opts=("-sS" "-o" "/dev/null" "-w" "%{http_code}" "--max-time" "10" "-L")
    case "$url" in https://*) curl_opts+=("-k");; esac
    local code
    code=$(curl "${curl_opts[@]}" "$url" 2>/dev/null || echo "000")
    CHECK_URL_LAST_CODE="$code"

    if echo "$code" | grep -q "^$expected_http\|^30"; then
      if [[ "$quiet" != "true" ]]; then
        echo "   ✅ $name"
      fi
      return 0
    fi
    if [[ "$quiet" != "true" ]]; then
      echo "   ⏳ $name (HTTP $code - iniciándose...)"
    fi
    return 1
  }

  wait_url() {
    local url="$1"; local name="$2"; local expected_http="${3:-200}"; local timeout="${4:-120}"; local interval=6
    local elapsed=0
    local notified=false
    local last_code="000"

    while [[ $elapsed -lt "$timeout" ]]; do
      if check_url "$url" "$name" "$expected_http" true; then
        return 0
      fi
      last_code="$CHECK_URL_LAST_CODE"
      if [[ "$notified" == "false" ]]; then
        notified=true
      fi
      sleep $interval
      elapsed=$((elapsed + interval))
    done
    return 1
  }

  # ============================================================================
  # PARALELIZAR HEALTH CHECKS DE URLS (Conservador y seguro)
  # ============================================================================
  echo "   ℹ️  🔍 Verificando disponibilidad de servicios en paralelo..."
  echo ""
  
  # Archivos temporales para capturar resultados
  local check_dir="/tmp/gitops-health-checks-$$"
  mkdir -p "$check_dir"
  
  # Lanzar todos los health checks en background, guardando resultados
  (wait_url "http://localhost:30080" "ArgoCD" 200 60 && echo "OK" > "$check_dir/argocd" || echo "FAIL" > "$check_dir/argocd") &
  (wait_url "http://localhost:30083" "Gitea" 200 180 && echo "OK" > "$check_dir/gitea" || echo "FAIL" > "$check_dir/gitea") &
  (wait_url "http://localhost:30085" "Kargo" 200 240 && echo "OK" > "$check_dir/kargo" || echo "FAIL" > "$check_dir/kargo") &
  (wait_url "http://localhost:30082" "Grafana" 200 240 && echo "OK" > "$check_dir/grafana" || echo "FAIL" > "$check_dir/grafana") &
  (wait_url "http://localhost:30081" "Prometheus" 200 240 && echo "OK" > "$check_dir/prometheus" || echo "FAIL" > "$check_dir/prometheus") &
  (wait_url "http://localhost:30084" "Argo Rollouts" 200 180 && echo "OK" > "$check_dir/rollouts" || echo "FAIL" > "$check_dir/rollouts") &
  (wait_url "http://localhost:30086" "Kubernetes Dashboard" 200 240 && echo "OK" > "$check_dir/dashboard" || echo "FAIL" > "$check_dir/dashboard") &
  
  # Esperar a que terminen todos los checks
  wait
  
  # Mostrar servicios con formato mejorado
  echo "┌─────────────────────────────────────────────────────────────────────────┐"
  echo "│ ArgoCD - GitOps Continuous Delivery                                     │"
  echo "├─────────────────────────────────────────────────────────────────────────┤"
  echo "│ 🔗 URL:       http://localhost:30080                                    │"
  echo "│ 👤 Usuario:   admin                                                     │"
  echo "│ 🔑 Password:  $argocd_password                                          │"
  if [[ -f "$check_dir/argocd" ]] && [[ "$(cat "$check_dir/argocd")" == "OK" ]]; then
    echo "   ✅ Servicio disponible"
  else
    echo "   ⏳ Todavía iniciándose..."
  fi
  echo "└─────────────────────────────────────────────────────────────────────────┘"
  echo ""
  
  echo "┌─────────────────────────────────────────────────────────────────────────┐"
  echo "│ Gitea - Git Server Local (sin autenticación)                           │"
  echo "├─────────────────────────────────────────────────────────────────────────┤"
  echo "│ 🔗 URL:       http://localhost:30083                                    │"
  echo "│ 👤 Usuario:   gitops (opcional - navegación anónima habilitada)        │"
  echo "│ 🔑 Password:  $gitea_pw                                                 │"
  if [[ -f "$check_dir/gitea" ]] && [[ "$(cat "$check_dir/gitea")" == "OK" ]]; then
    echo "   ✅ Servicio disponible"
  else
    echo "   ⏳ Todavía iniciándose..."
  fi
  echo "└─────────────────────────────────────────────────────────────────────────┘"
  echo ""
  
  echo "┌─────────────────────────────────────────────────────────────────────────┐"
  echo "│ Kargo - Progressive Delivery & Promotions                              │"
  echo "├─────────────────────────────────────────────────────────────────────────┤"
  echo "│ 🔗 URL:       http://localhost:30085                                    │"
  echo "│ 👤 Usuario:   admin                                                     │"
  echo "│ 🔑 Password:  $kargo_admin_pw                                           │"
  echo "│ 📄 Credenciales guardadas en: ~/.gitops-credentials/kargo-admin.txt    │"
  if [[ -f "$check_dir/kargo" ]] && [[ "$(cat "$check_dir/kargo")" == "OK" ]]; then
    echo "   ✅ Servicio disponible"
  else
    echo "   ⏳ Todavía iniciándose..."
  fi
  echo "└─────────────────────────────────────────────────────────────────────────┘"
  echo ""
  
  echo "┌─────────────────────────────────────────────────────────────────────────┐"
  echo "│ Grafana - Monitoring & Dashboards                                      │"
  echo "├─────────────────────────────────────────────────────────────────────────┤"
  echo "│ 🔗 URL:       http://localhost:30082                                    │"
  echo "│ � Acceso directo sin login (anonymous access: Admin)                  │"
  echo "│ 👤 Usuario:   admin (opcional)                                          │"
  echo "│ 🔑 Password:  $grafana_admin_pw (opcional)                              │"
  echo "│ 📄 Credenciales guardadas en: ~/.gitops-credentials/grafana-admin.txt  │"
  if [[ -f "$check_dir/grafana" ]] && [[ "$(cat "$check_dir/grafana")" == "OK" ]]; then
    echo "   ✅ Servicio disponible"
  else
    echo "   ⏳ Todavía iniciándose..."
  fi
  echo "└─────────────────────────────────────────────────────────────────────────┘"
  echo ""
  
  echo "┌─────────────────────────────────────────────────────────────────────────┐"
  echo "│ Prometheus - Metrics Collection                                        │"
  echo "├─────────────────────────────────────────────────────────────────────────┤"
  echo "│ 🔗 URL:       http://localhost:30081                                    │"
  echo "│ 🔓 Sin autenticación                                                    │"
  if [[ -f "$check_dir/prometheus" ]] && [[ "$(cat "$check_dir/prometheus")" == "OK" ]]; then
    echo "   ✅ Servicio disponible"
  else
    echo "   ⏳ Todavía iniciándose..."
  fi
  echo "└─────────────────────────────────────────────────────────────────────────┘"
  echo ""
  
  echo "┌─────────────────────────────────────────────────────────────────────────┐"
  echo "│ Argo Rollouts Dashboard - Progressive Delivery                         │"
  echo "├─────────────────────────────────────────────────────────────────────────┤"
  echo "│ 🔗 URL:       http://localhost:30084                                    │"
  echo "│ 🔓 Sin autenticación                                                    │"
  if [[ -f "$check_dir/rollouts" ]] && [[ "$(cat "$check_dir/rollouts")" == "OK" ]]; then
    echo "   ✅ Servicio disponible"
  else
    echo "   ⏳ Todavía iniciándose..."
  fi
  echo "└─────────────────────────────────────────────────────────────────────────┘"
  echo ""
  
  echo "┌─────────────────────────────────────────────────────────────────────────┐"
  echo "│ Kubernetes Dashboard - Cluster Overview                                │"
  echo "├─────────────────────────────────────────────────────────────────────────┤"
  echo "│ 🔗 URL:       http://localhost:30086                                    │"
  echo "│ 🔓 Acceso directo sin autenticación (--enable-skip-login)              │"
  if [[ -f "$check_dir/dashboard" ]] && [[ "$(cat "$check_dir/dashboard")" == "OK" ]]; then
    echo "   ✅ Servicio disponible"
  else
    echo "   ⏳ Todavía iniciándose..."
  fi
  echo "└─────────────────────────────────────────────────────────────────────────┘"
  echo ""
  
  # Limpiar archivos temporales
  rm -rf "$check_dir"
  echo "└─────────────────────────────────────────────────────────────────────────┘"
  echo ""

  if [[ "$ENABLE_CUSTOM_APPS" == "true" ]]; then
    echo "┌─────────────────────────────────────────────────────────────────────────┐"
    echo "│ Demo API - Aplicación de Ejemplo                                       │"
    echo "├─────────────────────────────────────────────────────────────────────────┤"
    echo "│ 🔗 URL:       http://localhost:30070                                    │"
    echo "│ 🔓 Sin autenticación                                                    │"
    wait_url "http://localhost:30070" "Demo API" 200 240 || echo "   ⏳ Todavía iniciándose..."
    echo "└─────────────────────────────────────────────────────────────────────────┘"
    echo ""
  fi

  # =============================================================================
  # SECCIÓN 3: ESTRUCTURA DE REPOSITORIOS
  # =============================================================================
  echo "┌────────────────────────────────────────────────────────────────────────────┐"
  echo "│ 📂 ESTRUCTURA DE REPOSITORIOS GITOPS                                      │"
  echo "└────────────────────────────────────────────────────────────────────────────┘"
  echo ""
  echo "Los siguientes repositorios Git locales están sincronizados con Gitea:"
  echo ""
  echo "  📁 ~/gitops-repos/gitops-tools/"
  echo "     ├─ Repositorio Gitea: gitops/gitops-tools"
  echo "     └─ GitOps tools (Kargo, Grafana, Prometheus, Argo Rollouts, etc.)"
  echo ""
  echo "  📁 ~/gitops-repos/gitops-custom-apps/"
  echo "     ├─ Repositorio Gitea: gitops/custom-apps"
  echo "     └─ Manifests de aplicaciones custom (Demo API, etc.)"
  echo ""
  echo "  📁 ~/gitops-repos/argo-config/"
  echo "     ├─ Repositorio Gitea: gitops/argo-config"
  echo "     └─ Configuración de ArgoCD (Applications, Projects, ConfigMaps, Repositories)"
  echo ""
  if [[ "$ENABLE_CUSTOM_APPS" == "true" ]]; then
    echo "  📁 ~/gitops-repos/sourcecode-apps/demo-api/"
    echo "     ├─ Repositorio Gitea: gitops/demo-api"
    echo "     └─ Código fuente de la aplicación demo (Node.js + Express)"
    echo ""
  fi
  
  # =============================================================================
  # SECCIÓN 4: AÑADIR NUEVAS GITOPS TOOLS
  # =============================================================================
  echo "┌────────────────────────────────────────────────────────────────────────────┐"
  echo "│ ➕ ¿CÓMO AÑADIR UNA NUEVA GITOPS TOOL?                                     │"
  echo "└────────────────────────────────────────────────────────────────────────────┘"
  echo ""
  echo "Para añadir una nueva herramienta GitOps al cluster:"
  echo ""
  echo "1️⃣  Navega al repositorio gitops-tools local:"
  echo "    cd ~/gitops-repos/gitops-tools"
  echo ""
  echo "2️⃣  Crea una nueva carpeta para tu herramienta:"
  echo "    mkdir -p my-new-tool"
  echo "    cd my-new-tool"
  echo ""
  echo "3️⃣  Añade los manifests de Kubernetes (deployment.yaml, service.yaml, etc.):"
  echo "    # Ejemplo: deployment.yaml"
  echo "    apiVersion: apps/v1"
  echo "    kind: Deployment"
  echo "    metadata:"
  echo "      name: my-new-tool"
  echo "      namespace: my-new-tool"
  echo "    spec:"
  echo "      replicas: 1"
  echo "      selector:"
  echo "        matchLabels:"
  echo "          app: my-new-tool"
  echo "      template:"
  echo "        metadata:"
  echo "          labels:"
  echo "            app: my-new-tool"
  echo "        spec:"
  echo "          containers:"
  echo "          - name: my-new-tool"
  echo "            image: my-registry/my-new-tool:latest"
  echo "            ports:"
  echo "            - containerPort: 8080"
  echo ""
  echo "4️⃣  Haz commit de los cambios:"
  echo "    git add my-new-tool/"
  echo "    git commit -m \"feat: añadir my-new-tool\""
  echo ""
  echo "5️⃣  Haz push al remoto Gitea (ArgoCD detectará los cambios automáticamente):"
  echo "    git push gitea-gitops-tools main"
  echo ""
  echo "6️⃣  (Opcional) Haz backup a GitHub:"
  echo "    git push origin main"
  echo ""
  echo "7️⃣  ArgoCD detectará el cambio y creará automáticamente una Application para"
  echo "    'my-new-tool' gracias al ApplicationSet configurado. Puedes verificar en:"
  echo "    http://localhost:30080"
  echo ""
  echo "💡 NOTA: El namespace 'my-new-tool' se creará automáticamente en la próxima"
  echo "   ejecución de ./install.sh (gracias a la función de pre-creación dinámica)."
  echo "   O puedes crearlo manualmente con: kubectl create namespace my-new-tool"
  echo ""
  
  # =============================================================================
  # SECCIÓN 5: FLUJO DE TRABAJO RECOMENDADO
  # =============================================================================
  echo "┌────────────────────────────────────────────────────────────────────────────┐"
  echo "│ 🔄 FLUJO DE TRABAJO GITOPS RECOMENDADO                                    │"
  echo "└────────────────────────────────────────────────────────────────────────────┘"
  echo ""
  echo "Opción A - Desarrollo local (recomendado para POCs):"
  echo "  1. Edita manifests en ~/gitops-repos/argo-config/ o gitops-tools/"
  echo "  2. git commit -m \"feat: nueva funcionalidad\""
  echo "  3. git push gitea-<repo-name> main  → ArgoCD detecta cambios automáticamente"
  echo "  4. git push origin main  → (opcional) backup a GitHub"
  echo ""
  echo "Opción B - Flujo completo con dotfiles:"
  echo "  1. Edita manifests en este repositorio dotfiles (argo-config/, manifests/)"
  echo "  2. git commit -m \"feat: nueva funcionalidad\""
  echo "  3. git push origin main  → Backup a GitHub"
  echo "  4. ./scripts/sync-to-gitea.sh  → Sincroniza cambios a Gitea"
  echo "  5. ArgoCD detecta cambios y actualiza cluster automáticamente"
  echo ""
  
  # =============================================================================
  # SECCIÓN 6: COMANDOS ÚTILES
  # =============================================================================
  echo "┌────────────────────────────────────────────────────────────────────────────┐"
  echo "│ 🛠️  COMANDOS ÚTILES                                                        │"
  echo "└────────────────────────────────────────────────────────────────────────────┘"
  echo ""
  echo "Ver estado de aplicaciones ArgoCD:"
  echo "  kubectl get applications -n argocd"
  echo ""
  echo "Ver logs de una aplicación:"
  echo "  kubectl logs -n <namespace> -l app=<app-name> --tail=100 -f"
  echo ""
  echo "Forzar sincronización de ArgoCD:"
  echo "  kubectl patch app <app-name> -n argocd -p '{\"operation\":{\"sync\":{}}}' --type merge"
  echo ""
  echo "Ver todos los pods del cluster:"
  echo "  kubectl get pods -A"
  echo ""
  echo "Acceder a un pod:"
  echo "  kubectl exec -it -n <namespace> <pod-name> -- /bin/bash"
  echo ""
  echo "Ver secretos cifrados (SealedSecrets):"
  echo "  kubectl get sealedsecrets -A"
  echo ""
  echo "Generar un nuevo SealedSecret:"
  echo "  echo -n 'mi-password' | kubectl create secret generic my-secret --dry-run=client --from-file=password=/dev/stdin -o yaml | \\"
  echo "    kubeseal -o yaml > sealed-secret.yaml"
  echo ""
  
  # =============================================================================
  # SECCIÓN 7: DOCUMENTACIÓN Y RECURSOS
  # =============================================================================
  echo "┌────────────────────────────────────────────────────────────────────────────┐"
  echo "│ 📚 DOCUMENTACIÓN Y RECURSOS                                                │"
  echo "└────────────────────────────────────────────────────────────────────────────┘"
  echo ""
  echo "  🔹 ArgoCD:          https://argo-cd.readthedocs.io/"
  echo "  🔹 Kargo:           https://docs.kargo.io/"
  echo "  🔹 Sealed Secrets:  https://sealed-secrets.netlify.app/"
  echo "  🔹 Argo Rollouts:   https://argo-rollouts.readthedocs.io/"
  echo "  🔹 Argo Workflows:  https://argo-workflows.readthedocs.io/"
  echo "  🔹 Prometheus:      https://prometheus.io/docs/"
  echo "  🔹 Grafana:         https://grafana.com/docs/"
  echo "  🔹 Kind:            https://kind.sigs.k8s.io/"
  echo ""
  
  echo "════════════════════════════════════════════════════════════════════════════════"
  echo "                  ✨ ¡GitOps Master Setup 100% Funcional! ✨"
  echo "════════════════════════════════════════════════════════════════════════════════"
  echo ""
  log_success "Instalación completada. ¡Disfruta de tu entorno GitOps! 🚀"
  echo ""
}

validate_yaml_and_apps() {
  log_step "Validación final: lint YAML y verificación de contenidos"

  # Lint YAML básico si yamllint está disponible
  if command -v yamllint >/dev/null 2>&1; then
    yamllint -d '{extends: default, rules: {line-length: disable, document-start: disable}}' "${DOTFILES_DIR}/manifests" >/dev/null 2>&1 || {
      log_warning "yamllint detectó advertencias (consulta manualmente si es necesario)"
    }
  else
    log_info "yamllint no instalado; omitiendo lint"
  fi

  # Verificar que cada carpeta de infraestructura tenga recursos aplicables
  local base="${DOTFILES_DIR}/manifests/gitops-tools"
  local missing=()
  for d in $(ls -1 "$base"); do
    local dir="$base/$d"
    [[ -d "$dir" ]] || continue
    # Ignorar carpetas que solo tienen CRDs (han sido ya separadas)
    local has_resource=false
    if grep -R "^kind:\s*\(Deployment\|StatefulSet\|DaemonSet\|Service\)" -n "$dir" >/dev/null 2>&1; then
      has_resource=true
    fi
    if [[ "$has_resource" != true ]]; then
      missing+=("$d")
    fi
  done

  if ((${#missing[@]} > 0)); then
    log_warning "Directorios sin workloads/Service aparentes: ${missing[*]}"
  else
    log_success "Todos los componentes de infraestructura tienen recursos aplicables"
  fi
}

# =============================================================================
# FUNCIÓN PRINCIPAL
# =============================================================================

main() {
  local unattended=false
  local single_stage=""
  local start_from=""
  local list_stages=false
  local open_service_name=""
  local snapshot_cmd=""
  local snapshot_arg=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --unattended)
        unattended=true
        ;;
      --stage)
        shift || { log_error "Falta el nombre de la fase tras --stage"; exit 1; }
        single_stage="$1"
        ;;
      --start-from)
        shift || { log_error "Falta el nombre de la fase tras --start-from"; exit 1; }
        start_from="$1"
        ;;
      --open)
        shift || { log_error "Falta el nombre del servicio tras --open"; exit 1; }
        open_service_name="$1"
        ;;
      --snapshot)
        snapshot_cmd="create"
        shift
        if [[ $# -gt 0 && ! "$1" =~ ^-- ]]; then
          snapshot_arg="$1"
        fi
        ;;
      --restore)
        snapshot_cmd="restore"
        shift || { log_error "Falta la ruta del snapshot tras --restore"; exit 1; }
        snapshot_arg="$1"
        ;;
      --list-stages)
        list_stages=true
        ;;
      -h|--help)
        print_usage
        print_stage_list
        exit 0
        ;;
      *)
        log_error "Opción no reconocida: $1"
        print_usage
        exit 1
        ;;
    esac
    shift
  done

  # Manejar comandos de snapshot
  if [[ -n "$snapshot_cmd" ]]; then
    case "$snapshot_cmd" in
      create)
        if [[ -n "$snapshot_arg" ]]; then
          create_snapshot "$snapshot_arg"
        else
          create_snapshot
        fi
        exit $?
        ;;
      restore)
        restore_snapshot "$snapshot_arg"
        exit $?
        ;;
    esac
  fi

  if [[ -n "$open_service_name" ]]; then
    if [[ -n "$single_stage" || -n "$start_from" || "$list_stages" == true ]]; then
      log_error "La opción --open no se puede combinar con ejecución de fases"
      exit 1
    fi
    open_service "$open_service_name"
    exit $?
  fi

  if [[ "$list_stages" == true ]]; then
    print_stage_list
    if [[ -z "$single_stage" && -z "$start_from" ]]; then
      exit 0
    fi
  fi

  local stages_to_run=()
  if [[ -n "$single_stage" ]]; then
    if ! stage_exists "$single_stage"; then
      log_error "La fase '$single_stage' no existe"
      print_stage_list
      exit 1
    fi
    stages_to_run=("$single_stage")
  elif [[ -n "$start_from" ]]; then
    if ! stage_exists "$start_from"; then
      log_error "La fase '$start_from' no existe"
      print_stage_list
      exit 1
    fi
    local found=false
    for stage in "${STAGE_ORDER[@]}"; do
      if [[ "$stage" == "$start_from" ]]; then
        found=true
      fi
      if [[ "$found" == true ]]; then
        stages_to_run+=("$stage")
      fi
    done
  else
    stages_to_run=("${STAGE_ORDER[@]}")
  fi

  local total_stages=${#stages_to_run[@]}

  echo ""
  echo "════════════════════════════════════════════════════════════"
  echo "🚀 GitOps Master Setup"
  echo "💻 Entorno Local de Desarrollo GitOps"
  echo "════════════════════════════════════════════════════════════"
  echo ""
  echo "════════════════════════════════════════════════════════════"
  echo "  🧩 Fases seleccionadas ($total_stages):"
  local idx=1
  for stage in "${stages_to_run[@]}"; do
    printf "  %d/%d %-10s %s\n" "$idx" "$total_stages" "$stage" "${STAGE_TITLES[$stage]}"
    ((idx++))
  done
  echo "════════════════════════════════════════════════════════════"
  echo ""

  if [[ "$unattended" != true ]]; then
    echo "────────────────────────────────────────────────────────────"
    echo "  ❓ ¿Continuar con la ejecución? (y/N):"
    echo "────────────────────────────────────────────────────────────"
    read -r response
    if [[ "$response" != "y" && "$response" != "Y" ]]; then
      echo "   ❌ Instalación cancelada por el usuario."
      exit 0
    fi
    echo "   ✅ Iniciando instalación..."
  else
    echo "   🤖 MODO DESATENDIDO ACTIVADO - Ejecutando fases seleccionadas..."
  fi

  # ===== VERIFICAR Y ACTUALIZAR VERSIONES =====
  # Consultar últimas versiones desde GitHub antes de empezar
  echo ""
  check_and_update_versions
  echo ""

  local report_needed=false
  for stage in "${stages_to_run[@]}"; do
    run_stage "$stage"
    case "$stage" in
      gitops|access)
        report_needed=true
        ;;
    esac
  done

  if [[ "$report_needed" == true ]]; then
    # Ejecutar smoke tests si está habilitado
    if [[ "${RUN_SMOKE_TESTS:-true}" == "true" ]]; then
      echo ""
      run_smoke_tests || log_warning "Algunos smoke tests fallaron, pero la instalación continuó"
      echo ""
    fi
    
    show_final_report
  else
    echo ""
    echo "   🎯 Ejecución finalizada exitosamente"
    
    # Determinar siguiente stage lógico
    local last_stage="${stages_to_run[-1]}"
    local next_stage=""
    local next_desc=""
    
    case "$last_stage" in
      "prereqs") next_stage="system"; next_desc="herramientas base" ;;
      "system") next_stage="docker"; next_desc="Docker + kubectl + kind" ;;
      "docker") next_stage="cluster"; next_desc="cluster Kubernetes" ;;
      "cluster") next_stage="gitops"; next_desc="GitOps completo" ;;
      "gitops") next_stage="images"; next_desc="construcción y push de imágenes" ;;
      *) next_stage="images"; next_desc="construcción y push de imágenes" ;;
    esac
    
    if [[ -n "$next_stage" ]]; then
      echo "   ➡️  Siguiente: ./install.sh --stage $next_stage ($next_desc)"
      echo "   🚀 O completo: ./install.sh --start-from $next_stage --unattended"
    else
      echo "   🎉 ¡Instalación completa! Usa ./install.sh --stage access para accesos rápidos"
    fi
  fi
}

# Ejecutar si es llamado directamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
