#!/bin/bash

# Script para crear aplicaciones de ArgoCD después de la instalación inicial

echo "🚀 Creando aplicaciones de ArgoCD..."

# Esperar a que ArgoCD esté completamente listo
echo "⏳ Esperando a que ArgoCD esté completamente operativo..."
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

# Crear la aplicación del Dashboard
echo "📊 Creando aplicación del Kubernetes Dashboard..."
kubectl apply -f ~/dotfiles/argocd-apps/dashboard/application.yaml

# Esperar a que la aplicación se sincronice
echo "⏳ Esperando a que el Dashboard se sincronice..."
kubectl wait --for=condition=available --timeout=300s deployment/kubernetes-dashboard-web -n kubernetes-dashboard

echo "✅ Aplicaciones de ArgoCD creadas exitosamente!"
echo ""
echo "� Estado de las aplicaciones:"
kubectl get applications -n argocd
echo ""
echo "🔗 URLs de acceso:"
echo "   ArgoCD: http://localhost:30080 o http://argocd.mini-cluster"
echo "   Dashboard: http://localhost:30081 o http://dashboard.mini-cluster"
echo ""
echo "📝 Para acceder al Dashboard:"
echo "   1. Ve a la URL del Dashboard"
echo "   2. Obtén el token con: kubectl -n kubernetes-dashboard create token kubernetes-dashboard"
echo "   3. Usa el token para iniciar sesión"
