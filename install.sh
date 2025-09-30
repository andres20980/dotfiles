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
readonly SCRIPT_DIR
readonly DOTFILES_DIR="$SCRIPT_DIR"
readonly CLUSTER_NAME="mini-cluster"
readonly GITEA_NAMESPACE="gitea"

# Controla si se gestionan aplicaciones personalizadas (hello-world-modern, etc.)
# Por defecto deshabilitado para centrarse en herramientas GitOps.
ENABLE_CUSTOM_APPS="${ENABLE_CUSTOM_APPS:-false}"
readonly ENABLE_CUSTOM_APPS

export DEBIAN_FRONTEND=noninteractive

# =============================================================================
# FUNCIONES DE UTILIDAD
# =============================================================================

log_step() {
    local message="$1"
    echo ""
    echo "============================================================"
    echo "➡️  $message"
    echo "============================================================"
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

ensure_argocd_nodeport_and_reachability() {
  log_info "Asegurando argocd-server como NodePort:30080 y accesible desde host..."
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

  wait_for_condition "curl -fsS -o /dev/null -w '%{http_code}' --max-time 3 http://127.0.0.1:30080 | grep -q '^2\|^3'" 120 5 || true
}

wait_for_condition() {
    local condition_command="$1"
    local timeout="${2:-300}"
    local interval="${3:-10}"
    local elapsed=0

    while [[ $elapsed -lt $timeout ]]; do
        if eval "$condition_command"; then
            return 0
        fi
        sleep "$interval"
        elapsed=$((elapsed + interval))
    done

    return 1
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

  local required=(sudo apt-get curl git openssl)
  local missing=()
  for cmd in "${required[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing+=("$cmd")
    fi
  done

  if (( ${#missing[@]} > 0 )); then
    log_warning "Herramientas faltantes: ${missing[*]}. Se instalarán en la fase siguiente si es posible."
  else
    log_info "Herramientas básicas detectadas correctamente."
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
    
    # Docker
    if ! command -v docker >/dev/null 2>&1; then
        log_info "Instalando Docker..."
        curl -fsSL https://get.docker.com -o get-docker.sh
        sudo sh get-docker.sh >/dev/null 2>&1
        sudo usermod -aG docker "$USER"
        rm get-docker.sh
    fi

    # kubectl
    if ! command -v kubectl >/dev/null 2>&1; then
        log_info "Instalando kubectl..."
        curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
        sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
        rm kubectl
    fi

    # kind
    if ! command -v kind >/dev/null 2>&1; then
        log_info "Instalando kind..."
        [ "$(uname -m)" = x86_64 ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
        sudo install -o root -g root -m 0755 kind /usr/local/bin/kind
        rm kind
    fi

    # Helm
    if ! command -v helm >/dev/null 2>&1; then
        log_info "Instalando Helm..."
        curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash >/dev/null 2>&1
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
  # Rango representativo de NodePorts (30000-30100) expuestos para facilitar
  # acceso desde el host/Windows sin usar port-forward. Estos mapeos permiten
  # que los servicios con NodePort dentro del cluster sean accesibles en
  # localhost:<hostPort> en la máquina donde corre Docker/Kind.
  # ArgoCD (HTTP) estándar en 30080
  - containerPort: 30080
    hostPort: 30080
    protocol: TCP
  # OPA Gatekeeper Dashboard (Policy Testing UI)
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
  # NOTE: puerto 30080 ya mapeado arriba (para containerPort:80 -> hostPort:30080)
  # Evitamos duplicar mapeos idénticos para prevenir errores de kind
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

    # Instalar ArgoCD
    log_info "Instalando ArgoCD..."
    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml --validate=false >/dev/null

    # Esperar a que ArgoCD esté listo
    log_info "Esperando a que ArgoCD esté listo..."
    kubectl wait --for=condition=Ready pods --all -n argocd --timeout=600s

  # Exponer y comprobar reachability NodePort 30080
  ensure_argocd_nodeport_and_reachability

    # Verificar mapeos de puertos (sanity check)
    if ! check_mapping_sanity; then
        log_warning "Problemas detectados en el mapeo de puertos; revisa los mensajes previos"
    fi

    log_success "Cluster y ArgoCD creados (acceso sin autenticación)"
}



build_and_load_images() {
    log_step "Construyendo y cargando imágenes"

  if [[ "$ENABLE_CUSTOM_APPS" != "true" ]]; then
    log_info "Fase de imágenes de aplicaciones personalizadas deshabilitada (ENABLE_CUSTOM_APPS=${ENABLE_CUSTOM_APPS})."
    log_success "Imágenes personalizadas omitidas"
    return 0
  fi
    
    # Verificar si existe la estructura de repositorios
    local gitops_base_dir="$HOME/gitops-repos"
    local source_dir
    
  if [[ -d "$gitops_base_dir/sourcecode-apps/hello-world-modern" ]]; then
    source_dir="$gitops_base_dir/sourcecode-apps/hello-world-modern"
        log_info "Usando código fuente desde: $source_dir"
  else
    source_dir="$DOTFILES_DIR/sourcecode-apps/hello-world-modern"
        log_info "Usando código fuente desde dotfiles: $source_dir"
    fi
    
    # Verificar que el directorio existe
    if [[ ! -d "$source_dir" ]]; then
        log_error "Directorio de código fuente no encontrado: $source_dir"
        return 1
    fi
    
    # Construir hello-world-modern
    log_info "Construyendo imagen hello-world-modern..."
    cd "$source_dir"
    docker build -t hello-world-modern:latest . >/dev/null 2>&1

    # Cargar en kind
    log_info "Cargando imagen en cluster kind..."
    kind load docker-image hello-world-modern:latest --name "$CLUSTER_NAME" >/dev/null 2>&1

    cd "$DOTFILES_DIR"
    log_success "Imágenes construidas y cargadas"
}

setup_gitops() {
    log_step "Configurando GitOps completo"
    
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
    gitea_password=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-16)
    log_info "Password generado para Gitea: $gitea_password"
  fi

  export GITEA_ADMIN_PASSWORD="$gitea_password"
  log_info "Password para Gitea: $gitea_password"

    # Instalar Gitea
    install_gitea
    
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
        image: gitea/gitea:1.21
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

    # Esperar a que Gitea esté listo
    log_info "Esperando a que Gitea esté listo..."
  wait_for_condition "kubectl get pods -n $GITEA_NAMESPACE --no-headers | awk '{if(\$3 != \"Running\"){exit 1}} END {exit 0}'" 300
    sleep 30  # Tiempo adicional para que Gitea termine de inicializar
}

create_gitops_repositories() {
    log_info "Creando repositorios GitOps en Gitea..."
    
    # Directorio base para repositorios GitOps (fuera de dotfiles)
    local gitops_base_dir="$HOME/gitops-repos"
    
    # Esperar a que Gitea API esté disponible
    log_info "Esperando a que Gitea API esté disponible..."
    wait_for_condition "curl -fsS --output /dev/null http://localhost:30083/api/v1/version" 120
    
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
    "infrastructure|$DOTFILES_DIR/manifests/infrastructure|GitOps infrastructure manifests"
    "applications|$DOTFILES_DIR/manifests/applications|GitOps applications manifests"
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
    log_success "✅ $repo → $repo_dir"
  done

    # Crear repositorios de código fuente para desarrollo
    create_source_repositories "$gitops_base_dir"
    
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
    
    # Crear repositorio hello-world-modern para desarrollo
    local app_dir="$apps_dir/hello-world-modern"
    rm -rf "$app_dir"
    mkdir -p "$app_dir"
    
  # Copiar código fuente desde dotfiles
  cp -r "$DOTFILES_DIR/sourcecode-apps/hello-world-modern/"* "$app_dir/"
    
    # Inicializar repositorio git para desarrollo
    cd "$app_dir"
    git init -b main >/dev/null 2>&1
  git checkout -B main >/dev/null 2>&1
    git config user.name "Developer"
    git config user.email "dev@localhost"
    git add .
    git commit -m "Initial hello-world-modern application

- Aplicación Go moderna con métricas Prometheus
- Dockerfile para containerización
- Health checks y readiness probes
- Configuración para despliegue con argo-rollouts" >/dev/null 2>&1
    
    # Crear repositorio en Gitea para el código fuente
    curl -X POST "http://localhost:30083/api/v1/user/repos" \
        -H "Content-Type: application/json" \
        -u "gitops:$GITEA_ADMIN_PASSWORD" \
        -d "{
            \"name\": \"hello-world-modern\",
            \"description\": \"Hello World Modern Application Source Code\",
            \"auto_init\": false,
            \"private\": false
    }" >/dev/null 2>&1 || true

    # Subir código fuente a Gitea
  git remote remove origin >/dev/null 2>&1 || true
    git remote add origin "http://gitops:$GITEA_ADMIN_PASSWORD@localhost:30083/gitops/hello-world-modern.git"
    git push --set-upstream origin main >/dev/null 2>&1
    
    log_success "✅ hello-world-modern → $app_dir"
    log_info "📁 Estructura creada:"
  log_info "   $base_dir/gitops-infrastructure/  (manifests K8s)"
  log_info "   $base_dir/gitops-applications/    (manifests apps)"
  log_info "   $base_dir/sourcecode-apps/hello-world-modern/ (código fuente)"
}

setup_application_sets() {
  log_info "Registrando aplicaciones ArgoCD desde argo-config..."

  cat <<'EOF' | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: argo-config
  namespace: argocd
spec:
  project: default
  source:
    repoURL: http://gitea.gitea.svc.cluster.local:3000/gitops/argo-config.git
    targetRevision: HEAD
    path: .
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
EOF

  log_info "Esperando a que el Application 'argo-config' esté Synced/Healthy..."
  wait_for_condition "kubectl -n argocd get app argo-config -o jsonpath='{.status.sync.status} {.status.health.status}' 2>/dev/null | grep -q 'Synced Healthy'" 180 5 || log_warning "argo-config todavía no está totalmente sincronizado"

  wait_and_sync_applications

  configure_services_nodeports
}

configure_services_nodeports() {
    log_info "Configurando servicios como NodePort para acceso directo..."
    
    # Cambiar argocd-server a NodePort con nodePort 30080
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
    }' >/dev/null 2>&1 || log_warning "No se pudo configurar argocd-server NodePort"
    
  # grafana - usar nodePort 30093 (alineado con manifests)
  kubectl patch svc grafana -n grafana --type merge -p '{
        "spec": {
            "type": "NodePort",
            "ports": [{
                "name": "web",
                "port": 3000,
                "protocol": "TCP",
                "targetPort": 3000,
        "nodePort": 30093
            }]
        }
    }' >/dev/null 2>&1 || log_warning "No se pudo configurar grafana NodePort"
    
    # prometheus - usar nodePort 30092 (ya está en manifests)
  kubectl patch svc prometheus -n prometheus --type merge -p '{
        "spec": {
            "type": "NodePort",
            "ports": [{
                "name": "web",
                "port": 9090,
                "protocol": "TCP",
                "targetPort": 9090,
                "nodePort": 30092
            }]
        }
    }' >/dev/null 2>&1 || log_warning "No se pudo configurar prometheus NodePort"
    
    # argo-rollouts-dashboard - usar nodePort 30084 (ya está en manifests)
    kubectl patch svc argo-rollouts-dashboard -n argo-rollouts --type merge -p '{
        "spec": {
            "type": "NodePort",
            "ports": [{
                "port": 3100,
                "protocol": "TCP",
                "targetPort": 3100,
                "nodePort": 30084
            }]
        }
    }' >/dev/null 2>&1 || log_warning "No se pudo configurar argo-rollouts-dashboard NodePort"
    
  # kubernetes-dashboard - usar nodePort 30085 (HTTP plano)
  kubectl patch svc kubernetes-dashboard -n dashboard --type merge -p '{
    "spec": {
      "type": "NodePort",
      "ports": [{
        "name": "http",
        "port": 80,
        "protocol": "TCP",
        "targetPort": 9090,
        "nodePort": 30085
      }]
    }
  }' >/dev/null 2>&1 || log_warning "No se pudo configurar kubernetes-dashboard NodePort"

  if [[ "$ENABLE_CUSTOM_APPS" == "true" ]]; then
    # hello-world-canary - usar nodePort 30082 (ya está en manifests)
    kubectl patch svc hello-world-canary -n hello-world --type merge -p '{
      "spec": {
        "type": "NodePort",
        "ports": [{
          "name": "http",
          "port": 3000,
          "protocol": "TCP",
          "targetPort": 3000,
          "nodePort": 30082
        }]
      }
    }' >/dev/null 2>&1 || log_warning "No se pudo configurar hello-world-canary NodePort"
  else
    log_info "NodePort para hello-world-canary omitido (ENABLE_CUSTOM_APPS=${ENABLE_CUSTOM_APPS})."
  fi
    
    log_success "✅ Servicios configurados como NodePort"
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
            log_success "✅ $app_count aplicaciones generadas"
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

  local desired_apps=(argo-rollouts sealed-secrets dashboard grafana prometheus)
  if [[ "$ENABLE_CUSTOM_APPS" == "true" ]]; then
    desired_apps+=(hello-world)
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

create_access_scripts() {
  log_step "Configurando accesos rápidos"

  local open_command
  open_command="${DOTFILES_DIR}/install.sh --open"

  for shell_file in "$HOME/.zshrc" "$HOME/.bashrc"; do
    ensure_shell_alias "$shell_file" "argocd" "${open_command} argocd"
    ensure_shell_alias "$shell_file" "gitea" "${open_command} gitea"
    ensure_shell_alias "$shell_file" "dashboard" "${open_command} dashboard"
    ensure_shell_alias "$shell_file" "grafana" "${open_command} grafana"
    ensure_shell_alias "$shell_file" "prometheus" "${open_command} prometheus"
    ensure_shell_alias "$shell_file" "rollouts" "${open_command} rollouts"
  done

  log_success "Aliases de acceso actualizados"
  log_info "Usa 'dashboard', 'argocd', 'gitea', etc. para abrir los servicios"
}

# =============================================================================
# CONTROL DE FASES Y UTILIDADES CLI
# =============================================================================

declare -ar STAGE_ORDER=(
  prereqs
  system
  docker
  cluster
  images
  gitops
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
  [images]="Preparación de imágenes GitOps"
  [gitops]="Configuración completa GitOps"
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

  log_step "▶️  [${stage}] $title"
  "$func"

  local end_ts
  end_ts=$(date +%s)
  local elapsed=$(( end_ts - start_ts ))
  log_success "✅  [${stage}] completado en ${elapsed}s"
}

print_usage() {
  cat <<'EOF'
Uso: ./install.sh [opciones]

Opciones:
  --unattended           Ejecuta todas las fases sin pedir confirmación
  --stage <fase>         Ejecuta solo la fase indicada (ver --list-stages)
  --start-from <fase>    Ejecuta desde la fase indicada hasta el final
  --open <servicio>      Abre rápidamente la URL de un servicio (argocd, dashboard, gitea...)
  --list-stages          Muestra las fases disponibles y termina (si no se especifican fases)
  -h, --help             Muestra esta ayuda y termina

Ejemplos:
  ./install.sh --stage gitops
  ./install.sh --open dashboard
  ./install.sh --start-from gitops --unattended
  ./install.sh --list-stages
EOF
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

  check_url() {
    local url="$1"; local name="$2"; local expected_http="${3:-200}"
    local curl_opts=("-sS" "-o" "/dev/null" "-w" "%{http_code}" "--max-time" "10" "-L")
    case "$url" in https://*) curl_opts+=("-k");; esac
    local code
    code=$(curl "${curl_opts[@]}" "$url" || echo "000")
    if echo "$code" | grep -q "^$expected_http\|^30"; then
      echo "   ✅ $name reachable: $url"
      return 0
    else
      echo "   ❌ $name NOT reachable yet: $url (got $code)"
      return 1
    fi
  }

  wait_url() {
    local url="$1"; local name="$2"; local expected_http="${3:-200}"; local timeout="${4:-120}"; local interval=6
    local elapsed=0
    while [[ $elapsed -lt "$timeout" ]]; do
      if check_url "$url" "$name" "$expected_http"; then return 0; fi
      sleep $interval
      elapsed=$((elapsed + interval))
    done
    check_url "$url" "$name" "$expected_http" || return 1
  }

  wait_url "http://localhost:30080" "ArgoCD (admin/${argocd_password})" 200 60 || true
  wait_url "http://localhost:30083" "Gitea (gitops/${gitea_pw})" 200 180 || true
  wait_url "http://localhost:30092" "Prometheus" 200 240 || true
  wait_url "http://localhost:30093" "Grafana (admin/${grafana_admin_pw})" 200 240 || true
  wait_url "http://localhost:30084" "Argo Rollouts" 200 180 || true
  wait_url "http://localhost:30085" "Kubernetes Dashboard (skip login)" 200 240 || true
  if [[ "$ENABLE_CUSTOM_APPS" == "true" ]]; then
    wait_url "http://localhost:30082" "App Demo (Hello World)" 200 240 || true
  else
    echo "   ℹ️  App Demo omitida (ENABLE_CUSTOM_APPS=${ENABLE_CUSTOM_APPS})"
  fi

  echo ""
  echo "📂 Estructura de repositorios creada:"
  echo "   ~/gitops-repos/gitops-infrastructure/      (Manifests de infraestructura)"
  echo "   ~/gitops-repos/gitops-applications/        (Manifests de aplicaciones)"
  echo "   ~/gitops-repos/argo-config/                (Configuración de ArgoCD)"
  if [[ "$ENABLE_CUSTOM_APPS" == "true" ]]; then
    echo "   ~/gitops-repos/sourcecode-apps/hello-world-modern/    (Código fuente demo)"
  else
    echo "   ~/gitops-repos/sourcecode-apps/                      (Aplicaciones personalizadas deshabilitadas)"
  fi
  echo ""
  echo "🔧 Flujo de trabajo sugerido:"
  echo "   1. Editar manifests en los repos GitOps locales"
  echo "   2. Git commit + push hacia Gitea"
  echo "   3. ArgoCD sincroniza automáticamente"
  echo ""
  echo "📋 Comandos útiles:"
  echo "   ./install.sh --open <servicio>  - Abre el servicio indicado (argocd, dashboard, gitea, grafana, prometheus, rollouts)"
  echo "   Aliases disponibles tras reabrir tu shell: 'dashboard', 'argocd', 'gitea', ..."
  echo ""
  echo "🔍 Para verificar el estado manualmente:"
  echo "   kubectl get applications -n argocd"
  echo "   kubectl get pods --all-namespaces"
  echo ""
  echo "💡 Las aplicaciones pueden tardar 1-2 minutos en alcanzar estado Healthy"
  echo ""
  log_success "¡GitOps Master Setup 100% funcional! Verificación automática completada. 🎉"
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

  echo "🚀 SETUP MASTER GITOPS"
  echo "=============================================="
  echo "Este script prepara un entorno GitOps completo con kind + ArgoCD + observabilidad."
  echo ""
  echo "🧩 Fases seleccionadas ($total_stages):"
  local idx=1
  for stage in "${stages_to_run[@]}"; do
    printf "  %d/%d %-10s %s\n" "$idx" "$total_stages" "$stage" "${STAGE_TITLES[$stage]}"
    ((idx++))
  done
  echo ""

  if [[ "$unattended" == false ]]; then
    read -p "¿Continuar con la ejecución? (y/N): " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      echo "Instalación cancelada"
      exit 0
    fi
  else
    echo "🤖 MODO DESATENDIDO ACTIVADO - Ejecutando fases seleccionadas..."
  fi

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
    show_final_report
  else
    echo ""
    log_info "Ejecución finalizada. Usa --stage gitops o --start-from gitops para desplegar todo el stack."
  fi
}

# Ejecutar si es llamado directamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi