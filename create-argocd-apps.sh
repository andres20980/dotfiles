#!/bin/bash

# Script para crear aplicaciones de ArgoCD después de la instalación inicial

echo "🚀 Creando aplicaciones de ArgoCD..."

# Esperar a que ArgoCD esté completamente listo
echo "⏳ Esperando a que ArgoCD esté completamente operativo..."
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

# Crear aplicaciones de GitOps Tools
echo "🔧 Creando aplicaciones de GitOps Tools..."

# Kubernetes Dashboard (instalado directamente para desarrollo local)
echo "  📊 Instalando Kubernetes Dashboard..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml >/dev/null 2>&1
kubectl patch svc kubernetes-dashboard -n kubernetes-dashboard --type='json' -p='[{"op": "replace", "path": "/spec/type", "value": "NodePort"}, {"op": "replace", "path": "/spec/ports/0/nodePort", "value": 30081}]' >/dev/null 2>&1

# Esperar Dashboard
echo "  ⏳ Esperando Dashboard..."
kubectl wait --for=condition=available --timeout=60s deployment/kubernetes-dashboard -n kubernetes-dashboard 2>/dev/null || echo "  ⚠️  Dashboard aún iniciando..."

# Crear aplicaciones Custom
echo "🛠️  Creando aplicaciones Custom..."

# Hello World App (aplicada directamente con kubectl para desarrollo local)
echo "  👋 Creando Hello World App (desarrollo local)..."
kubectl apply -f ~/dotfiles/argocd-apps/custom-apps/hello-world/manifests/

# Esperar a que las aplicaciones se sincronicen
echo "⏳ Esperando a que las aplicaciones se sincronicen..."

# Esperar Dashboard
echo "  ⏳ Esperando Dashboard..."
kubectl wait --for=condition=available --timeout=300s deployment/kubernetes-dashboard-web -n kubernetes-dashboard 2>/dev/null || echo "  ⚠️  Dashboard aún sincronizando..."

# Esperar Hello World
echo "  ⏳ Esperando Hello World..."
kubectl wait --for=condition=available --timeout=300s deployment/hello-world -n hello-world 2>/dev/null || echo "  ⚠️  Hello World aún sincronizando..."

echo "✅ Aplicaciones de ArgoCD creadas exitosamente!"
echo ""
echo "📋 Estado de las aplicaciones de ArgoCD:"
kubectl get applications -n argocd 2>/dev/null || echo "  No hay aplicaciones de ArgoCD"
echo ""
echo "📋 Estado de las aplicaciones Custom (desarrollo local):"
echo "  Dashboard: $(kubectl get deployment kubernetes-dashboard -n kubernetes-dashboard -o jsonpath='{.status.readyReplicas}/{.status.replicas}' 2>/dev/null || echo 'N/A') pods ready"
echo "  Hello World: $(kubectl get deployment hello-world -n hello-world -o jsonpath='{.status.readyReplicas}/{.status.replicas}' 2>/dev/null || echo 'N/A') pods ready"
echo ""
echo "🔗 URLs de acceso:"
echo "   ArgoCD: http://localhost:30080 o http://argocd.mini-cluster"
echo "   Dashboard: http://localhost:30081 o http://dashboard.mini-cluster"
echo "   Hello World: http://localhost:30082 o http://hello-world.mini-cluster"
echo ""
echo "📝 Para acceder al Dashboard:"
echo "   1. Ve a la URL del Dashboard"
echo "   2. Obtén el token con: kubectl -n kubernetes-dashboard create token kubernetes-dashboard"
echo "   3. Usa el token para iniciar sesión"
echo ""
echo "📝 Para acceder a Hello World:"
echo "   Ve directamente a: http://localhost:30082"
