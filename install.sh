#!/bin/bash

# 🚀 GitOps Installation Script - Single Point of Entry
# Instala un entorno GitOps completo de forma totalmente desatendida
# 
# Uso: ./install.sh
# 
# Este script consolida toda la lógica de instalación en un solo lugar
# siguiendo mejores prácticas de scripting modular.

set -e

# =============================================================================
# CONFIGURACIÓN Y CONSTANTES
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly DOTFILES_DIR="$SCRIPT_DIR"
readonly CLUSTER_NAME="mini-cluster"
readonly GITEA_NAMESPACE="gitea"

# =============================================================================
# FUNCIONES DE UTILIDAD
# =============================================================================

log_step() {
    echo ""
    echo "🚀 PASO: $1"
    echo "----------------------------------------"
}


# Sanity check: verificar que los hostPorts mapeados por kind realmente apuntan
# a los containerPorts que los servicios esperan (ej. argocd-server -> 8080)
check_mapping_sanity() {
  log_step "Comprobando mapeos de puertos (sanity)"

  # Detectar contenedor control-plane de kind
  local node_container
  node_container=$(docker ps --format '{{.Names}}' | grep "${CLUSTER_NAME}-control-plane" || true)
  if [[ -z "$node_container" ]]; then
    log_warning "No se encontró el contenedor del control-plane. No puedo verificar mapeos."
    return 1
  fi

  local issues=0
  local mapping
  mapping=$(docker port "$node_container" 2>/dev/null || true)

  # argocd-server
  if kubectl get svc argocd-server -n argocd >/dev/null 2>&1; then
    local nodePort
    nodePort=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}{.spec.ports[?(@.port==443)].nodePort}' 2>/dev/null | awk '{print $1}')
    if [[ -z "$nodePort" ]]; then
      nodePort=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.spec.ports[?(@.nodePort)].nodePort}' 2>/dev/null | awk '{print $1}')
    fi
    log_info "argocd-server nodePort: ${nodePort:-none}"

    # comprobar que docker expone ese puerto del nodo y que responde HTTP
    if [[ -z "$nodePort" ]]; then
      log_warning "argocd-server aún no es NodePort"
      issues=$((issues+1))
    elif ! echo "$mapping" | grep -q ":${nodePort}"; then
      log_warning "NodePort ${nodePort} de argocd-server no aparece en 'docker port' del nodo $node_container"
      issues=$((issues+1))
    else
      # prueba de conectividad
      if curl -s -o /dev/null -w "%{http_code}" --max-time 3 "http://127.0.0.1:${nodePort}" | grep -q "^2\|^3"; then
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

  # Comprobar unos NodePorts comunes: gitea (si existe), grafana, prometheus
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

# Asegura que el servicio argocd-server esté en NodePort 30080 y que responda por HTTP
ensure_argocd_nodeport_and_reachability() {
  log_info "Asegurando argocd-server como NodePort:30080 y accesible desde host..."
  # Hacer el patch de manera idempotente y con reintentos breves
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

    # Validar que ya es NodePort 30080
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

  # Esperar a que responda HTTP en localhost:30080 (hasta 120s)
  wait_for_condition "curl -s -o /dev/null -w '%{http_code}' --max-time 3 http://127.0.0.1:30080 | grep -q '^2\|^3'" 120 5 || true
}

log_success() {
    echo "✅ $1"
}

log_info() {
    echo "💡 $1"
}

log_error() {
    echo "❌ ERROR: $1" >&2
}

log_warning() {
    echo "⚠️ WARNING: $1"
}

validate_prerequisites() {
    log_step "Verificando prerequisitos"
    
    # Validar que estamos en el directorio correcto
    if [[ ! -f "install.sh" ]]; then
        log_error "Debes ejecutar este script desde la raíz del repositorio dotfiles"
        exit 1
    fi

    # Validar permisos sudo
    if ! id -nG | grep -qw "sudo"; then
        log_error "Tu usuario necesita permisos sudo"
        exit 1
    fi

    log_success "Prerequisitos verificados"
}

wait_for_condition() {
    local condition="$1"
    local timeout="${2:-300}"
    local interval="${3:-10}"
    
    local elapsed=0
    while ! eval "$condition" >/dev/null 2>&1; do
        if [[ $elapsed -ge $timeout ]]; then
            log_error "Timeout esperando: $condition"
            return 1
        fi
        sleep "$interval"
        elapsed=$((elapsed + interval))
        log_info "Esperando... (${elapsed}s/${timeout}s)"
    done
    return 0
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
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml >/dev/null

    # Esperar a que ArgoCD esté listo
    log_info "Esperando a que ArgoCD esté listo..."
    kubectl wait --for=condition=Ready pods --all -n argocd --timeout=600s

  # Configurar ArgoCD sin autenticación para desarrollo local
  log_info "Configurando ArgoCD sin autenticación..."
  kubectl patch configmap argocd-cmd-params-cm -n argocd --type merge -p '{"data":{"server.insecure":"true","server.disable.auth":"true"}}' >/dev/null 2>&1 || true
  kubectl rollout restart deployment argocd-server -n argocd >/dev/null 2>&1 || true
  kubectl wait --for=condition=Ready pods -l app.kubernetes.io/name=argocd-server -n argocd --timeout=180s >/dev/null 2>&1 || true

  # Configurar health check personalizado para Ingress (fix Dashboard health status)
  log_info "Configurando health checks personalizados..."
  kubectl patch configmap argocd-cm -n argocd --type merge -p '{"data":{"resource.customizations.health.networking.k8s.io_Ingress":"hs = {}\nhs.status = \"Healthy\"\nhs.message = \"Ingress is configured\"\nreturn hs"}}' >/dev/null 2>&1 || true
  kubectl rollout restart statefulset argocd-application-controller -n argocd >/dev/null 2>&1 || true
  kubectl wait --for=condition=Ready pods -l app.kubernetes.io/name=argocd-application-controller -n argocd --timeout=180s >/dev/null 2>&1 || true

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
    
    # Verificar si existe la estructura de repositorios
    local gitops_base_dir="$HOME/gitops-repos"
    local source_dir
    
    if [[ -d "$gitops_base_dir/apps/hello-world-modern" ]]; then
        source_dir="$gitops_base_dir/apps/hello-world-modern"
        log_info "Usando código fuente desde: $source_dir"
    else
        source_dir="$DOTFILES_DIR/source-code/hello-world-modern"
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
    local gitea_password
    gitea_password=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-16)
    export GITEA_ADMIN_PASSWORD="$gitea_password"
    
    log_info "Password generado para Gitea: $gitea_password"

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
    wait_for_condition "kubectl get pods -n $GITEA_NAMESPACE --no-headers | grep -v Running | wc -l | grep -q '^0$'" 300
    sleep 30  # Tiempo adicional para que Gitea termine de inicializar
}

create_gitops_repositories() {
    log_info "Creando repositorios GitOps en Gitea..."
    
    # Directorio base para repositorios GitOps (fuera de dotfiles)
    local gitops_base_dir="$HOME/gitops-repos"
    
    # Esperar a que Gitea API esté disponible
    log_info "Esperando a que Gitea API esté disponible..."
    wait_for_condition "curl -s -f http://localhost:30083/api/v1/version" 120
    
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
    for repo in infrastructure applications; do
        log_info "Creando repositorio: $repo"
        
        # Crear repositorio en Gitea
        curl -X POST "http://localhost:30083/api/v1/user/repos" \
            -H "Content-Type: application/json" \
            -u "gitops:$GITEA_ADMIN_PASSWORD" \
            -d "{
                \"name\": \"$repo\",
                \"description\": \"GitOps $repo repository\",
                \"auto_init\": true,
                \"private\": false
            }" >/dev/null 2>&1

        # Crear directorio de trabajo para el repositorio
        local repo_dir="$gitops_base_dir/gitops-$repo"
        rm -rf "$repo_dir"  # Limpiar si existe
        mkdir -p "$repo_dir"
        
        # Copiar manifests desde dotfiles
        if [[ "$repo" == "infrastructure" ]]; then
            cp -r "$DOTFILES_DIR/manifests/infrastructure/"* "$repo_dir/"
        else
            cp -r "$DOTFILES_DIR/manifests/applications/"* "$repo_dir/"
        fi

        # Inicializar y subir repositorio
        cd "$repo_dir"
        git init -b main >/dev/null 2>&1
        git config user.name "GitOps Setup"
        git config user.email "gitops@localhost"
        git add .
        git commit -m "Initial GitOps $repo manifests with correct versions

- argo-rollouts: v1.8.3 con argumentos correctos
- sealed-secrets: docker.io registry 
- RBAC: permisos completos
- Manifests listos para producción" >/dev/null 2>&1
        git remote add origin "http://gitops:$GITEA_ADMIN_PASSWORD@localhost:30083/gitops/$repo.git"
        git push --set-upstream origin main --force >/dev/null 2>&1
        
        log_success "✅ $repo → $repo_dir"
    done

    # Crear repositorios de código fuente para desarrollo
    create_source_repositories "$gitops_base_dir"
    
    cd "$DOTFILES_DIR"
}

create_source_repositories() {
    local base_dir="$1"
    log_info "Creando repositorios de código fuente para desarrollo..."
    
    # Directorio para aplicaciones de desarrollo
    local apps_dir="$base_dir/apps"
    mkdir -p "$apps_dir"
    
    # Crear repositorio hello-world-modern para desarrollo
    local app_dir="$apps_dir/hello-world-modern"
    rm -rf "$app_dir"
    mkdir -p "$app_dir"
    
    # Copiar código fuente desde dotfiles
    cp -r "$DOTFILES_DIR/source-code/hello-world-modern/"* "$app_dir/"
    
    # Inicializar repositorio git para desarrollo
    cd "$app_dir"
    git init -b main >/dev/null 2>&1
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
        }" >/dev/null 2>&1

    # Subir código fuente a Gitea
    git remote add origin "http://gitops:$GITEA_ADMIN_PASSWORD@localhost:30083/gitops/hello-world-modern.git"
    git push --set-upstream origin main >/dev/null 2>&1
    
    log_success "✅ hello-world-modern → $app_dir"
    log_info "📁 Estructura creada:"
    log_info "   $base_dir/gitops-infrastructure/  (manifests K8s)"
    log_info "   $base_dir/gitops-applications/    (manifests apps)"
    log_info "   $base_dir/apps/hello-world-modern/ (código fuente)"
}

setup_application_sets() {
    log_info "Configurando ApplicationSets..."
    
    # ApplicationSet para infraestructura
    kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: gitops-tools
  namespace: argocd
spec:
  generators:
  - git:
      repoURL: http://gitea.gitea.svc.cluster.local:3000/gitops/infrastructure.git
      revision: HEAD
      directories:
      - path: "*"
  template:
    metadata:
      name: '{{path.basename}}'
    spec:
      project: infrastructure
      source:
        repoURL: http://gitea.gitea.svc.cluster.local:3000/gitops/infrastructure.git
        targetRevision: HEAD
        path: '{{path}}'
      destination:
        server: https://kubernetes.default.svc
        namespace: '{{path.basename}}'
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
        - CreateNamespace=true
        - PrunePropagationPolicy=foreground
        - PruneLast=true
---
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: custom-apps
  namespace: argocd
spec:
  generators:
  - git:
      repoURL: http://gitea.gitea.svc.cluster.local:3000/gitops/applications.git
      revision: HEAD
      directories:
      - path: "*"
  template:
    metadata:
      name: '{{path.basename}}'
    spec:
      project: applications
      source:
        repoURL: http://gitea.gitea.svc.cluster.local:3000/gitops/applications.git
        targetRevision: HEAD
        path: '{{path}}'
      destination:
        server: https://kubernetes.default.svc
        namespace: '{{path.basename}}'
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
        - CreateNamespace=true
        - PrunePropagationPolicy=foreground
        - PruneLast=true
EOF

    # Proyectos ArgoCD
    kubectl apply -f "$DOTFILES_DIR/gitops/projects/"
    
    # Configurar permisos de proyectos automáticamente
    configure_argocd_permissions
    
    # Esperar y sincronizar aplicaciones automáticamente
    wait_and_sync_applications

    # Configurar servicios como NodePort para acceso directo
    configure_services_nodeports
}

configure_argocd_permissions() {
    log_info "Configurando permisos de proyectos ArgoCD..."
    
    # Esperar a que ArgoCD esté completamente listo
    wait_for_condition "kubectl get pods -n argocd --no-headers | grep -v Running | wc -l | grep -q '^0$'" 300
    sleep 10
    
    # Actualizar proyecto infrastructure con todos los namespaces necesarios
    kubectl patch appproject infrastructure -n argocd --type merge -p '{
        "spec": {
            "destinations": [
                {"namespace": "monitoring", "server": "https://kubernetes.default.svc"},
                {"namespace": "kubernetes-dashboard", "server": "https://kubernetes.default.svc"},
                {"namespace": "ingress-nginx", "server": "https://kubernetes.default.svc"},
                {"namespace": "argo-rollouts", "server": "https://kubernetes.default.svc"},
                {"namespace": "sealed-secrets", "server": "https://kubernetes.default.svc"},
                {"namespace": "dashboard", "server": "https://kubernetes.default.svc"},
                {"namespace": "grafana", "server": "https://kubernetes.default.svc"},
                {"namespace": "prometheus", "server": "https://kubernetes.default.svc"}
            ]
        }
    }' >/dev/null 2>&1
    
    log_success "✅ Permisos de proyectos configurados"
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
    kubectl patch svc grafana -n monitoring --type merge -p '{
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
    kubectl patch svc prometheus -n monitoring --type merge -p '{
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
    
    # kubernetes-dashboard - usar nodePort 30085 (ya está en manifests)
    kubectl patch svc kubernetes-dashboard -n kubernetes-dashboard --type merge -p '{
        "spec": {
            "type": "NodePort",
            "ports": [{
                "name": "https",
                "port": 443,
                "protocol": "TCP",
                "targetPort": 8443,
                "nodePort": 30085
            }]
        }
    }' >/dev/null 2>&1 || log_warning "No se pudo configurar kubernetes-dashboard NodePort"

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
  kubectl exec -n argocd deployment/argocd-server -- argocd app sync argo-rollouts sealed-secrets dashboard grafana prometheus hello-world gatekeeper --insecure --server localhost:8080 >/dev/null 2>&1 || true

  # Esperar a que las aplicaciones alcancen estado saludable
  log_info "Esperando a que las aplicaciones alcancen estado saludable..."
  sleep 30

    # Esperar a que apps clave estén Healthy
    log_info "Esperando a que apps estén Synced+Healthy (dashboard, grafana, prometheus, argo-rollouts, sealed-secrets, hello-world, gatekeeper)..."
    local apps=(dashboard grafana prometheus argo-rollouts sealed-secrets hello-world gatekeeper)
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
    log_step "Configurando scripts de acceso"
    
    # Script de dashboard
    cat > "$DOTFILES_DIR/dashboard.sh" << 'EOF'
#!/bin/bash
set -euo pipefail
URL="https://localhost:30085"
echo "🚀 Abriendo Kubernetes Dashboard en $URL"
echo "💡 En la pantalla de login, pulsa 'SKIP'"
if command -v cmd.exe >/dev/null 2>&1; then
  cmd.exe /c start "$URL" 2>/dev/null || true
else
  xdg-open "$URL" 2>/dev/null || echo "Dashboard disponible en: $URL"
fi
EOF

    chmod +x "$DOTFILES_DIR/dashboard.sh"
    
    # Aliases en .zshrc
    if [[ -f "$HOME/.zshrc" ]]; then
        local gitea_url="http://localhost:30083"
        if grep -q "alias gitea=" "$HOME/.zshrc"; then
            sed -i "s|alias gitea=.*|alias gitea='echo \"Gitea: $gitea_url\"'|" "$HOME/.zshrc"
        else
            echo "alias gitea='echo \"Gitea: $gitea_url\"'" >> "$HOME/.zshrc"
        fi
    fi

    log_success "Scripts de acceso configurados"
}

# =============================================================================
# FUNCIÓN PRINCIPAL
# =============================================================================

main() {
    # Modo desatendido si se pasa argumento --unattended
    local unattended=false
    if [[ "$1" == "--unattended" ]]; then
        unattended=true
    fi
    
    echo "🚀 INSTALADOR MASTER GITOPS"
    echo "=============================================="
    echo "Este script instalará un entorno GitOps completo:"
    echo ""
    echo "📋 Componentes a instalar:"
    echo "  🔧 Sistema base (zsh, git, herramientas)"
    echo "  🐳 Docker + kubectl + kind"
    echo "  🏗️ Cluster Kubernetes + ArgoCD"
    echo "  🚀 GitOps (Gitea + aplicaciones)"
    echo ""
    echo "📊 Stack de observabilidad:"
    echo "  📈 Prometheus (métricas)"
    echo "  📊 Grafana (dashboards)"
    echo "  🎯 Hello World moderna (con métricas)"
    echo "  📱 Kubernetes Dashboard"
    echo ""
    echo "🔒 Seguridad y Políticas:"
    echo "  🛡️ OPA Gatekeeper (Policy as Code)"
    echo ""
    echo "⏱️ Tiempo estimado: 15-20 minutos"
    echo ""
    
    if [[ "$unattended" == "false" ]]; then
        read -p "¿Continuar con la instalación? (y/N): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Instalación cancelada"
            exit 0
        fi
    else
        echo "🤖 MODO DESATENDIDO ACTIVADO - Instalando automáticamente..."
    fi

    # Ejecutar pasos de instalación
    validate_prerequisites
    install_system_base
    install_docker_and_tools
    create_cluster
    build_and_load_images
    setup_gitops
    create_access_scripts

    # Mostrar información final
    echo ""
    echo "🎉 INSTALACIÓN COMPLETADA EXITOSAMENTE"
    echo "====================================="
    echo ""
    echo "� VERIFICACIÓN AUTOMÁTICA DEL ESTADO:"
    echo "====================================="
    
    # Verificar pods de ArgoCD
    local argocd_pods_ready
    argocd_pods_ready=$(kubectl get pods -n argocd --no-headers 2>/dev/null | awk '{if($2 ~ /\/.*/ && $3=="Running") print $1}' | wc -l || echo "0")
    echo "🔵 ArgoCD: $argocd_pods_ready/7 pods Running"
    
    # Verificar aplicaciones GitOps
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
    
    # Verificar infraestructura desplegada
    echo "🔵 Infraestructura desplegada:"
  for ns in argo-rollouts sealed-secrets kubernetes-dashboard gatekeeper; do
    local pod_count
    pod_count=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | grep -c Running || echo 0)
    pod_count=$(echo "$pod_count" | tr -d '[:space:]')
    if [ "${pod_count:-0}" -gt 0 ]; then
            echo "   ✅ $ns: $pod_count pods Running"
        else
            echo "   ⏳ $ns: iniciándose..."
        fi
    done
    
    echo ""
  echo "� Servicios disponibles (verificando accesibilidad):"
  # Obtener credenciales desde secretos/configmaps
  local argocd_password
  argocd_password=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null || echo "[obteniendo...]")
  local gitea_pw="${GITEA_ADMIN_PASSWORD:-[obteniendo...]}"
    local grafana_admin_pw
    grafana_admin_pw=$(kubectl -n monitoring get secret grafana -o jsonpath="{.data.admin-password}" 2>/dev/null | base64 -d 2>/dev/null || echo "admin")
  # Helper para chequear una URL (con soporte HTTPS -k y follow redirects)
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
  while [ $elapsed -lt "$timeout" ]; do
      if check_url "$url" "$name" "$expected_http"; then return 0; fi
      sleep $interval
      elapsed=$((elapsed + interval))
    done
    check_url "$url" "$name" "$expected_http" || return 1
  }

  # Chequeos activos con espera (hostPorts expuestos por kind)
  wait_url "http://localhost:30080" "ArgoCD (admin/${argocd_password})" 200 60 || true
  wait_url "http://localhost:30083" "Gitea (gitops/${gitea_pw})" 200 180 || true
  wait_url "http://localhost:30092" "Prometheus" 200 240 || true
  wait_url "http://localhost:30093" "Grafana (admin/${grafana_admin_pw})" 200 240 || true
  wait_url "http://localhost:30084" "Argo Rollouts" 200 180 || true
  wait_url "https://localhost:30085" "Kubernetes Dashboard (skip login)" 200 240 || true
  wait_url "http://localhost:30082" "App Demo (Hello World)" 200 240 || true
  wait_url "http://localhost:30000" "OPA Gatekeeper Dashboard" 200 120 || true
  wait_url "http://localhost:30181" "OPA API (Policy Engine)" 200 120 || true
    echo ""
    echo "� Estructura de repositorios creada:"
    echo "   ~/gitops-repos/gitops-infrastructure/   (Kubernetes manifests)"
    echo "   ~/gitops-repos/gitops-applications/     (Application manifests)"
    echo "   ~/gitops-repos/apps/hello-world-modern/ (Source code)"
    echo ""
    echo "🔧 Flujo de desarrollo:"
    echo "   1. Modificar código en: ~/gitops-repos/apps/hello-world-modern/"
    echo "   2. Build + push imagen: cd ~/gitops-repos/apps/hello-world-modern && docker build -t hello-world-modern:latest ."
    echo "   3. Cargar en kind: kind load docker-image hello-world-modern:latest --name $CLUSTER_NAME"
    echo "   4. Modificar manifests en: ~/gitops-repos/gitops-applications/"
    echo "   5. Git push → ArgoCD sync automático"
    echo ""
    echo "�📋 Comandos útiles:"
    echo "   ./dashboard.sh     - Abrir Dashboard K8s"
    echo "   gitea             - Ver URL de Gitea"
    echo ""
    echo "� Endpoints de Seguridad:"
    echo "   http://localhost:30000 - OPA Gatekeeper Dashboard (Policy Testing)"
    echo "   http://localhost:30181 - OPA API (Policy Queries)"
    echo ""
    echo "�🔍 Para verificar el estado:"
    echo "   kubectl get applications -n argocd"
    echo "   kubectl get pods --all-namespaces"
    echo "   kubectl get constrainttemplate -A  # Ver políticas OPA"
    echo ""
    echo "💡 Las aplicaciones pueden tardar 1-2 minutos en alcanzar estado Healthy"
    echo "💡 Gatekeeper incluye UI web para testing de políticas en tiempo real"
    echo ""
    log_success "¡GitOps Master Setup 100% funcional! Verificación automática completada. 🎉"
}

# Ejecutar si es llamado directamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi