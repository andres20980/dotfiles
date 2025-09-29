#!/bin/bash

# Script completo para configurar entorno GitOps con ArgoCD + Gitea + Dashboard
# Usa manifests existentes en argo-apps/ y los sube a Gitea

set -e  # Salir si cualquier comando falla

echo "🚀 Empezando la configuración del entorno GitOps completo..."
echo "============================================================="

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
    kubectl wait --for=condition=ready pod -l app=$app -n $namespace --timeout=${timeout}s || \
    kubectl wait --for=condition=ready pod -l k8s-app=$app -n $namespace --timeout=${timeout}s || \
    kubectl wait --for=condition=available deployment/$app -n $namespace --timeout=${timeout}s
}

# --- Actualizar paquetes ---
log_step "Actualizando lista de paquetes..."
sudo apt-get update

# --- Instalar paquetes esenciales ---
log_step "Instalando paquetes esenciales..."
sudo apt-get install -y jq python3-pip zsh htop git curl wget build-essential libice6 ca-certificates apache2-utils unzip

# --- Instalar Oh My Zsh ---
if [ -d "$HOME/.oh-my-zsh" ]; then
    log_success "Oh My Zsh ya está instalado."
else
    log_step "Instalando Oh My Zsh..."
    sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

# --- Instalar plugins de Zsh ---
log_step "Instalando plugins de Zsh..."
ZSH_CUSTOM=${ZSH_CUSTOM:-~/.oh-my-zsh/custom}

if [ ! -d "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting" ]; then
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting
else
    log_success "Plugin zsh-syntax-highlighting ya está instalado."
fi

if [ ! -d "${ZSH_CUSTOM}/plugins/zsh-autosuggestions" ]; then
    git clone https://github.com/zsh-users/zsh-autosuggestions.git ${ZSH_CUSTOM}/plugins/zsh-autosuggestions
else
    log_success "Plugin zsh-autosuggestions ya está instalado."
fi

# --- Instalar Docker ---
log_step "Instalando Docker Engine..."
if ! command -v docker &> /dev/null; then
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo usermod -aG docker $USER
    log_success "Docker instalado correctamente"
else
    log_success "Docker ya está instalado"
fi

# --- Instalar kubectl ---
log_step "Instalando kubectl..."
if ! command -v kubectl &> /dev/null; then
    curl -LO "https://dl.k8s.io/release/v1.34.1/bin/linux/amd64/kubectl"
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm kubectl
    log_success "kubectl instalado correctamente"
else
    log_success "kubectl ya está instalado"
fi

# --- Instalar kind ---
log_step "Instalando kind..."
if ! command -v kind &> /dev/null; then
    curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.23.0/kind-linux-amd64
    sudo install -o root -g root -m 0755 kind /usr/local/bin/kind
    rm kind
    log_success "kind instalado correctamente"
else
    log_success "kind ya está instalado"
fi

# --- Crear cluster kind ---
log_step "Creando cluster kind..."
if ! kind get clusters | grep -q mini-cluster; then
    kind create cluster --name mini-cluster --config ~/dotfiles/kind-config.yaml
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

# Configurar ArgoCD con credenciales admin/admin123
log_step "Configurando credenciales de ArgoCD..."
# Eliminar el secret inicial automático que interfiere con nuestra contraseña personalizada
kubectl delete secret argocd-initial-admin-secret -n argocd 2>/dev/null || true
# Generar hash usando ArgoCD para garantizar compatibilidad
ADMIN_PASSWORD_HASH=$(kubectl exec -n argocd deployment/argocd-server -- argocd account bcrypt --password admin123)
ADMIN_PASSWORD_B64=$(echo -n "$ADMIN_PASSWORD_HASH" | base64 -w 0)
ADMIN_TIME_B64=$(echo -n $(date +%s) | base64 -w 0)
kubectl patch secret argocd-secret -n argocd -p="{\"data\":{\"admin.password\":\"$ADMIN_PASSWORD_B64\",\"admin.passwordMtime\":\"$ADMIN_TIME_B64\"}}" --type=merge

# Configurar servicios como NodePort
log_step "Configurando servicios ArgoCD como NodePort..."
kubectl patch svc argocd-server -n argocd --type='json' -p='[{"op": "replace", "path": "/spec/type", "value": "NodePort"}, {"op": "replace", "path": "/spec/ports/0/nodePort", "value": 30080}, {"op": "replace", "path": "/spec/ports/1/nodePort", "value": 30443}]'

# Configurar ArgoCD para acceso HTTP sin TLS
log_step "Configurando ArgoCD para acceso HTTP sin TLS..."
kubectl patch configmap argocd-cmd-params-cm -n argocd --type merge -p='{"data":{"server.insecure":"true"}}'
kubectl rollout restart deployment argocd-server -n argocd
kubectl rollout status deployment argocd-server -n argocd --timeout=300s

log_success "ArgoCD instalado y configurado (admin/admin123) en puertos 30080/30443"

# --- Instalar NGINX Ingress ---
log_step "Instalando NGINX Ingress Controller..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.0/deploy/static/provider/cloud/deploy.yaml
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=300s
kubectl patch svc ingress-nginx-controller -n ingress-nginx --type='json' -p='[{"op": "replace", "path": "/spec/type", "value": "NodePort"}, {"op": "replace", "path": "/spec/ports/0/nodePort", "value": 30090}]'
log_success "NGINX Ingress instalado en puerto 30090"

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
      containers:
      - name: gitea
        image: gitea/gitea:1.21.11
        ports:
        - containerPort: 3000
        - containerPort: 22
        env:
        - name: GITEA__database__DB_TYPE
          value: sqlite3
        - name: GITEA__database__PATH
          value: /data/gitea/gitea.db
        - name: GITEA__security__INSTALL_LOCK
          value: "true"
        - name: GITEA__service__DISABLE_REGISTRATION
          value: "false"
        - name: GITEA__service__REQUIRE_SIGNIN_VIEW
          value: "false"
        - name: GITEA__webhook__SKIP_TLS_VERIFY
          value: "true"
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
  ports:
  - name: http
    port: 3000
    targetPort: 3000
    nodePort: 30083
  - name: ssh
    port: 22
    targetPort: 22
    nodePort: 30022
  type: NodePort
EOF

wait_for_pods gitea gitea
log_success "Gitea instalado en puerto 30083"

# --- Esperar a que Gitea esté completamente listo ---
log_step "Esperando a que Gitea esté completamente funcional..."
sleep 30

# --- Crear usuario gitops en Gitea ---
log_step "Creando usuario gitops en Gitea..."
# Crear usuario a través de la API REST
CSRF_TOKEN=$(curl -s "http://localhost:30083/user/sign_up" | grep -o 'value="[^"]*"' | head -1 | cut -d'"' -f2)
curl -X POST "http://localhost:30083/user/sign_up" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "_csrf=$CSRF_TOKEN&user_name=gitops&email=gitops%40mini-cluster.local&password=gitops123&retype=gitops123" \
  -L -s > /dev/null || log_info "Usuario gitops ya existe"

log_success "Usuario gitops creado (gitops/gitops123)"

# --- Crear repositorios en Gitea ---
log_step "Creando repositorios en Gitea..."
# Crear repositorios a través de la API REST
curl -X POST "http://gitops:gitops123@localhost:30083/api/v1/user/repos" \
  -H "Content-Type: application/json" \
  -d '{"name": "gitops-tools", "private": false}' -s > /dev/null || true

curl -X POST "http://gitops:gitops123@localhost:30083/api/v1/user/repos" \
  -H "Content-Type: application/json" \
  -d '{"name": "custom-apps", "private": false}' -s > /dev/null || true

# --- Construir imagen Hello World Modern ---
log_step "Construyendo imagen Hello World Modern..."
cd "$HOME/dotfiles/hello-world-modern"
docker build -t hello-world-modern:latest . || log_info "Error construyendo imagen, usando nginx como fallback"

# Cargar imagen en kind
log_step "Cargando imagen en cluster kind..."
kind load docker-image hello-world-modern:latest --name mini-cluster || log_info "Error cargando imagen en kind"

# --- Subir manifests desde argo-apps a Gitea ---
log_step "Subiendo manifests a repositorios de Gitea..."

# Crear directorio temporal
TEMP_DIR="/tmp/gitops-upload"
mkdir -p "$TEMP_DIR"

# Repositorio gitops-tools
log_step "Subiendo gitops-tools..."
cp -r "$HOME/dotfiles/argo-apps/gitops-tools" "$TEMP_DIR/"
cd "$TEMP_DIR/gitops-tools"
rm -rf .git
# Eliminar cualquier directorio .git anidado para evitar submodules
find . -name ".git" -type d -exec rm -rf {} + 2>/dev/null || true
git init
git config user.name "GitOps Setup"
git config user.email "gitops@mini-cluster.local"
git add .
git commit -m "GitOps tools: Dashboard + Prometheus + Grafana with full observability"
git remote add origin http://gitops:gitops123@localhost:30083/gitops/gitops-tools.git
git push --set-upstream origin master || log_info "Push gitops-tools falló"

# Repositorio custom-apps
log_step "Subiendo custom-apps..."
cp -r "$HOME/dotfiles/argo-apps/custom-apps" "$TEMP_DIR/"
cd "$TEMP_DIR/custom-apps"
rm -rf .git
# Eliminar cualquier directorio .git anidado para evitar submodules
find . -name ".git" -type d -exec rm -rf {} + 2>/dev/null || true
git init  
git config user.name "GitOps Setup"
git config user.email "gitops@mini-cluster.local"
git add .
git commit -m "Hello World Modern with Prometheus metrics and observability"
git remote add origin http://gitops:gitops123@localhost:30083/gitops/custom-apps.git
git push --set-upstream origin master || log_info "Push custom-apps falló"

log_success "Repositorios subidos a Gitea"

# --- Crear proyectos y aplicaciones ArgoCD ---
log_step "Creando proyectos ArgoCD..."

kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: gitops-tools
  namespace: argocd
spec:
  description: GitOps tools and infrastructure
  sourceRepos: ['*']
  destinations:
  - namespace: '*'
    server: '*'
  clusterResourceWhitelist:
  - group: '*'
    kind: '*'
---
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: custom-apps
  namespace: argocd
spec:
  description: Custom applications
  sourceRepos: ['*']
  destinations:
  - namespace: '*'
    server: '*'
  clusterResourceWhitelist:
  - group: '*'
    kind: '*'
EOF

# --- Crear secrets para repositorios ---
log_step "Creando secrets de repositorio ArgoCD..."

kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: gitea-repo-gitops-tools
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
type: Opaque
stringData:
  type: git
  url: http://gitea.gitea.svc.cluster.local:3000/gitops/gitops-tools.git
  username: gitops
  password: gitops123
---
apiVersion: v1
kind: Secret
metadata:
  name: gitea-repo-custom-apps
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
type: Opaque
stringData:
  type: git
  url: http://gitea.gitea.svc.cluster.local:3000/gitops/custom-apps.git
  username: gitops
  password: gitops123
EOF

# --- Crear aplicaciones ArgoCD ---
log_step "Creando aplicaciones ArgoCD..."

kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: dashboard
  namespace: argocd
spec:
  project: gitops-tools
  source:
    repoURL: http://gitea.gitea.svc.cluster.local:3000/gitops/gitops-tools.git
    targetRevision: master
    path: dashboard/manifests
  destination:
    server: https://kubernetes.default.svc
    namespace: kubernetes-dashboard
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: hello-world
  namespace: argocd
spec:
  project: custom-apps
  source:
    repoURL: http://gitea.gitea.svc.cluster.local:3000/gitops/custom-apps.git
    targetRevision: master
    path: hello-world/manifests
  destination:
    server: https://kubernetes.default.svc
    namespace: hello-world
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: prometheus
  namespace: argocd
spec:
  project: gitops-tools
  source:
    repoURL: http://gitea.gitea.svc.cluster.local:3000/gitops/gitops-tools.git
    targetRevision: master
    path: prometheus/manifests
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: grafana
  namespace: argocd
spec:
  project: gitops-tools
  source:
    repoURL: http://gitea.gitea.svc.cluster.local:3000/gitops/gitops-tools.git
    targetRevision: master
    path: grafana/manifests
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
EOF

# --- Reiniciar ArgoCD repo-server ---
log_step "Reiniciando ArgoCD repo-server..."
kubectl rollout restart deployment/argocd-repo-server -n argocd
kubectl wait --for=condition=available --timeout=120s deployment/argocd-repo-server -n argocd

# --- Configurar permisos admin para Dashboard (skip-login) ---
log_step "Configurando permisos admin para Dashboard..."
kubectl create clusterrolebinding kubernetes-dashboard-admin \
    --clusterrole=cluster-admin \
    --serviceaccount=kubernetes-dashboard:kubernetes-dashboard \
    --dry-run=client -o yaml | kubectl apply -f -

# --- Crear scripts de acceso automático ---
log_step "Creando scripts de acceso automático..."

# Script de acceso rápido al dashboard
cat > ~/dotfiles/dashboard.sh << 'EOFDASH'
#!/bin/bash
WSL_IP=$(hostname -I | awk '{print $1}')
DASHBOARD_URL="https://$WSL_IP:30081"

echo "🚀 Abriendo Kubernetes Dashboard..."
echo "URL: $DASHBOARD_URL"

if command -v cmd.exe &> /dev/null; then
    cmd.exe /c start "$DASHBOARD_URL"
    echo "✅ Dashboard abierto en Windows"
    echo "💡 Si pide token, haz clic en 'SKIP' para saltarlo"
else
    echo "📋 Ve a: $DASHBOARD_URL"
    echo "💡 Haz clic en 'SKIP' para acceder sin token"
fi
EOFDASH

# Script completo con token automático
cat > ~/dotfiles/open-dashboard.sh << 'EOFOPEN'
#!/bin/bash

WSL_IP=$(hostname -I | awk '{print $1}')
DASHBOARD_URL="https://$WSL_IP:30081"

echo "🚀 Iniciando Dashboard Automático..."

TOKEN=$(kubectl -n kubernetes-dashboard create token admin-user 2>/dev/null)
if [ $? -eq 0 ]; then
    if command -v clip.exe &> /dev/null; then
        echo "$TOKEN" | clip.exe
        echo "✅ Token copiado al clipboard de Windows"
    fi
    
    if command -v cmd.exe &> /dev/null; then
        cmd.exe /c start "$DASHBOARD_URL"
        echo "🌐 Dashboard abierto en Windows"
    fi
    
    echo "🔑 Token: $TOKEN"
    echo "💡 El token está en tu clipboard, solo pégalo en el Dashboard"
else
    echo "❌ Error generando token"
fi
EOFOPEN

# Script de verificación
cat > ~/dotfiles/check-windows-access.sh << 'EOFCHECK'
#!/bin/bash

WSL_IP=$(hostname -I | awk '{print $1}')

echo "🌐 URLs de acceso para Windows:"
echo "=================================="
echo "📍 IP de WSL: $WSL_IP"
echo
echo "🔗 URLs de acceso desde Windows:"
echo "   ArgoCD UI:      http://$WSL_IP:30080"
echo "   Gitea:          http://$WSL_IP:30083"
echo "   Dashboard:      https://$WSL_IP:30081"
echo "   Hello World:    http://$WSL_IP:30082"
echo
echo "📋 Credenciales de acceso:"
echo "   ArgoCD: admin / admin123"
echo "   Gitea:  gitops / gitops123"
echo
echo "🔑 Token de Dashboard:"
kubectl -n kubernetes-dashboard create token admin-user 2>/dev/null || echo "Error generando token"
EOFCHECK

chmod +x ~/dotfiles/dashboard.sh
chmod +x ~/dotfiles/open-dashboard.sh
chmod +x ~/dotfiles/check-windows-access.sh

# Script de prueba de conectividad desde Windows
cat > ~/dotfiles/test-windows-access.sh << 'EOFTEST'
#!/bin/bash
# Script para probar conectividad GitOps desde Windows

echo "🔍 Probando conectividad GitOps desde Windows..."
echo "================================================="

WSL_IP=$(hostname -I | awk '{print $1}')
echo "📍 IP de WSL: $WSL_IP"
echo ""

echo "🌐 Probando URLs con localhost (recomendado para Windows):"
echo -n "   ArgoCD:       http://localhost:30080 -> "
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:30080 --max-time 5 || echo "ERROR"

echo -n "   Dashboard:    https://localhost:30081 -> "
curl -k -s -o /dev/null -w "%{http_code}\n" https://localhost:30081 --max-time 5 || echo "ERROR"

echo -n "   Gitea:        http://localhost:30083 -> "
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:30083 --max-time 5 || echo "ERROR"

echo -n "   Hello World:  http://localhost:30082 -> "
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:30082 --max-time 5 || echo "ERROR"

echo ""
echo "🌐 Probando URLs con IP de WSL:"
echo -n "   ArgoCD:       http://$WSL_IP:30080 -> "
curl -s -o /dev/null -w "%{http_code}\n" http://$WSL_IP:30080 --max-time 5 || echo "ERROR"

echo -n "   Dashboard:    https://$WSL_IP:30081 -> "
curl -k -s -o /dev/null -w "%{http_code}\n" https://$WSL_IP:30081 --max-time 5 || echo "ERROR"

echo -n "   Gitea:        http://$WSL_IP:30083 -> "
curl -s -o /dev/null -w "%{http_code}\n" http://$WSL_IP:30083 --max-time 5 || echo "ERROR"

echo -n "   Hello World:  http://$WSL_IP:30082 -> "
curl -s -o /dev/null -w "%{http_code}\n" http://$WSL_IP:30082 --max-time 5 || echo "ERROR"

echo ""
echo "📝 Instrucciones para Windows:"
echo "   1. Abre tu navegador en Windows"
echo "   2. Usa las URLs con 'localhost' (más compatibles):"
echo "      - ArgoCD:    http://localhost:30080"
echo "      - Dashboard: https://localhost:30081"
echo "      - Gitea:     http://localhost:30083"
echo "   3. Para Dashboard HTTPS:"
echo "      - Acepta el certificado (click 'Avanzado' -> 'Continuar')"
echo "      - En la pantalla de login, haz click en 'SKIP'"
echo ""
echo "🔧 Si no funciona desde Windows:"
echo "   - Verifica que Windows Firewall permita las conexiones"
echo "   - Asegúrate de que Docker Desktop está ejecutándose"
echo "   - Prueba con las URLs de IP: $WSL_IP:PUERTO"
EOFTEST

chmod +x ~/dotfiles/test-windows-access.sh

# --- Crear aliases ---
cat > ~/dotfiles/.gitops_aliases << 'EOFALIAS'
# Aliases para GitOps Dashboard
alias dashboard='cd /home/asanchez/dotfiles && ./dashboard.sh'
alias dashboard-full='cd /home/asanchez/dotfiles && ./open-dashboard.sh'
alias k8s-dash='cd /home/asanchez/dotfiles && ./dashboard.sh'

# Aliases para otros servicios GitOps
alias argocd='cmd.exe /c start http://$(hostname -I | awk "{print \$1}"):30080'
alias gitea='cmd.exe /c start http://$(hostname -I | awk "{print \$1}"):30083'

echo "🚀 Aliases de GitOps cargados:"
echo "   dashboard      - Abre Dashboard (skip login)"
echo "   dashboard-full - Abre Dashboard con token automático"  
echo "   k8s-dash       - Alias corto para dashboard"
echo "   argocd         - Abre ArgoCD UI"
echo "   gitea          - Abre Gitea UI"
EOFALIAS

# Agregar aliases al .zshrc si no están ya
if ! grep -q "GitOps aliases" ~/.zshrc; then
    echo "" >> ~/.zshrc
    echo "# GitOps aliases" >> ~/.zshrc
    echo "source /home/asanchez/dotfiles/.gitops_aliases" >> ~/.zshrc
fi

# --- Esperar a que las aplicaciones se sincronicen ---
log_step "Esperando a que ArgoCD sincronice las aplicaciones..."
sleep 30

# Forzar sincronización
kubectl patch application dashboard -n argocd --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' || true
kubectl patch application hello-world -n argocd --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' || true

sleep 20

# --- Limpiar archivos temporales ---
rm -rf "$TEMP_DIR"

# --- Verificar estado final ---
log_step "Verificando estado final del sistema..."

echo ""
echo "🎉 ¡INSTALACIÓN COMPLETADA!"
echo "=============================================="
echo ""
echo "📊 Estado de las aplicaciones ArgoCD:"
kubectl get applications -n argocd 2>/dev/null || echo "Error obteniendo aplicaciones"
echo ""
echo "🌐 URLs de acceso:"
WSL_IP=$(hostname -I | awk '{print $1}')
echo "   📍 Desde WSL/Linux:"
echo "      ArgoCD:       http://$WSL_IP:30080 (admin/admin123)"
echo "      Gitea:        http://$WSL_IP:30083 (gitops/gitops123)"
echo "      Dashboard:    https://$WSL_IP:30081 (SKIP login habilitado)"
echo "      Hello World:  http://$WSL_IP:30082 (con métricas)"
echo "      Prometheus:   http://$WSL_IP:30090 (métricas y alertas)"
echo "      Grafana:      http://$WSL_IP:30091 (dashboards, admin/admin123)"
echo ""
echo "   🪟 Desde Windows:"
echo "      ArgoCD:       http://localhost:30080 (admin/admin123)"
echo "      Gitea:        http://localhost:30083 (gitops/gitops123)"
echo "      Dashboard:    https://localhost:30081 (SKIP login habilitado)"
echo "      Hello World:  http://localhost:30082 (con métricas)"
echo "      Prometheus:   http://localhost:30090 (métricas y alertas)"
echo "      Grafana:      http://localhost:30091 (dashboards, admin/admin123)"
echo ""
echo "🚀 Comandos de acceso rápido:"
echo "   dashboard       - Abre Dashboard con skip login"
echo "   dashboard-full  - Abre Dashboard con token automático"
echo "   argocd          - Abre ArgoCD"
echo "   gitea           - Abre Gitea"
echo ""
echo "📜 Scripts disponibles:"
echo "   ./dashboard.sh             - Acceso rápido al Dashboard"
echo "   ./open-dashboard.sh        - Dashboard con token automático"  
echo "   ./check-windows-access.sh  - Verificar URLs y generar token"
echo "   ./test-windows-access.sh   - Probar conectividad desde Windows"
echo ""
echo "💡 IMPORTANTE:"
echo "   - Reinicia tu terminal para cargar los aliases"
echo "   - El Dashboard permite 'SKIP' login para acceso rápido"
echo "   - Todas las aplicaciones deberían mostrar 'Synced & Healthy'"
echo ""
echo "🪟 Para acceso desde Windows:"
echo "   - Ejecuta: ./test-windows-access.sh (probar conectividad)"
echo "   - Usa URLs con 'localhost' para mejor compatibilidad"
echo "   - Dashboard HTTPS: Acepta certificado y haz click en 'SKIP'"
echo ""
log_success "Entorno GitOps completamente configurado y listo para usar"