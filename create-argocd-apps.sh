#!/bin/bash
# Script para crear aplicaciones en ArgoCD para gestionar herramientas

echo "🚀 Creando aplicaciones en ArgoCD..."

# Crear aplicación para el Dashboard de Kubernetes
echo "📊 Creando aplicación para Kubernetes Dashboard..."
kubectl apply -f - <<EOF_APP
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kubernetes-dashboard
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  project: default
  source:
    repoURL: https://github.com/kubernetes/dashboard
    targetRevision: v2.7.0
    path: aio/deploy/recommended.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: kubernetes-dashboard
  syncPolicy:
    automated:
      prune: false
      selfHeal: false
EOF_APP

# Crear aplicación para ArgoCD (esto es meta - ArgoCD gestionándose a sí mismo)
echo "🚢 Creando aplicación para ArgoCD..."
kubectl apply -f - <<EOF_APP
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: argocd-system
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  project: default
  source:
    repoURL: https://github.com/argoproj/argo-cd
    targetRevision: stable
    path: manifests
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: false
      selfHeal: false
EOF_APP

echo "✅ Aplicaciones creadas en ArgoCD"
echo ""
echo "📋 Para ver el estado:"
echo "kubectl get applications -n argocd"
echo ""
echo "🌐 Accede a ArgoCD: http://localhost:30080"
echo "   Usuario: admin (sin contraseña - autenticación deshabilitada)"
