#!/bin/bash

# 🚀 GitOps Bootstrap - Solo lógica GitOps SEGURA
# Instala Gitea + configura repositorios + despliega aplicaciones
# ⚠️  REQUIERE VARIABLES DE ENTORNO PARA CREDENCIALES

set -e

echo "🚀 Configurando GitOps completo (MODO SEGURO)..."
echo "==============================================="

# --- Validar credenciales ---
if [[ -z "$GITEA_ADMIN_PASSWORD" ]]; then
    echo "❌ ERROR: Variable GITEA_ADMIN_PASSWORD no definida"
    echo "💡 Ejecuta primero: source scripts/set-credentials.sh"
    echo "💡 O genera nuevas: scripts/generate-secure-credentials.sh"
    exit 1
fi

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

log_error() {
    echo "❌ ERROR: $1" >&2
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
        -d "user_name=gitops&email=gitops@localhost&password=${GITEA_ADMIN_PASSWORD}&retype=${GITEA_ADMIN_PASSWORD}" \
        >/dev/null 2>&1 || log_info "Usuario puede ya existir"
    
    sleep 5
    
    # Crear repositorios via API
    log_step "Creando repositorios Git..."
    for repo in infrastructure applications bootstrap; do
        echo "📦 Creando repositorio: $repo"
        curl -X POST "http://localhost:30083/api/v1/user/repos" \
            -H "Content-Type: application/json" \
            -u "gitops:${GITEA_ADMIN_PASSWORD}" \
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
        if curl -s -f -u "gitops:${GITEA_ADMIN_PASSWORD}" "http://localhost:30083/api/v1/user" >/dev/null 2>&1; then
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

# --- FLUJO GITOPS PURO: Solo Git -> ArgoCD ---
log_step "🎯 INICIANDO FLUJO GITOPS PURO"

# Verificar que existan los directorios de manifests
if [[ ! -d "$DOTFILES_DIR/manifests" ]]; then
    log_error "No se encontró $DOTFILES_DIR/manifests/"
    exit 1
fi

TEMP_DIR="/tmp/gitops-upload"

# Función robusta para subir a Git con verificación
push_to_git_repo() {
    local repo_name="$1"
    local source_path="$2"
    local commit_message="$3"
    
    log_step "📦 Subiendo $repo_name a Git..."
    
    # Verificar que existe el directorio fuente
    if [[ ! -d "$source_path" ]]; then
        log_error "Directorio fuente no existe: $source_path"
        return 1
    fi
    
    # Limpiar y preparar directorio temporal
    rm -rf "$TEMP_DIR" 2>/dev/null || true
    mkdir -p "$TEMP_DIR"
    
    # Copiar contenido
    cp -r "$source_path"/* "$TEMP_DIR/" 2>/dev/null || {
        log_error "Error copiando contenido desde $source_path"
        return 1
    }
    
    cd "$TEMP_DIR"
    
    # Configurar Git
    git init -b main --quiet
    git config user.name "GitOps Setup"
    git config user.email "gitops@localhost"
    
    # Agregar archivos
    git add .
    if ! git commit -m "$commit_message" --quiet; then
        log_error "Error haciendo commit en $repo_name"
        return 1
    fi
    
    # Configurar remote y push con manejo de errores robusto
    git remote add origin "http://gitops:${GITEA_ADMIN_PASSWORD}@localhost:30083/gitops/$repo_name.git"
    
    # Intentar push con fuerza (necesario por auto_init de Gitea)
    local push_attempts=3
    for attempt in $(seq 1 $push_attempts); do
        log_info "Intento $attempt/$push_attempts: Subiendo $repo_name..."
        if git push --set-upstream origin main --force --quiet; then
            log_success "✅ $repo_name subido correctamente a Git"
            return 0
        fi
        sleep 5
    done
    
    log_error "❌ Error subiendo $repo_name después de $push_attempts intentos"
    return 1
}

# Verificar conectividad con Gitea antes de empezar
log_step "🔍 Verificando conectividad con Gitea..."
for attempt in $(seq 1 10); do
    if curl -s -f -u "gitops:${GITEA_ADMIN_PASSWORD}" "http://localhost:30083/api/v1/user" >/dev/null 2>&1; then
        log_success "✅ Conectividad con Gitea verificada"
        break
    fi
    log_info "Intento $attempt/10: Esperando conectividad con Gitea..."
    sleep 10
done

# PASO 1: Subir infrastructure (CRÍTICO - debe estar ANTES de ArgoCD Apps)
if ! push_to_git_repo "infrastructure" "$DOTFILES_DIR/manifests/infrastructure" "GitOps Infrastructure: Dashboard + Prometheus + Grafana"; then
    log_error "CRÍTICO: Error subiendo infrastructure. Abortando."
    exit 1
fi

# PASO 2: Subir applications (CRÍTICO - debe estar ANTES de ArgoCD Apps)
if ! push_to_git_repo "applications" "$DOTFILES_DIR/manifests/applications" "GitOps Applications: Hello World con métricas"; then
    log_error "CRÍTICO: Error subiendo applications. Abortando."
    exit 1
fi

# PASO 3: Verificar que los repos Git están poblados ANTES de crear Applications
log_step "🔍 Verificando repositorios Git poblados..."
for repo in infrastructure applications; do
    log_info "Verificando contenido de $repo..."
    if ! curl -s -f "http://gitops:${GITEA_ADMIN_PASSWORD}@localhost:30083/gitops/$repo/archive/main.zip" >/dev/null 2>&1; then
        log_error "CRÍTICO: Repositorio $repo no está disponible o vacío"
        exit 1
    fi
    log_success "✅ Repositorio $repo verificado y poblado"
done

# --- PASO 3.5: CONSTRUIR IMAGEN DOCKER (Antes de ArgoCD Applications) ---
log_step "🐳 Construyendo imagen hello-world-modern..."
if [[ ! -d "$DOTFILES_DIR/source-code/hello-world-modern" ]]; then
    log_error "Directorio hello-world-modern no encontrado"
    exit 1
fi

cd "$DOTFILES_DIR/source-code/hello-world-modern"
if ! docker build -t hello-world-modern:latest .; then
    log_error "Error construyendo imagen hello-world-modern"
    exit 1
fi
log_success "✅ Imagen hello-world-modern construida"

log_step "📦 Cargando imagen en cluster kind..."
if ! kind load docker-image hello-world-modern:latest --name mini-cluster; then
    log_error "Error cargando imagen en kind"
    exit 1
fi
log_success "✅ Imagen cargada en cluster kind"

# Volver al directorio base
cd "$DOTFILES_DIR"

# --- PASO 4: CONFIGURAR ARGOCD (Solo después de verificar Git y construir imagen) ---
log_step "🔧 Configurando proyectos ArgoCD..."
if ! kubectl apply -f "$DOTFILES_DIR/gitops/projects/"; then
    log_error "CRÍTICO: Error aplicando projects ArgoCD"
    exit 1
fi

log_step "🔐 Configurando repository secrets ArgoCD (con credenciales seguras)..."
# Procesar template con credenciales del entorno
if ! envsubst < "$DOTFILES_DIR/gitops/repositories/gitea-repos.yaml" | kubectl apply -f -; then
    log_error "CRÍTICO: Error aplicando repository secrets con credenciales seguras"
    exit 1
fi

# --- PASO 5: DESPLEGAR ARGOCD APPLICATIONS (CRÍTICO) ---
log_step "🚀 Desplegando ArgoCD Applications..."
if ! kubectl apply -f "$DOTFILES_DIR/gitops/applications/"; then
    log_error "CRÍTICO: Error aplicando ArgoCD Applications"
    exit 1
fi

# --- PASO 6: VERIFICAR SINCRONIZACIÓN GITOPS ---
log_step "⏳ Esperando sincronización GitOps..."

# Función para verificar sincronización de ArgoCD Application
verify_argocd_sync() {
    local app_name="$1"
    local timeout="$2"
    
    log_info "Verificando sincronización de $app_name..."
    
    for attempt in $(seq 1 "$timeout"); do
        # Verificar que la aplicación existe
        if ! kubectl get application "$app_name" -n argocd >/dev/null 2>&1; then
            log_info "[$attempt/$timeout] Aplicación $app_name no existe aún..."
            sleep 10
            continue
        fi
        
        # Verificar estado de sync y health
        local sync_status
        sync_status=$(kubectl get application "$app_name" -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
        local health_status
        health_status=$(kubectl get application "$app_name" -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
        
        log_info "[$attempt/$timeout] $app_name: Sync=$sync_status, Health=$health_status"
        
        if [[ "$sync_status" == "Synced" && "$health_status" == "Healthy" ]]; then
            log_success "✅ $app_name sincronizada correctamente"
            return 0
        fi
        
        sleep 10
    done
    
    log_error "❌ TIMEOUT: $app_name no se sincronizó en $((timeout * 10)) segundos"
    return 1
}

# Verificar sincronización de cada aplicación crítica
declare -a critical_apps=("kubernetes-dashboard" "prometheus" "grafana" "hello-world" "argo-rollouts")
for app in "${critical_apps[@]}"; do
    if ! verify_argocd_sync "$app" 12; then  # 2 minutos por app
        log_error "CRÍTICO: Aplicación $app falló en sincronizar desde Git"
        # Mostrar detalles del error
        kubectl describe application "$app" -n argocd | tail -20
        exit 1
    fi
done

# Limpiar archivos temporales
rm -rf "$TEMP_DIR"

log_success "🎉 GitOps PURO configurado - Solo Git -> ArgoCD -> Kubernetes"

# --- PASO 7: VERIFICACIÓN FINAL GITOPS ---
log_step "🔍 Verificación final del flujo GitOps..."

# Verificar que todos los namespaces fueron creados por ArgoCD
declare -a expected_namespaces=("monitoring" "kubernetes-dashboard" "argo-rollouts")
for ns in "${expected_namespaces[@]}"; do
    log_info "Verificando namespace $ns creado por ArgoCD..."
    for attempt in $(seq 1 30); do
        if kubectl get namespace "$ns" >/dev/null 2>&1; then
            log_success "✅ Namespace $ns creado por GitOps"
            break
        fi
        log_info "[$attempt/30] Esperando namespace $ns..."
        sleep 10
    done
    
    if ! kubectl get namespace "$ns" >/dev/null 2>&1; then
        log_error "CRÍTICO: Namespace $ns no fue creado por ArgoCD"
        exit 1
    fi
done

# Verificar que todos los deployments fueron creados por ArgoCD
declare -a expected_deployments=(
    "kubernetes-dashboard:kubernetes-dashboard"
    "monitoring:prometheus" 
    "monitoring:grafana"
    "hello-world:hello-world"
    "argo-rollouts:argo-rollouts"
)

for deployment_info in "${expected_deployments[@]}"; do
    IFS=':' read -r namespace deployment <<< "$deployment_info"
    log_info "Verificando deployment $deployment en namespace $namespace..."
    
    for attempt in $(seq 1 30); do
        if kubectl get deployment "$deployment" -n "$namespace" >/dev/null 2>&1; then
            log_success "✅ Deployment $deployment creado por GitOps en $namespace"
            break
        fi
        log_info "[$attempt/30] Esperando deployment $deployment en $namespace..."
        sleep 10
    done
    
    if ! kubectl get deployment "$deployment" -n "$namespace" >/dev/null 2>&1; then
        log_error "CRÍTICO: Deployment $deployment no existe en namespace $namespace"
        exit 1
    fi
done

# Configurar Dashboard RBAC (única excepción permitida)
log_step "🔐 Configurando Dashboard RBAC (post-deployment)..."
kubectl create clusterrolebinding kubernetes-dashboard-admin \
    --clusterrole=cluster-admin \
    --serviceaccount=kubernetes-dashboard:kubernetes-dashboard \
    --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null || log_info "RBAC ya configurado"

log_success "🎯 FLUJO GITOPS PURO COMPLETADO - Solo Git -> ArgoCD -> Kubernetes"
echo ""
echo "🎉 ECOSISTEMA GITOPS PURO INSTALADO! 🎯"
echo ""
echo "✨ FLUJO VERIFICADO: Git -> ArgoCD -> Kubernetes"
echo ""
echo "🌐 URLs disponibles:"
echo "   🚀 ArgoCD:        http://localhost:30080 (admin/[PASSWORD_FROM_ENV])"
echo "   🗃️  Gitea:         http://localhost:30083 (gitops/[PASSWORD_FROM_ENV])" 
echo "   📱 Dashboard:     https://localhost:30081 (skip login habilitado)"
echo "   🎯 Hello World:   http://localhost:30082 (con métricas Prometheus)"
echo "   🔄 Rollouts UI:   http://localhost:30084 (Progressive Delivery)"
echo "   🚀 Canary Demo:   http://localhost:30087 (Hello World Canary)"
echo "   📈 Prometheus:    http://localhost:30092 (métricas del cluster)"
echo "   📊 Grafana:       http://localhost:30093 (admin/[PASSWORD_FROM_ENV])"
echo ""
echo "� Verificar estado GitOps:"
echo "   kubectl get applications -n argocd"
echo "   kubectl get pods --all-namespaces"
echo "   kubectl get svc --all-namespaces"
echo ""
echo "📋 Repositorios Git (fuente de verdad):"
echo "   http://localhost:30083/gitops/infrastructure"
echo "   http://localhost:30083/gitops/applications"
echo ""
echo "✨ Entorno educativo GitOps PURO listo para aprender!"