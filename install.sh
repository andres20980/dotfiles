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

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly DOTFILES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
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
    if [[ ! -f "$DOTFILES_DIR/install.sh" ]]; then
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
        sleep $interval
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
        [ $(uname -m) = x86_64 ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
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
  - containerPort: 80
    hostPort: 30080
    protocol: TCP
  - containerPort: 443
    hostPort: 30443
    protocol: TCP
  - containerPort: 30083
    hostPort: 30083
    protocol: TCP
  - containerPort: 30022
    hostPort: 30022
    protocol: TCP
  - containerPort: 30001
    hostPort: 30001
    protocol: TCP
  - containerPort: 30002
    hostPort: 30002
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
EOF

    # Instalar ArgoCD
    log_info "Instalando ArgoCD..."
    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f - >/dev/null
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml >/dev/null

    # Esperar a que ArgoCD esté listo
    log_info "Esperando a que ArgoCD esté listo..."
    wait_for_condition "kubectl get pods -n argocd --no-headers | grep -v Running | wc -l | grep -q '^0$'" 300

    log_success "Cluster y ArgoCD creados"
}

build_and_load_images() {
    log_step "Construyendo y cargando imágenes"
    
    # Construir hello-world-modern
    log_info "Construyendo imagen hello-world-modern..."
    cd "$DOTFILES_DIR/source-code/hello-world-modern"
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
    local gitea_password=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-16)
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
          value: "true"
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
    
    # Crear usuario gitops en Gitea
    local temp_dir="/tmp/gitea_setup_$$"
    mkdir -p "$temp_dir"
    
    # Esperar a que Gitea API esté disponible
    wait_for_condition "curl -s -f http://localhost:30083/api/v1/version" 60
    
    # Crear usuario gitops (puede fallar si ya existe, es OK)
    curl -X POST "http://localhost:30083/api/v1/admin/users" \
        -H "Content-Type: application/json" \
        -u "admin:$GITEA_ADMIN_PASSWORD" \
        -d "{
            \"username\": \"gitops\",
            \"email\": \"gitops@localhost\",
            \"password\": \"$GITEA_ADMIN_PASSWORD\",
            \"must_change_password\": false
        }" >/dev/null 2>&1 || true

    # Crear repositorios
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

        # Preparar directorio temporal con manifests
        local repo_dir="$temp_dir/$repo"
        mkdir -p "$repo_dir"
        
        if [[ "$repo" == "infrastructure" ]]; then
            cp -r "$DOTFILES_DIR/manifests/infrastructure/"* "$repo_dir/"
        else
            cp -r "$DOTFILES_DIR/manifests/applications/"* "$repo_dir/"
        fi

        # Subir manifests al repositorio
        cd "$repo_dir"
        git init -b main >/dev/null 2>&1
        git config user.name "GitOps Setup"
        git config user.email "gitops@localhost"
        git add .
        git commit -m "Initial GitOps $repo manifests" >/dev/null 2>&1
        git remote add origin "http://gitops:$GITEA_ADMIN_PASSWORD@localhost:30083/gitops/$repo.git"
        git push --set-upstream origin main --force >/dev/null 2>&1
        
        log_success "✅ $repo repository creado y poblado"
    done

    rm -rf "$temp_dir"
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
}

create_access_scripts() {
    log_step "Configurando scripts de acceso"
    
    # Script de dashboard
    cat > "$DOTFILES_DIR/dashboard.sh" << 'EOF'
#!/bin/bash
echo "🚀 Abriendo Kubernetes Dashboard..."
echo "💡 En la pantalla de login, haz click en 'SKIP'"
kubectl proxy --port=8001 &
sleep 3
if command -v cmd.exe >/dev/null 2>&1; then
    cmd.exe /c start http://localhost:8001/api/v1/namespaces/dashboard/services/https:kubernetes-dashboard:/proxy/ 2>/dev/null
else
    echo "Dashboard disponible en: http://localhost:8001/api/v1/namespaces/dashboard/services/https:kubernetes-dashboard:/proxy/"
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
    echo "⏱️ Tiempo estimado: 15-20 minutos"
    echo ""
    read -p "¿Continuar con la instalación? (y/N): " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Instalación cancelada"
        exit 0
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
    echo "🚀 Servicios disponibles:"
    echo "   ArgoCD:     http://localhost:8080 (admin/[ver secret])"
    echo "   Gitea:      http://localhost:30083 (gitops/$GITEA_ADMIN_PASSWORD)"
    echo "   Dashboard:  ./dashboard.sh"
    echo ""
    echo "📋 Comandos útiles:"
    echo "   ./dashboard.sh     - Abrir Dashboard K8s"
    echo "   gitea             - Ver URL de Gitea"
    echo ""
    echo "🔍 Para verificar el estado:"
    echo "   kubectl get applications -n argocd"
    echo "   kubectl get pods --all-namespaces"
    echo ""
    log_success "¡Todo listo! El entorno GitOps está funcionando."
}

# Ejecutar si es llamado directamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi