#!/bin/bash

# Script para crear aplicaciones de ArgoCD después de la instalación inicial

echo "🚀 Creando aplicaciones de ArgoCD..."

# Esperar a que ArgoCD esté completamente listo
echo "⏳ Esperando a que ArgoCD esté completamente operativo..."
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

# Crear aplicaciones de GitOps Tools
echo "🔧 Creando aplicaciones de GitOps Tools..."

# Kubernetes Dashboard
echo "  📊 Creando aplicación Kubernetes Dashboard..."
kubectl apply -f ~/dotfiles/argo-apps/gitops-tools/dashboard/application.yaml

# Crear aplicaciones Custom
echo "🛠️  Creando aplicaciones Custom..."

# Hello World App
echo "  👋 Creando aplicación Hello World..."
kubectl apply -f ~/dotfiles/argo-apps/custom-apps/hello-world/application.yaml

# Esperar a que las aplicaciones se sincronicen
echo "⏳ Esperando a que las aplicaciones se sincronicen..."

# Esperar Dashboard
echo "  ⏳ Esperando Dashboard..."
kubectl wait --for=condition=available --timeout=300s deployment/kubernetes-dashboard -n kubernetes-dashboard 2>/dev/null || echo "  ⚠️  Dashboard aún sincronizando..."

# Esperar Hello World
echo "  ⏳ Esperando Hello World..."
kubectl wait --for=condition=available --timeout=300s deployment/hello-world -n hello-world 2>/dev/null || echo "  ⚠️  Hello World aún sincronizando..."

echo "✅ Aplicaciones de ArgoCD creadas exitosamente!"
echo ""
echo "📋 Estado de las aplicaciones:"
kubectl get applications -n argocd
echo ""
echo "🔗 URLs de acceso:"
echo "   ArgoCD: http://localhost:30080 o http://argocd.mini-cluster"
echo "   Gitea: http://localhost:30083 o http://gitea.mini-cluster"
echo "   Dashboard: https://localhost:30081 o http://dashboard.mini-cluster"
echo "   Hello World: http://localhost:30082 o http://hello-world.mini-cluster"
echo ""
echo "📝 Para acceder al Dashboard:"
echo "   1. Ve a la URL del Dashboard"
echo "   2. Obtén el token con: kubectl -n kubernetes-dashboard create token kubernetes-dashboard"
echo "   3. Usa el token para iniciar sesión"
echo ""
echo "📝 Para acceder a Gitea:"
echo "   Ve directamente a: http://localhost:30083"
echo "   Usuario: argocd / Contraseña: argocd123"
echo ""
echo "📝 Para acceder a Hello World:"
echo "   Ve directamente a: http://localhost:30082"
