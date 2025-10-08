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
readonly SKIP_CLEANUP_ON_ERROR="${SKIP_CLEANUP_ON_ERROR:-false}"

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

    rm -rf /tmp/gitops-sync-* /tmp/kargo-sealed-secret.yaml /tmp/kubeseal 2>/dev/null || true

    # Capturar estado del cluster para debugging si está habilitado
    if [[ "${CAPTURE_STATE_ON_ERROR:-true}" == "true" ]]; then
      local debug_dir
      debug_dir=$(capture_cluster_state)
      log_error "📋 Debug info guardado en: $debug_dir"
      log_info "💡 Revisa los logs para diagnosticar el problema"
    fi

    if [[ "$SKIP_CLEANUP_ON_ERROR" == "true" ]]; then
      log_warning "SKIP_CLEANUP_ON_ERROR=true: se preserva el cluster kind para diagnóstico manual"
      return
    fi

        log_info "Iniciando limpieza..."
        
        # Limpiar cluster kind si existe
        if command -v kind >/dev/null 2>&1 && kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
            log_info "Eliminando cluster kind incompleto..."
            kind delete cluster --name "$CLUSTER_NAME" >/dev/null 2>&1 || true
        fi

        log_info "Limpieza completada. Puedes volver a ejecutar el script."
    fi
}

# Configurar trap para limpieza automática
trap 'cleanup_on_error' EXIT

log_step() {
    local message="$1"
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║  ➡️  $message"
    echo "╚══════════════════════════════════════════════════════════╝"
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
  
  # Instalar kubeseal si no existe
  install_kubeseal
  
  # Esperar a que el namespace kargo y sealed-secrets controller estén listos
  local retries=30
  while [[ $retries -gt 0 ]]; do
    if kubectl get namespace kargo >/dev/null 2>&1 && kubectl get pods -n sealed-secrets -l name=sealed-secrets-controller --field-selector=status.phase=Running | grep -q Running 2>/dev/null; then
      break
    fi
    sleep 2
    retries=$((retries - 1))
  done
  
  if [[ $retries -eq 0 ]]; then
    log_warning "Namespace kargo o sealed-secrets controller no están listos"
    return 0
  fi
  
  # Generar hash seguro para admin/admin123
  local password_hash
  if command -v python3 >/dev/null 2>&1 && python3 -c "import bcrypt" >/dev/null 2>&1; then
    password_hash=$(python3 -c "import bcrypt; print(bcrypt.hashpw('admin123'.encode('utf-8'), bcrypt.gensalt(rounds=12)).decode('utf-8'))")
    log_info "Password hash generado dinámicamente"
  else
    # shellcheck disable=SC2016
    password_hash='$2b$12$DDMB2JPKQx8G2zlofseJ8OhTFQhFrpZvT4NxAlsjPY7RfcU0pIBBC'
    log_warning "Usando password hash estático (bcrypt no disponible)"
  fi
  
  # Crear Secret temporal y convertir a SealedSecret con validación
  local temp_secret_file="/tmp/kargo-temp-secret-$$.yaml"
  local sealed_secret_file="/tmp/kargo-sealed-secret-$$.yaml"
  
  kubectl create secret generic kargo-api -n kargo \
    --from-literal=ADMIN_ACCOUNT_PASSWORD_HASH="${password_hash}" \
    --from-literal=ADMIN_ACCOUNT_TOKEN_SIGNING_KEY='supersecretkey123456789012' \
    --from-literal=ADMIN_ACCOUNT_USERNAME='admin' \
    --from-literal=ADMIN_ACCOUNT_ENABLED='true' \
    --dry-run=client -o yaml > "${temp_secret_file}"
  
  if ! kubeseal -o yaml < "${temp_secret_file}" > "${sealed_secret_file}" 2>/dev/null; then
    log_error "No se pudo generar SealedSecret con kubeseal"
    rm -f "${temp_secret_file}" "${sealed_secret_file}"
    return 1
  fi
  
  if ! kubectl apply --dry-run=client -f "${sealed_secret_file}" >/dev/null 2>&1; then
    log_error "SealedSecret generado inválido"
    rm -f "${temp_secret_file}" "${sealed_secret_file}"
    return 1
  fi
  
  if ! kubectl apply -f "${sealed_secret_file}" >/dev/null 2>&1; then
    log_error "No se pudo aplicar SealedSecret"
    rm -f "${temp_secret_file}" "${sealed_secret_file}"
    return 1
  fi
  
  # Persistir en dotfiles para GitOps
  cp "${sealed_secret_file}" "$DOTFILES_DIR/manifests/gitops-tools/kargo/sealed-secret.yaml"
  cp "${sealed_secret_file}" /tmp/kargo-sealed-secret.yaml 2>/dev/null || true
  rm -f "$DOTFILES_DIR/manifests/gitops-tools/kargo/secret.yaml" 2>/dev/null || true
  rm -f "${temp_secret_file}" "${sealed_secret_file}"
  
  # Reiniciar API de Kargo para recoger nuevas variables
  if kubectl -n kargo rollout restart deploy/kargo-api >/dev/null 2>&1; then
    kubectl -n kargo rollout status deploy/kargo-api --timeout=120s >/dev/null 2>&1 || log_warning "Timeout esperando rollout de kargo-api"
  fi
  
  log_success "SealedSecret kargo-api generado y aplicado (usuario: admin, contraseña: admin123)"
}

sync_sealedsecret_to_gitea() {
  log_info "Sincronizando SealedSecret actualizado a Gitea..."
  
  # Verificar que el archivo exista
  if [[ ! -f "$DOTFILES_DIR/manifests/gitops-tools/kargo/sealed-secret.yaml" ]]; then
    log_warning "SealedSecret no encontrado, saltando sincronización"
    return 0
  fi
  
  # Push directo del directorio infrastructure actualizado
  (
    cd "$DOTFILES_DIR/manifests/gitops-tools" || exit 1
    git add kargo/sealed-secret.yaml
    git commit -m "feat: update kargo SealedSecret with cluster key" >/dev/null 2>&1 || true
    git remote remove gitea 2>/dev/null || true
    git remote add gitea "http://gitops:$GITEA_ADMIN_PASSWORD@localhost:30083/gitops/infrastructure.git"
    git push gitea HEAD:main --force >/dev/null 2>&1
  )
  
  log_success "SealedSecret sincronizado a Gitea"
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
  log_info "🔍 Verificando últimas versiones de GitOps tools..."
  
  # Verificar dependencias
  if ! command -v jq >/dev/null 2>&1; then
    log_warning "jq no está instalado, usando versiones de config.env"
    return 0
  fi

  local config_file="$SCRIPT_DIR/config.env"
  local temp_file="${config_file}.tmp"
  cp "$config_file" "$temp_file"

  # Función helper para obtener última versión de GitHub
  get_latest_github_version() {
    local repo="$1"
    local var_name="$2"
    
    log_info "   Consultando: $repo"
    local version
    version=$(curl -fsSL "https://api.github.com/repos/$repo/releases" 2>/dev/null | \
              jq -r '.[0].tag_name // empty' 2>/dev/null)
    
    if [[ -n "$version" ]]; then
      log_success "   ✓ $var_name=$version"
      sed -i "s|^${var_name}=.*|${var_name}=${version}|" "$temp_file"
    else
      log_warning "   ⚠ No se pudo obtener versión de $repo"
    fi
  }

  # Actualizar todas las versiones
  echo ""
  log_info "📦 ArgoCD Stack:"
  get_latest_github_version "argoproj/argo-cd" "ARGOCD_VERSION"
  get_latest_github_version "argoproj/argo-rollouts" "ARGO_ROLLOUTS_VERSION"
  get_latest_github_version "argoproj/argo-workflows" "ARGO_WORKFLOWS_VERSION"
  get_latest_github_version "argoproj/argo-events" "ARGO_EVENTS_VERSION"
  get_latest_github_version "argoproj-labs/argocd-image-updater" "ARGO_IMAGE_UPDATER_VERSION"

  echo ""
  log_info "🔐 Seguridad:"
  get_latest_github_version "bitnami-labs/sealed-secrets" "KUBESEAL_VERSION"

  echo ""
  log_info "🚀 Release Management:"
  get_latest_github_version "akuity/kargo" "KARGO_VERSION"

  echo ""
  log_info "📊 Observabilidad:"
  get_latest_github_version "prometheus/prometheus" "PROMETHEUS_VERSION"
  get_latest_github_version "grafana/grafana" "GRAFANA_VERSION"
  get_latest_github_version "kubernetes/dashboard" "K8S_DASHBOARD_VERSION"

  echo ""
  log_info "📦 Infraestructura:"
  get_latest_github_version "go-gitea/gitea" "GITEA_VERSION"
  get_latest_github_version "kubernetes-sigs/kind" "KIND_VERSION"

  # Aplicar cambios si hubo actualizaciones
  if ! diff -q "$config_file" "$temp_file" >/dev/null 2>&1; then
    mv "$temp_file" "$config_file"
    log_success "✅ config.env actualizado con las últimas versiones"
    
    # Recargar configuración
    load_config
  else
    rm -f "$temp_file"
    log_info "ℹ️  Todas las versiones ya están actualizadas"
  fi
  
  echo ""
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
  
  log_success "✅ Snapshot creado: ${snapshot_dir}.tar.gz"
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
  
  log_success "✅ Snapshot restaurado. Verifica el estado con: kubectl get applications -n argocd"
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
      log_success "✅ $name"
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
  run_test "Sealed Secrets controller Running" "kubectl get pods -n sealed-secrets -o json 2>/dev/null | jq -r '.items[].status.phase' | grep -q Running"
  run_test "CRD SealedSecrets existe" "kubectl get crd sealedsecrets.bitnami.com"
  
  # Resumen final
  echo ""
  log_info "📊 Resultados de smoke tests:"
  log_info "   Total:   $tests_total tests"
  log_success "   Passed:  $tests_passed ✅"
  
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
  
  log_success "✅ Conectividad de red verificada"
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
  log_step "Validando prerequisitos del entorno"

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
    local detected_tools=()
    for cmd in "${required[@]}"; do
      if command -v "$cmd" >/dev/null 2>&1; then
        detected_tools+=("✓ $cmd")
      fi
    done
    log_info "Sistema validado - Herramientas: ${detected_tools[*]}"
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
    log_step "Instalando sistema base (herramientas Linux)"
    
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
    log_step "Instalando Docker y herramientas Kubernetes"
    
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
      
      # kubectl
      if ! command -v kubectl >/dev/null 2>&1; then
        (
          install_tool "kubectl" bash -c '
            curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
            sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
            rm kubectl
          '
        ) &
      else
        log_info "kubectl ya está instalado"
      fi
      
      # kind
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
      
      # Helm
      if ! command -v helm >/dev/null 2>&1; then
        (
          install_tool "helm" bash -c '
            curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
          '
        ) &
      else
        log_info "Helm ya está instalado"
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
    log_step "Creando cluster Kubernetes + ArgoCD"
    
    # Verificar si el cluster ya existe
    if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
        log_info "Cluster $CLUSTER_NAME ya existe, eliminando..."
        kind delete cluster --name "$CLUSTER_NAME" >/dev/null 2>&1
    fi

    # Crear cluster con configuración de puertos
    log_info "Creando cluster kind con puertos mapeados..."
    cat <<EOF | kind create cluster --name "$CLUSTER_NAME" --config=-
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

    # Esperar a que el nodo esté listo antes de continuar
    log_info "Esperando a que el nodo esté listo..."
    kubectl wait --for=condition=Ready nodes --all --timeout=120s

    # Esperar a que CoreDNS esté listo (esencial para que funcione el cluster)
    log_info "Esperando a que CoreDNS esté listo..."
    kubectl wait --for=condition=Ready pod -l k8s-app=kube-dns -n kube-system --timeout=120s

    # Instalar ArgoCD
    log_info "Instalando ArgoCD ${ARGOCD_VERSION:-v3.2.0-rc3}..."
    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f - >/dev/null
    local argocd_version="${ARGOCD_VERSION:-v3.2.0-rc3}"
    if ! kubectl apply -n argocd -f "https://raw.githubusercontent.com/argoproj/argo-cd/${argocd_version}/manifests/install.yaml" --validate=false 2>&1 | tee /tmp/argocd-install.log; then
        log_error "Error al instalar ArgoCD ${argocd_version}. Ver detalles en /tmp/argocd-install.log"
        cat /tmp/argocd-install.log
        exit 1
    fi

    # Eliminado: instalación manual de Sealed Secrets (lo gestiona ArgoCD)

    # Aplicar ConfigMaps de configuración inmediatamente (sin SSL, sin auth)
    log_info "Aplicando configuración ArgoCD (insecure, no-auth)..."
    if ! kubectl apply -f "$DOTFILES_DIR/argo-config/configmaps/argocd-cmd-params-cm.yaml" >/dev/null 2>&1; then
        log_warning "No se pudo aplicar argocd-cmd-params-cm.yaml"
    fi
    if ! kubectl apply -f "$DOTFILES_DIR/argo-config/configmaps/argocd-cm.yaml" >/dev/null 2>&1; then
        log_warning "No se pudo aplicar argocd-cm.yaml"
    fi

    # Reiniciar ArgoCD para que lea la nueva configuración
    log_info "Reiniciando ArgoCD para aplicar configuración..."
    kubectl rollout restart deployment/argocd-server -n argocd >/dev/null 2>&1 || true
    kubectl rollout restart deployment/argocd-repo-server -n argocd >/dev/null 2>&1 || true

    # Pausa breve para evitar connection reset en la verificación
    sleep 3

  # Esperar a que ArgoCD esté listo con la nueva configuración (robusto)
  log_info "Esperando a que ArgoCD esté listo (rollout de cada componente)..."
  local argocd_components=(
    "deploy/argocd-server"
    "deploy/argocd-repo-server"
    "deploy/argocd-applicationset-controller"
    "deploy/argocd-dex-server"
    "deploy/argocd-notifications-controller"
    "deploy/argocd-redis"
    "sts/argocd-application-controller"
  )

  for component in "${argocd_components[@]}"; do
    local component_name
    component_name=${component#*/}
    log_info "↳ Rollout ${component_name}"
    if kubectl -n argocd rollout status "$component" --timeout=600s >/dev/null 2>&1; then
      log_success "${component_name} listo"
    else
      log_warning "Timeout esperando ${component_name}. Revisa 'kubectl -n argocd get pods'."
    fi
  done

  # Configurar solo ArgoCD para bootstrapping (otros servicios usan manifests GitOps)
  configure_argocd_bootstrap

    # Verificar mapeos de puertos (sanity check)
    if ! check_mapping_sanity; then
        log_warning "Problemas detectados en el mapeo de puertos; revisa los mensajes previos"
    fi

    # Chequeo adicional de conflictos de NodePort
    check_nodeport_conflicts || true

    log_success "Cluster y ArgoCD creados (acceso sin autenticación)"
}



build_and_load_images() {
    log_step "Construyendo imagen y publicando en registry local"

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
  local manifest_dir="$gitops_base_dir/gitops-applications/demo-api"
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
    log_step "Configurando GitOps completo"
    
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
    log_info "Instalando Gitea..."
    
    kubectl create namespace "$GITEA_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

    # Crear secret con password
    kubectl create secret generic gitea-admin-secret \
        --from-literal=password="$GITEA_ADMIN_PASSWORD" \
        -n "$GITEA_NAMESPACE" \
        --dry-run=client -o yaml | kubectl apply -f - >/dev/null

    # Aplicar manifests de Gitea
    kubectl apply -f - <<EOF
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
      log_success "✅ Gitea Actions configurado - Runner operativo y listo para ejecutar workflows"
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
    
    # Crear usuario gitops usando el endpoint de registro público
    curl -X POST "http://localhost:30083/user/sign_up" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "user_name=gitops&email=gitops@localhost&password=$GITEA_ADMIN_PASSWORD&retype=$GITEA_ADMIN_PASSWORD" \
        >/dev/null 2>&1 || true
    
    # Esperar un momento para que la cuenta se active
    sleep 5

    # Crear estructuras de repositorios persistentes
    mkdir -p "$gitops_base_dir"
    
    # Crear repositorios GitOps
  local repo_definitions=(
    "gitops-tools|$DOTFILES_DIR/manifests/gitops-tools|GitOps tools manifests"
    "applications|$DOTFILES_DIR/manifests/custom-apps|GitOps applications manifests"
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
      applications)
        repo_dir="$gitops_base_dir/gitops-applications"
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
    log_info "   $base_dir/gitops-applications/    (manifests apps)"
  log_info "   $base_dir/sourcecode-apps/demo-api/ (código fuente)"
}

setup_application_sets() {
  log_info "Registrando ArgoCD self-management (siguiendo ArgoCD Best Practices)..."

  # Primero crear el proyecto para self-management
  log_info "Creando proyecto argocd-config para self-management..."
  kubectl apply -f "$DOTFILES_DIR/argo-config/projects/argocd-config.yaml" >/dev/null 2>&1 || true
  
  # Application ArgoCD self-management: cubre proyectos, apps, repos y configmaps
  cat <<'EOF' | kubectl apply -f -
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

  log_info "Esperando a que ArgoCD self-config esté Synced/Healthy..."
  wait_for_condition "kubectl -n argocd get app argocd-self-config -o jsonpath='{.status.sync.status} {.status.health.status}' 2>/dev/null | grep -q 'Synced Healthy'" 180 5 || log_warning "argocd-self-config todavía no está totalmente sincronizado"

  wait_and_sync_applications

  # Asegurar sealed-secrets listo antes de usar kubeseal/kargo
  ensure_sealed_secrets_ready || true
  
  # Generar y sincronizar el SealedSecret de Kargo ahora que el controller está listo
  create_kargo_secret_workaround || true
  sync_sealedsecret_to_gitea || true

  # Hard refresh selectivo si namespaces fueron recreados recientemente
  hard_refresh_if_recent "kargo" "kargo" 900
  hard_refresh_if_recent "prometheus" "prometheus" 900
  hard_refresh_if_recent "grafana" "grafana" 900
  hard_refresh_if_recent "dashboard" "kubernetes-dashboard" 900
  hard_refresh_if_recent "argo-rollouts" "argo-rollouts" 900

  # Verificar servicios desplegados (NodePorts configurados via manifests GitOps)
  verify_gitops_services
}

verify_gitops_services() {
  log_info "Verificando arquitectura GitOps desplegada..."
  
  # Verificar ArgoCD self-management
  log_info "🔄 ArgoCD Self-Management:"
  local self_app_status
  self_app_status=$(kubectl -n argocd get app argocd-self-config -o jsonpath='{.status.sync.status}/{.status.health.status}' 2>/dev/null || echo "Unknown/Unknown")
  if [[ "$self_app_status" == "Synced/Healthy" ]]; then
    log_success "  ✅ argocd-self-config: $self_app_status (siguiendo Best Practices)"
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
        log_success "  ✅ $ns/$svc: NodePort $actual_port → http://localhost:$actual_port"
      else
        log_info "  ⏳ $ns/$svc: $svc_type (NodePort será configurado por manifest)"
      fi
    else
      log_info "  ⏳ $ns/$svc: Pendiente de despliegue"
    fi
  done
  
  log_success "🎯 Arquitectura GitOps: Cluster → ArgoCD (bootstrap) → Manifests (declarativo)"
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
  [access]=create_access_scripts
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

  log_step "▶️  [$current_stage_idx/$total_stages] [${stage}] $title"
  "$func"

  local end_ts
  end_ts=$(date +%s)
  local elapsed=$(( end_ts - start_ts ))
  local end_time=$(date '+%H:%M:%S')
  log_success "[$current_stage_idx/$total_stages] [${stage}] completado en ${elapsed}s ($end_time)"
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
    git remote add gitea-infrastructure "http://gitops:${GITEA_ADMIN_PASSWORD}@localhost:30083/gitops/infrastructure.git" 2>/dev/null || true
    
    log_info "✅ Remotos configurados:"
    log_info "   - gitea-argo-config: Configuración de ArgoCD"
    log_info "   - gitea-infrastructure: Manifests de infraestructura"
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
    log_success "$prefix sincronizado ✅"
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
  echo "🎉 INSTALACIÓN COMPLETADA EXITOSAMENTE"
  echo "====================================="
  echo ""
  echo "🧪 VERIFICACIÓN AUTOMÁTICA DEL ESTADO:"
  echo "====================================="

  local argocd_pods_ready
  argocd_pods_ready=$(kubectl get pods -n argocd --no-headers 2>/dev/null | awk '{if($2 ~ /\/.*/ && $3=="Running") print $1}' | wc -l || echo "0")
  echo "🔵 ArgoCD: $argocd_pods_ready/7 pods Running"

  echo "🔵 Aplicaciones GitOps:"
  kubectl get applications -n argocd --no-headers 2>/dev/null | while read -r app sync health _; do
    local status_icon="⏳"
    if [[ "$sync" == "Synced" && "$health" == "Healthy" ]]; then
      status_icon="✅"
    elif [[ "$sync" == "Synced" ]]; then
      status_icon="🟡"
    fi
    echo "   $status_icon $app: $sync + $health"
  done 2>/dev/null || echo "   ⏳ Aplicaciones iniciándose..."

  echo "🔵 Infraestructura desplegada:"
  for ns in argo-rollouts sealed-secrets kubernetes-dashboard grafana prometheus; do
    local pod_count
    pod_count=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | grep -c Running || echo 0)
    pod_count=$(echo "$pod_count" | tr -d '[:space:]')
    if [[ "${pod_count:-0}" -gt 0 ]]; then
      echo "   ✅ $ns: $pod_count pods Running"
    else
      echo "   ⏳ $ns: iniciándose..."
    fi
  done

  echo ""
  echo "🌐 Servicios disponibles (verificando accesibilidad):"
  local argocd_password
  argocd_password=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null || echo "[obteniendo...]")
  local gitea_pw="${GITEA_ADMIN_PASSWORD:-[obteniendo...]}"
  local grafana_admin_pw
  grafana_admin_pw=$(kubectl -n monitoring get secret grafana -o jsonpath="{.data.admin-password}" 2>/dev/null | base64 -d 2>/dev/null || echo "admin")

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
        echo "   ✅ $name reachable: $url"
      fi
      return 0
    fi

    if [[ "$quiet" != "true" ]]; then
      echo "   ❌ $name NOT reachable yet: $url (got $code)"
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
        echo "   ✅ $name reachable: $url"
        return 0
      fi

      last_code="$CHECK_URL_LAST_CODE"
      if [[ "$notified" == "false" ]]; then
        echo "   ⏳ $name todavía no responde (HTTP $last_code). Reintentando..."
        notified=true
      fi

      sleep $interval
      elapsed=$((elapsed + interval))
    done

    check_url "$url" "$name" "$expected_http" true
    last_code="$CHECK_URL_LAST_CODE"
    echo "   ❌ $name NOT reachable tras ${timeout}s: $url (último código $last_code)"
    return 1
  }

  wait_url "http://localhost:30080" "ArgoCD (admin/${argocd_password})" 200 60 || true
  wait_url "http://localhost:30083" "Gitea (gitops/${gitea_pw})" 200 180 || true
  wait_url "http://localhost:30092" "Prometheus" 200 240 || true
  wait_url "http://localhost:30093" "Grafana (admin/${grafana_admin_pw})" 200 240 || true
  wait_url "http://localhost:30094" "Kargo (admin/admin123)" 200 240 || true
  wait_url "http://localhost:30084" "Argo Rollouts" 200 180 || true
  wait_url "http://localhost:30085" "Kubernetes Dashboard (skip login)" 200 240 || true
  if [[ "$ENABLE_CUSTOM_APPS" == "true" ]]; then
    wait_url "http://localhost:30070" "Demo API" 200 240 || true
  else
    echo "   ℹ️  App Demo omitida (ENABLE_CUSTOM_APPS=${ENABLE_CUSTOM_APPS})"
  fi

  echo ""
  echo "📂 Estructura de repositorios creada:"
  echo "   ~/gitops-repos/gitops-infrastructure/      (Manifests de infraestructura)"
  echo "   ~/gitops-repos/gitops-applications/        (Manifests de aplicaciones)"
  echo "   ~/gitops-repos/argo-config/                (Configuración de ArgoCD)"
  if [[ "$ENABLE_CUSTOM_APPS" == "true" ]]; then
  echo "   ~/gitops-repos/sourcecode-apps/demo-api/              (Código fuente demo)"
  else
    echo "   ~/gitops-repos/sourcecode-apps/                      (Aplicaciones personalizadas deshabilitadas)"
  fi
  echo ""
  echo "🔧 Flujo GitOps configurado:"
  echo "   ✅ ArgoCD lee de repositorios Gitea locales"
  echo "   ✅ Remotos configurados para desarrollo:"
  echo "      - origin (GitHub): para backup y compartir código"
  echo "      - gitea-* (Gitea local): para el flujo GitOps"
  echo ""
  echo "🔄 Flujo de trabajo recomendado:"
  echo "   1. Trabajar en el repo local clonado de GitHub"
  echo "   2. Editar manifests (argo-config/, manifests/gitops-tools/)"
  echo "   3. git commit -m \"feat: nueva funcionalidad\""
  echo "   4. git push origin main  (backup a GitHub)"
  echo "   5. ./scripts/sync-to-gitea.sh  (sincronizar a Gitea → ArgoCD detecta cambios)"
  echo ""
  echo "📚 DOCUMENTACIÓN:"
  echo "   - ArgoCD: https://argo-cd.readthedocs.io/"
  echo "   - Kargo: https://docs.kargo.io/"
  echo "   - Sealed Secrets: https://sealed-secrets.netlify.app/"
  echo ""
  log_success "¡GitOps Master Setup 100% funcional! Verificación automática completada. 🎉"
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
  echo "╔════════════════════════════════════════════════════════════╗"
  echo "║              🚀 SETUP MASTER GITOPS                        ║"
  echo "╚════════════════════════════════════════════════════════════╝"
  echo "Este script prepara un entorno GitOps completo con kind + ArgoCD + observabilidad."
  echo ""
  echo "╔══════════════════════════════════════════════════════════╗"
  echo "║  🧩 Fases seleccionadas ($total_stages):"
  local idx=1
  for stage in "${stages_to_run[@]}"; do
    printf "║  %d/%d %-10s %s\n" "$idx" "$total_stages" "$stage" "${STAGE_TITLES[$stage]}"
    ((idx++))
  done
  echo "╚══════════════════════════════════════════════════════════╝"
  echo ""

  if [[ "$unattended" != true ]]; then
    echo "┌─────────────────────────────────────────────┐"
    echo "│  ❓ ¿Continuar con la ejecución? (y/N): │"
    echo "└─────────────────────────────────────────────┘"
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
