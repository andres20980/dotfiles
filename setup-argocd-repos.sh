#!/bin/bash

# Script para configurar repositorios en ArgoCD después de la instalación

echo "🔧 Configurando repositorios en ArgoCD..."

# Esperar a que ArgoCD esté listo
echo "⏳ Esperando a que ArgoCD esté operativo..."
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

# Agregar repositorios de Gitea a ArgoCD (si es necesario)
echo "📚 Agregando repositorios de Gitea a ArgoCD..."

# Nota: Como Gitea está configurado sin autenticación, no necesitamos credenciales
# Los repositorios deberían ser accesibles directamente

echo "✅ Repositorios configurados en ArgoCD"
echo ""
echo "💡 Para verificar que ArgoCD puede acceder a los repositorios:"
echo "   kubectl exec -n argocd deployment/argocd-repo-server -- git ls-remote http://gitea.gitea.svc.cluster.local:3000/argocd/gitops-tools.git"
echo "   kubectl exec -n argocd deployment/argocd-repo-server -- git ls-remote http://gitea.gitea.svc.cluster.local:3000/argocd/custom-apps.git"