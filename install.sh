#!/bin/bash

# Script para configurar un nuevo entorno de desarrollo en Ubuntu

echo "🚀 Empezando la configuración..."

# --- Actualizar paquetes ---
echo "🔄 Actualizando lista de paquetes..."
sudo apt-get update

# --- Instalar paquetes esenciales con APT ---
echo "📦 Instalando paquetes esenciales (jq, pip, zsh, htop...)"
sudo apt-get install -y jq python3-pip zsh htop git curl wget build-essential libice6

# --- Instalar Oh My Zsh ---
if [ -d "$HOME/.oh-my-zsh" ]; then
    echo "✅ Oh My Zsh ya está instalado."
else
    echo "💤 Instalando Oh My Zsh..."
    sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

# --- Instalar plugins de Zsh ---
echo "🔌 Instalando plugins de Zsh..."
ZSH_CUSTOM=${ZSH_CUSTOM:-~/.oh-my-zsh/custom}

# Comprobar si el directorio del plugin ya existe
if [ ! -d "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting" ]; then
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting
else
    echo "✅ Plugin zsh-syntax-highlighting ya está instalado."
fi

if [ ! -d "${ZSH_CUSTOM}/plugins/zsh-autosuggestions" ]; then
    git clone https://github.com/zsh-users/zsh-autosuggestions.git ${ZSH_CUSTOM}/plugins/zsh-autosuggestions
else
    echo "✅ Plugin zsh-autosuggestions ya está instalado."
fi

# --- Instalar NVM ---
if [ -d "$HOME/.nvm" ]; then
    echo "✅ nvm ya está instalado."
else
    echo "📦 Instalando nvm (Node Version Manager)..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
fi

# --- Instalar Git Credential Manager (GCM) ---
echo "📦 Instalando Git Credential Manager..."
# Descargar el paquete
wget https://github.com/git-ecosystem/git-credential-manager/releases/download/v2.5.1/gcm-linux_amd64.2.5.1.deb -O /tmp/gcm.deb
# Instalar el paquete (requiere sudo)
sudo dpkg -i /tmp/gcm.deb
# Configurar Git para usar GCM y el almacén de texto plano
echo "🔧 Configurando Git para usar GCM..."
git config --global credential.helper manager
git config --global credential.credentialStore plaintext

# --- Instalar Herramientas Cloud Native (Docker, kubectl, kind) ---
echo "📦 Instalando herramientas Cloud Native..."

# Instalar Docker Engine
echo "    - Instalando Docker Engine..."
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Instalar kubectl (usando la versión que sabemos es estable)
echo "    - Instalando kubectl..."
curl -LO "https://dl.k8s.io/release/v1.34.1/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl

# Instalar kind
echo "    - Instalando kind..."
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.23.0/kind-linux-amd64
sudo install -o root -g root -m 0755 kind /usr/local/bin/kind
rm kind

# Crear cluster kind con configuración para acceso desde Windows
echo "    - Creando cluster kind con configuración especial..."
kind create cluster --name mini-cluster --config ~/dotfiles/kind-config.yaml
echo "    ✅ Cluster kind creado y configurado"

# --- Instalar y configurar ArgoCD ---
echo "🚢 Instalando y configurando ArgoCD..."
# 1. Instalar ArgoCD usando el manifiesto oficial
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
# 2. Esperar a que los pods estén listos
echo "    - Esperando a que ArgoCD esté listo..."
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
# 3. Configurar ArgoCD para funcionar sin autenticación (modo inseguro)
echo "    - Configurando ArgoCD sin autenticación..."
kubectl patch configmap argocd-cmd-params-cm -n argocd --type merge -p '{"data":{"server.insecure":"true","server.disable.auth":"true"}}'
# 4. Reiniciar el deployment para aplicar los cambios
kubectl rollout restart deployment argocd-server -n argocd
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
# 5. Cambiar servicios a NodePort para acceso directo sin port-forwarding
echo "    - Configurando servicios como NodePort para acceso directo..."
kubectl patch svc argocd-server -n argocd --type='json' -p='[{"op": "replace", "path": "/spec/type", "value": "NodePort"}, {"op": "replace", "path": "/spec/ports/0/nodePort", "value": 30080}, {"op": "replace", "path": "/spec/ports/1/nodePort", "value": 30443}]'
echo "    ✅ Servicios expuestos en localhost: ArgoCD (http:30080, https:30443)"
# 6. Configurar dominios personalizados en /etc/hosts
echo "    - Configurando dominios personalizados en /etc/hosts..."
KIND_IP=$(docker inspect mini-cluster-control-plane | grep '"IPAddress":' | grep -v null | head -1 | cut -d'"' -f4)
if [ -n "$KIND_IP" ]; then
    echo "# Kubernetes kind cluster services" | sudo tee -a /etc/hosts > /dev/null
    echo "$KIND_IP argocd.mini-cluster" | sudo tee -a /etc/hosts > /dev/null
    echo "$KIND_IP dashboard.mini-cluster" | sudo tee -a /etc/hosts > /dev/null
    echo "$KIND_IP hello-world.mini-cluster" | sudo tee -a /etc/hosts > /dev/null
    echo "$KIND_IP gitea.mini-cluster" | sudo tee -a /etc/hosts > /dev/null
    echo "    ✅ Dominios configurados: argocd.mini-cluster, dashboard.mini-cluster, hello-world.mini-cluster, gitea.mini-cluster"
else
    echo "    ⚠️  No se pudo detectar la IP del contenedor kind. Configura manualmente /etc/hosts"
fi
echo "    ✅ ArgoCD instalado y configurado sin autenticación"

# --- Crear proyectos de ArgoCD ---
echo "📋 Creando proyectos de ArgoCD..."
kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: gitops-tools
  namespace: argocd
spec:
  description: GitOps tools and infrastructure components
  sourceRepos:
  - '*'
  destinations:
  - namespace: '*'
    server: '*'
  clusterResourceWhitelist:
  - group: '*'
    kind: '*'
EOF

kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: custom-apps
  namespace: argocd
spec:
  description: Custom applications managed by ArgoCD
  sourceRepos:
  - '*'
  destinations:
  - namespace: '*'
    server: '*'
  clusterResourceWhitelist:
  - group: '*'
    kind: '*'
EOF
echo "    ✅ Proyectos de ArgoCD creados"

# --- Instalar NGINX Ingress Controller ---
echo "🌐 Instalando NGINX Ingress Controller..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.0/deploy/static/provider/cloud/deploy.yaml
echo "    - Esperando a que NGINX Ingress esté listo..."
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=300s
# Cambiar el servicio a NodePort para acceso directo
kubectl patch svc ingress-nginx-controller -n ingress-nginx --type='json' -p='[{"op": "replace", "path": "/spec/type", "value": "NodePort"}, {"op": "replace", "path": "/spec/ports/0/nodePort", "value": 30090}]'
echo "    ✅ NGINX Ingress Controller instalado y configurado como NodePort en puerto 30090"

# --- Instalar y configurar Gitea (repositorio Git local) ---
echo "📚 Instalando y configurando Gitea..."
# 1. Crear namespace para Gitea
kubectl create namespace gitea --dry-run=client -o yaml | kubectl apply -f -
# 2. Instalar Gitea usando configuración ligera
echo "    - Instalando Gitea con configuración mínima..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: gitea-data
  namespace: gitea
spec:
  accessModes:
    - ReadWriteOnce
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
          name: http
        - containerPort: 22
          name: ssh
        env:
        - name: GITEA__database__DB_TYPE
          value: sqlite3
        - name: GITEA__database__PATH
          value: /data/gitea/gitea.db
        - name: GITEA__security__INSTALL_LOCK
          value: "true"
        - name: GITEA__service__DISABLE_REGISTRATION
          value: "true"
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

# 3. Esperar a que Gitea esté listo
echo "    - Esperando a que Gitea esté listo..."
kubectl wait --for=condition=available --timeout=300s deployment/gitea -n gitea

# 4. Inicializar repositorios en Gitea
echo "    - Inicializando repositorios en Gitea..."
# Crear usuario argocd y repositorios
kubectl exec -n gitea deployment/gitea -- sh -c "
  # Esperar a que Gitea esté completamente inicializado
  sleep 10
  
  # Crear usuario argocd
  curl -X POST 'http://localhost:3000/api/v1/admin/users' \
    -H 'Content-Type: application/json' \
    -d '{
      \"username\": \"argocd\",
      \"email\": \"argocd@local\",
      \"password\": \"argocd123\",
      \"must_change_password\": false
    }' 2>/dev/null || echo 'Usuario ya existe o error en creación'
  
  # Crear repositorio gitops-tools
  curl -X POST 'http://localhost:3000/api/v1/user/repos' \
    -H 'Content-Type: application/json' \
    -u 'argocd:argocd123' \
    -d '{
      \"name\": \"gitops-tools\",
      \"description\": \"GitOps tools and infrastructure components\",
      \"private\": false
    }' 2>/dev/null || echo 'Repositorio gitops-tools ya existe'
  
  # Crear repositorio custom-apps
  curl -X POST 'http://localhost:3000/api/v1/user/repos' \
    -H 'Content-Type: application/json' \
    -u 'argocd:argocd123' \
    -d '{
      \"name\": \"custom-apps\",
      \"description\": \"Custom applications managed by ArgoCD\",
      \"private\": false
    }' 2>/dev/null || echo 'Repositorio custom-apps ya existe'
"

# 5. Configurar repositorios locales para usar Gitea
echo "    - Configurando repositorios locales para Gitea..."
cd ~/dotfiles/argo-apps/gitops-tools
if ! git remote get-url origin >/dev/null 2>&1; then
    git remote add origin http://localhost:30083/argocd/gitops-tools.git
fi
git push -u origin main || echo "Error al hacer push (posiblemente ya existe)"

cd ~/dotfiles/argo-apps/custom-apps
if ! git remote get-url origin >/dev/null 2>&1; then
    git remote add origin http://localhost:30083/argocd/custom-apps.git
fi
git push -u origin main || echo "Error al hacer push (posiblemente ya existe)"

echo "    ✅ Gitea instalado y configurado (SQLite, sin autenticación)"

# --- Crear repositorios y estructura de directorios ---
echo "📁 Creando repositorios y estructura de directorios..."
# 1. Crear directorios para los repositorios
mkdir -p ~/dotfiles/argo-apps/gitops-tools/dashboard/manifests
mkdir -p ~/dotfiles/argo-apps/custom-apps/hello-world/manifests

# 2. Inicializar repositorio Git para gitops-tools
echo "    - Inicializando repositorio gitops-tools..."
cd ~/dotfiles/argo-apps/gitops-tools
if [ ! -d ".git" ]; then
    git init
    git config user.name "ArgoCD Bot"
    git config user.email "argocd@local"
fi

# 3. Inicializar repositorio Git para custom-apps
echo "    - Inicializando repositorio custom-apps..."
cd ~/dotfiles/argo-apps/custom-apps
if [ ! -d ".git" ]; then
    git init
    git config user.name "ArgoCD Bot"
    git config user.email "argocd@local"
fi

# 4. Crear namespaces para las aplicaciones
echo "    - Creando namespaces..."
kubectl create namespace kubernetes-dashboard --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace hello-world --dry-run=client -o yaml | kubectl apply -f -

# 5. Crear manifiestos básicos
echo "    - Creando manifiestos básicos..."

# Dashboard manifests
cat > ~/dotfiles/argo-apps/gitops-tools/dashboard/manifests/deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kubernetes-dashboard
  namespace: kubernetes-dashboard
  labels:
    app: kubernetes-dashboard
spec:
  replicas: 1
  selector:
    matchLabels:
      app: kubernetes-dashboard
  template:
    metadata:
      labels:
        app: kubernetes-dashboard
    spec:
      serviceAccountName: kubernetes-dashboard
      containers:
      - name: kubernetes-dashboard
        image: kubernetesui/dashboard:v2.7.0
        ports:
        - containerPort: 8443
          protocol: TCP
        args:
          - --auto-generate-certificates
          - --namespace=kubernetes-dashboard
        volumeMounts:
        - name: kubernetes-dashboard-certs
          mountPath: /certs
        - name: tmp-volume
          mountPath: /tmp
      volumes:
      - name: kubernetes-dashboard-certs
        secret:
          secretName: kubernetes-dashboard-certs
      - name: tmp-volume
        emptyDir: {}
EOF

cat > ~/dotfiles/argo-apps/gitops-tools/dashboard/manifests/service.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: kubernetes-dashboard
  namespace: kubernetes-dashboard
spec:
  selector:
    app: kubernetes-dashboard
  ports:
  - port: 443
    targetPort: 8443
    nodePort: 30081
  type: NodePort
EOF

cat > ~/dotfiles/argo-apps/gitops-tools/dashboard/manifests/rbac.yaml << 'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: kubernetes-dashboard
  namespace: kubernetes-dashboard
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: kubernetes-dashboard
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: kubernetes-dashboard
  namespace: kubernetes-dashboard
EOF

cat > ~/dotfiles/argo-apps/gitops-tools/dashboard/manifests/ingress.yaml << 'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: kubernetes-dashboard
  namespace: kubernetes-dashboard
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - host: dashboard.mini-cluster
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: kubernetes-dashboard
            port:
              number: 443
EOF

# Hello World manifests
cat > ~/dotfiles/argo-apps/custom-apps/hello-world/manifests/deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello-world
  namespace: hello-world
  labels:
    app: hello-world
spec:
  replicas: 1
  selector:
    matchLabels:
      app: hello-world
  template:
    metadata:
      labels:
        app: hello-world
    spec:
      containers:
      - name: hello-world
        image: nginx:alpine
        ports:
        - containerPort: 80
        volumeMounts:
        - name: html
          mountPath: /usr/share/nginx/html
      volumes:
      - name: html
        configMap:
          name: hello-world-html
EOF

cat > ~/dotfiles/argo-apps/custom-apps/hello-world/manifests/service.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: hello-world
  namespace: hello-world
spec:
  selector:
    app: hello-world
  ports:
  - port: 80
    targetPort: 80
    nodePort: 30082
  type: NodePort
EOF

cat > ~/dotfiles/argo-apps/custom-apps/hello-world/manifests/configmap.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: hello-world-html
  namespace: hello-world
data:
  index.html: |
    <!DOCTYPE html>
    <html>
    <head>
        <title>Hello World - ArgoCD</title>
        <style>
            body { font-family: Arial, sans-serif; text-align: center; padding: 50px; }
            h1 { color: #4CAF50; }
        </style>
    </head>
    <body>
        <h1>🚀 Hello World!</h1>
        <p>Esta aplicación está siendo gestionada por ArgoCD desde un repositorio Gitea local.</p>
        <p><strong>Estado:</strong> <span style="color: green;">Synced & Healthy</span></p>
    </body>
    </html>
EOF

cat > ~/dotfiles/argo-apps/custom-apps/hello-world/manifests/ingress.yaml << 'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: hello-world
  namespace: hello-world
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
spec:
  ingressClassName: nginx
  rules:
  - host: hello-world.mini-cluster
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: hello-world
            port:
              number: 80
EOF

# 5. Crear archivos application.yaml para ArgoCD
echo "    - Creando archivos application.yaml para ArgoCD..."

cat > ~/dotfiles/argo-apps/gitops-tools/dashboard/application.yaml << 'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: dashboard
  namespace: argocd
spec:
  project: gitops-tools
  source:
    repoURL: http://gitea.mini-cluster/argocd/gitops-tools
    targetRevision: HEAD
    path: dashboard/manifests
  destination:
    server: https://kubernetes.default.svc
    namespace: kubernetes-dashboard
EOF

cat > ~/dotfiles/argo-apps/custom-apps/hello-world/application.yaml << 'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: hello-world
  namespace: argocd
spec:
  project: custom-apps
  source:
    repoURL: http://gitea.mini-cluster/argocd/custom-apps
    targetRevision: HEAD
    path: hello-world/manifests
  destination:
    server: https://kubernetes.default.svc
    namespace: hello-world
EOF

# 6. Hacer commit de los manifiestos
echo "    - Haciendo commit de los manifiestos..."
cd ~/dotfiles/argo-apps/gitops-tools
git add .
git commit -m "Initial commit: Kubernetes Dashboard manifests" || echo "No changes to commit or already committed"

cd ~/dotfiles/argo-apps/custom-apps
git add .
git commit -m "Initial commit: Hello World app manifests" || echo "No changes to commit or already committed"

# 7. Aplicar aplicaciones en ArgoCD
echo "    - Aplicando aplicaciones en ArgoCD..."
kubectl apply -f ~/dotfiles/argo-apps/gitops-tools/dashboard/application.yaml
kubectl apply -f ~/dotfiles/argo-apps/custom-apps/hello-world/application.yaml
echo "    - Esperando a que las aplicaciones se sincronicen..."
sleep 30  # Dar tiempo para que ArgoCD procese
kubectl get applications -n argocd

echo "    ✅ Repositorios creados, manifiestos inicializados y aplicaciones aplicadas"

echo "
✅ ¡Configuración completada!"
echo "NOTA: Cierra y vuelve a abrir tu terminal para que todos los cambios surtan efecto."
echo ""
echo "🔗 Servicios disponibles:"
echo "   ArgoCD: http://localhost:30080 o http://argocd.mini-cluster"
echo "   Gitea: http://localhost:30083 o http://gitea.mini-cluster"
echo "   NGINX Ingress: http://localhost:30090"
echo "   Dashboard: https://dashboard.mini-cluster (via ingress)"
echo "   Hello World: http://hello-world.mini-cluster (via ingress)"
echo ""
echo "📚 Repositorios Gitea:"
echo "   GitOps Tools: http://gitea.mini-cluster/argocd/gitops-tools"
echo "   Custom Apps: http://gitea.mini-cluster/argocd/custom-apps"
