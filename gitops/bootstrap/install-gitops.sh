#!/bin/bash

# 🚀 GitOps Bootstrap - Solo lógica GitOps  
# Instala Gitea + configura repositorios + despliega aplicaciones

set -e

echo "🚀 Configurando GitOps completo..."
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

# Detectar directorio base automáticamente (agnóstico al usuario)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "📁 Directorio base detectado: $DOTFILES_DIR"

# --- Instalar Gitea ---
log_step "Instalando Gitea..."
kubectl create namespace gitea --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: gitea-data
  namespace: gitea
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 1Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gitea
  namespace: gitea
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
      initContainers:
      - name: gitea-init
        image: gitea/gitea:1.21.11
        command: ["/bin/sh"]
        args:
        - -c
        - |
          mkdir -p /data/gitea/conf
          cat > /data/gitea/conf/app.ini << 'EOL'
          [database]
          DB_TYPE = sqlite3
          PATH = /data/gitea/gitea.db
          
          [repository]
          ROOT = /data/git/repositories
          
          [server]
          DOMAIN = localhost
          HTTP_PORT = 3000
          ROOT_URL = http://localhost:30083/
          DISABLE_SSH = false
          SSH_PORT = 22
          
          [security]
          INSTALL_LOCK = true
          
          [service]
          DISABLE_REGISTRATION = false
          REQUIRE_SIGNIN_VIEW = false
          
          [log]
          ROOT_PATH = /data/gitea/log
          EOL
          echo "Configuración inicial de Gitea completada"
        volumeMounts:
        - name: data
          mountPath: /data
      containers:
      - name: gitea
        image: gitea/gitea:1.21.11
        ports:
        - containerPort: 3000
        - containerPort: 22
        volumeMounts:
        - name: data
          mountPath: /data
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: gitea-data
---
apiVersion: v1
kind: Service
metadata:
  name: gitea
  namespace: gitea
spec:
  selector:
    app: gitea
  type: NodePort
  ports:
  - name: web
    port: 3000
    targetPort: 3000
    nodePort: 30083
  - name: ssh
    port: 22
    targetPort: 22
    nodePort: 30022
EOF

log_step "Esperando a que Gitea esté listo..."
kubectl wait --for=condition=available --timeout=300s deployment/gitea -n gitea

# Esperar más tiempo para que Gitea complete la configuración inicial
sleep 45

# Función para configurar usuario administrador en Gitea
configure_gitea() {
    log_step "Configurando usuario administrador..."
    
    # Esperar a que Gitea esté completamente funcionando
    for i in {1..20}; do
        echo "Intento $i: Verificando Gitea..."
        if curl -s -f http://localhost:30083/ | grep -q "Sign In" 2>/dev/null; then
            log_success "Gitea está funcionando"
            break
        fi
        sleep 10
    done
    
    # Crear usuario via API web (evita problemas de root)
    log_step "Creando usuario gitops via API..."
    curl -X POST "http://localhost:30083/user/sign_up" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "user_name=gitops&email=gitops@localhost&password=gitops123&retype=gitops123" \
        >/dev/null 2>&1 || log_info "Usuario puede ya existir"
    
    sleep 5
    
    # Crear repositorios via API
    log_step "Creando repositorios Git..."
    for repo in infrastructure applications bootstrap; do
        echo "📦 Creando repositorio: $repo"
        curl -X POST "http://localhost:30083/api/v1/user/repos" \
            -H "Content-Type: application/json" \
            -u "gitops:gitops123" \
            -d "{
                \"name\": \"$repo\",
                \"description\": \"GitOps repository for $repo\",
                \"private\": false,
                \"auto_init\": true,
                \"default_branch\": \"main\"
            }" >/dev/null 2>&1 && echo "✅ $repo creado" || echo "⚠️ $repo ya existe o error"
    done
    
    # Verificar login
    for i in {1..5}; do
        echo "Verificando login de gitops (intento $i)..."
        if curl -s -f -u "gitops:gitops123" "http://localhost:30083/api/v1/user" >/dev/null 2>&1; then
            log_success "Usuario gitops configurado correctamente"
            return 0
        fi
        sleep 5
    done
    
    log_info "Continuando con configuración (usuario puede existir)..."
    return 0
}

# Ejecutar configuración de Gitea
configure_gitea

# --- Subir manifests a repositorios Git ---
log_step "Subiendo manifests a repositorios Git en Gitea..."

# Verificar que existan los directorios
if [[ ! -d "$DOTFILES_DIR/manifests" ]]; then
    log_info "Error: No se encontró $DOTFILES_DIR/manifests/"
    exit 1
fi

TEMP_DIR="/tmp/gitops-upload"
mkdir -p "$TEMP_DIR"

# Subir manifests de infraestructura
log_step "Subiendo infraestructura a Git..."
if [[ -d "$DOTFILES_DIR/manifests/infrastructure" ]]; then
    rm -rf "$TEMP_DIR" 2>/dev/null || true
    mkdir -p "$TEMP_DIR"
    cp -r "$DOTFILES_DIR/manifests/infrastructure"/* "$TEMP_DIR/"
    cd "$TEMP_DIR"
    git init -b main >/dev/null 2>&1
    git config user.name "GitOps Setup"
    git config user.email "gitops@localhost"
    git add .
    git commit -m "Infrastructure: Dashboard + Prometheus + Grafana (ports fixed)" >/dev/null 2>&1
    git remote add origin http://gitops:gitops123@localhost:30083/gitops/infrastructure.git
    git push --set-upstream origin main >/dev/null 2>&1 && log_success "Infrastructure subida a Git" || log_info "Error subiendo infrastructure"
fi

# Subir manifests de aplicaciones
log_step "Subiendo aplicaciones a Git..."
if [[ -d "$DOTFILES_DIR/manifests/applications" ]]; then
    rm -rf "$TEMP_DIR" 2>/dev/null || true
    mkdir -p "$TEMP_DIR"
    cp -r "$DOTFILES_DIR/manifests/applications"/* "$TEMP_DIR/"
    cd "$TEMP_DIR"
    git init -b main >/dev/null 2>&1
    git config user.name "GitOps Setup" 
    git config user.email "gitops@localhost"
    git add .
    git commit -m "Applications: Hello World Modern with observability" >/dev/null 2>&1
    git remote add origin http://gitops:gitops123@localhost:30083/gitops/applications.git
    git push --set-upstream origin main >/dev/null 2>&1 && log_success "Applications subida a Git" || log_info "Error subiendo applications"
fi

# Subir configuración ArgoCD (bootstrap)
log_step "Subiendo bootstrap ArgoCD a Git..."
if [[ -d "$DOTFILES_DIR/gitops" ]]; then
    rm -rf "$TEMP_DIR" 2>/dev/null || true
    mkdir -p "$TEMP_DIR"
    cp -r "$DOTFILES_DIR/gitops"/* "$TEMP_DIR/"
    cd "$TEMP_DIR"
    git init -b main >/dev/null 2>&1
    git config user.name "GitOps Setup"
    git config user.email "gitops@localhost" 
    git add .
    git commit -m "Bootstrap: ArgoCD projects + applications + app-of-apps" >/dev/null 2>&1
    git remote add origin http://gitops:gitops123@localhost:30083/gitops/bootstrap.git
    git push --set-upstream origin main >/dev/null 2>&1 && log_success "Bootstrap subida a Git" || log_info "Error subiendo bootstrap"
fi

# --- Configurar ArgoCD para usar repositorios Git ---
log_step "Configurando proyectos y repositorios ArgoCD..."

# Aplicar projects
kubectl apply -f "$DOTFILES_DIR/gitops/projects/" || log_info "Error aplicando projects"

# Aplicar repository secrets  
kubectl apply -f "$DOTFILES_DIR/gitops/repositories/" || log_info "Error aplicando repositories"

# --- Aplicar ArgoCD Applications ---
log_step "Desplegando ArgoCD Applications..."
kubectl apply -f "$DOTFILES_DIR/gitops/applications/" || log_info "Error aplicando applications"

# Limpiar archivos temporales
rm -rf "$TEMP_DIR"

log_success "GitOps configurado - manifests en Git + ArgoCD Applications"

# --- Construir imagen hello-world-modern ---
log_step "Construyendo imagen hello-world-modern..."
cd "$DOTFILES_DIR/source-code/hello-world-modern"
docker build -t hello-world-modern:latest . || log_info "Error construyendo imagen"

log_step "Cargando imagen en cluster kind..."
kind load docker-image hello-world-modern:latest --name mini-cluster || log_info "Error cargando imagen en kind"



# --- Configurar Dashboard con skip-login ---
log_step "Configurando Dashboard con skip-login..."
kubectl create clusterrolebinding kubernetes-dashboard-admin \
    --clusterrole=cluster-admin \
    --serviceaccount=kubernetes-dashboard:kubernetes-dashboard \
    --dry-run=client -o yaml | kubectl apply -f -

# --- Esperar a que los pods estén funcionando ---
log_step "Esperando a que todos los servicios estén listos..."

# Esperar a Dashboard
kubectl wait --for=condition=available --timeout=120s deployment/kubernetes-dashboard -n kubernetes-dashboard 2>/dev/null || log_info "Dashboard aún iniciando"

# Esperar a Prometheus
kubectl wait --for=condition=available --timeout=120s deployment/prometheus -n monitoring 2>/dev/null || log_info "Prometheus aún iniciando"

# Esperar a Grafana
kubectl wait --for=condition=available --timeout=120s deployment/grafana -n monitoring 2>/dev/null || log_info "Grafana aún iniciando"

# Esperar a Hello World
kubectl wait --for=condition=available --timeout=120s deployment/hello-world -n default 2>/dev/null || log_info "Hello World aún iniciando"

log_success "GitOps configurado correctamente con manifests directos"
echo ""
echo "🎉 Ecosistema GitOps completo instalado!"
echo ""
echo "🌐 URLs disponibles:"
echo "   ArgoCD:      http://localhost:30080 (admin/admin123)"
echo "   Gitea:       http://localhost:30083 (para futuros ejercicios)" 
echo "   Dashboard:   https://localhost:30081 (skip login habilitado)"
echo "   Hello World: http://localhost:30082 (con métricas Prometheus)"
echo "   Prometheus:  http://localhost:30092 (métricas del cluster)"
echo "   Grafana:     http://localhost:30093 (admin/admin123)"
echo ""
echo "📊 Verificar estado:"
echo "   kubectl get pods --all-namespaces"
echo "   kubectl get svc --all-namespaces"
echo ""
echo "✨ Entorno educativo GitOps listo para aprender!"