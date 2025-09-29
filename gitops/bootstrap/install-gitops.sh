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

DOTFILES_DIR="/home/asanchez/dotfiles"

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
          value: "true"
        - name: GITEA__admin__USERNAME
          value: gitops
        - name: GITEA__admin__PASSWORD
          value: gitops123
        - name: GITEA__admin__EMAIL
          value: gitops@mini-cluster.local
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

# Esperar un poco más para que el setup interno termine
sleep 30

# --- Crear repositorios en Gitea ---
log_step "Creando repositorios en Gitea..."

# Crear repositorio infrastructure
curl -X POST "http://localhost:30083/api/v1/user/repos" \
     -H "Content-Type: application/json" \
     -u "gitops:gitops123" \
     -d '{
       "name": "infrastructure",
       "description": "Infrastructure and observability tools",
       "private": false,
       "default_branch": "master"
     }' || log_info "Repo infrastructure puede ya existir"

# Crear repositorio applications  
curl -X POST "http://localhost:30083/api/v1/user/repos" \
     -H "Content-Type: application/json" \
     -u "gitops:gitops123" \
     -d '{
       "name": "applications", 
       "description": "Business applications and workloads",
       "private": false,
       "default_branch": "master"
     }' || log_info "Repo applications puede ya existir"

# Crear repositorio bootstrap
curl -X POST "http://localhost:30083/api/v1/user/repos" \
     -H "Content-Type: application/json" \
     -u "gitops:gitops123" \
     -d '{
       "name": "bootstrap",
       "description": "ArgoCD bootstrap and app-of-apps",
       "private": false,
       "default_branch": "master"
     }' || log_info "Repo bootstrap puede ya existir"

# --- Construir imagen hello-world-modern ---
log_step "Construyendo imagen hello-world-modern..."
cd "$DOTFILES_DIR/source-code/hello-world-modern"
docker build -t hello-world-modern:latest . || log_info "Error construyendo imagen"

log_step "Cargando imagen en cluster kind..."
kind load docker-image hello-world-modern:latest --name mini-cluster || log_info "Error cargando imagen en kind"

# --- Subir manifests a repositorios ---
log_step "Subiendo manifests a repositorios de Gitea..."

TEMP_DIR="/tmp/gitops-upload"
mkdir -p "$TEMP_DIR"

# Repositorio infrastructure
log_step "Subiendo infrastructure..."
cp -r "$DOTFILES_DIR/manifests/infrastructure"/* "$TEMP_DIR/"
cd "$TEMP_DIR"
rm -rf .git 2>/dev/null || true
find . -name ".git" -type d -exec rm -rf {} + 2>/dev/null || true
git init
git config user.name "GitOps Setup"
git config user.email "gitops@mini-cluster.local"
git add .
git commit -m "Infrastructure: Dashboard + Prometheus + Grafana (ports fixed)"
git remote add origin http://gitops:gitops123@localhost:30083/gitops/infrastructure.git
git push --set-upstream origin master || log_info "Push infrastructure falló"

# Repositorio applications
log_step "Subiendo applications..."
rm -rf "$TEMP_DIR"/* 2>/dev/null || true
cp -r "$DOTFILES_DIR/manifests/applications"/* "$TEMP_DIR/"
cd "$TEMP_DIR"
rm -rf .git 2>/dev/null || true
find . -name ".git" -type d -exec rm -rf {} + 2>/dev/null || true
git init
git config user.name "GitOps Setup" 
git config user.email "gitops@mini-cluster.local"
git add .
git commit -m "Applications: Hello World Modern with observability"
git remote add origin http://gitops:gitops123@localhost:30083/gitops/applications.git
git push --set-upstream origin master || log_info "Push applications falló"

# Repositorio bootstrap
log_step "Subiendo bootstrap..."
rm -rf "$TEMP_DIR"/* 2>/dev/null || true
cp -r "$DOTFILES_DIR/gitops"/* "$TEMP_DIR/"
cd "$TEMP_DIR"
rm -rf .git 2>/dev/null || true
find . -name ".git" -type d -exec rm -rf {} + 2>/dev/null || true
git init
git config user.name "GitOps Setup"
git config user.email "gitops@mini-cluster.local" 
git add .
git commit -m "Bootstrap: ArgoCD projects + applications + app-of-apps"
git remote add origin http://gitops:gitops123@localhost:30083/gitops/bootstrap.git
git push --set-upstream origin master || log_info "Push bootstrap falló"

# --- Configurar ArgoCD ---
log_step "Configurando proyectos y repositorios ArgoCD..."

# Aplicar projects
kubectl apply -f "$DOTFILES_DIR/gitops/projects/"

# Aplicar repository secrets
kubectl apply -f "$DOTFILES_DIR/gitops/repositories/"

# Crear secret para bootstrap repo
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: gitea-bootstrap-repo
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
type: Opaque
stringData:
  type: git
  url: http://gitea.gitea.svc.cluster.local:3000/gitops/bootstrap.git
  username: gitops
  password: gitops123
EOF

# --- Aplicar aplicaciones ---
log_step "Desplegando aplicaciones ArgoCD..."
kubectl apply -f "$DOTFILES_DIR/gitops/applications/"

# --- Configurar Dashboard con skip-login ---
log_step "Configurando Dashboard con skip-login..."
kubectl create clusterrolebinding kubernetes-dashboard-admin \
    --clusterrole=cluster-admin \
    --serviceaccount=kubernetes-dashboard:kubernetes-dashboard \
    --dry-run=client -o yaml | kubectl apply -f -

# --- Limpiar archivos temporales ---
rm -rf "$TEMP_DIR"

# --- Reiniciar ArgoCD para aplicar cambios ---
log_step "Reiniciando ArgoCD..."
kubectl rollout restart deployment/argocd-repo-server -n argocd
kubectl rollout restart deployment/argocd-application-controller -n argocd
kubectl wait --for=condition=available --timeout=120s deployment/argocd-repo-server -n argocd
kubectl wait --for=condition=available --timeout=120s deployment/argocd-application-controller -n argocd

log_success "GitOps configurado correctamente"
echo ""
echo "🎉 GitOps completo instalado!"
echo ""
echo "🌐 URLs disponibles:"
echo "   ArgoCD:     http://localhost:30080 (admin/admin123)"
echo "   Gitea:      http://localhost:30083 (gitops/gitops123)" 
echo "   Dashboard:  https://localhost:30081 (skip login)"
echo "   Hello World: http://localhost:30082"
echo "   Prometheus: http://localhost:30092"  
echo "   Grafana:    http://localhost:30093 (admin/admin123)"
echo ""
echo "📊 Verificar aplicaciones: kubectl get applications -n argocd"