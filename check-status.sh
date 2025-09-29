#!/bin/bash

echo "🔍 Verificando estado del entorno GitOps..."
echo ""

# Verificar cluster
echo "🐳 Cluster Kubernetes:"
kubectl cluster-info --context kind-mini-cluster 2>/dev/null && echo "  ✅ Cluster mini-cluster está activo" || echo "  ❌ Cluster no encontrado"

# Verificar namespaces
echo ""
echo "📦 Namespaces creados:"
for ns in argocd gitea ingress-nginx kubernetes-dashboard hello-world; do
    kubectl get namespace $ns 2>/dev/null && echo "  ✅ $ns" || echo "  ❌ $ns no encontrado"
done

# Verificar ArgoCD
echo ""
echo "🚢 ArgoCD:"
ARGOCD_READY=$(kubectl get deployment argocd-server -n argocd -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
echo "  Server replicas ready: $ARGOCD_READY"
if [[ "$ARGOCD_READY" -gt "0" ]]; then
    echo "  ✅ ArgoCD Server está funcionando"
    echo "  🌐 Acceso: http://localhost:30080"
else
    echo "  ❌ ArgoCD Server no está listo"
fi

# Verificar Gitea
echo ""
echo "📚 Gitea:"
GITEA_READY=$(kubectl get deployment gitea -n gitea -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
echo "  Deployment replicas ready: $GITEA_READY"
if [[ "$GITEA_READY" -gt "0" ]]; then
    echo "  ✅ Gitea está funcionando"
    echo "  🌐 Acceso: http://localhost:30083"
    echo "  👤 Usuario: admin / Contraseña: admin123"
else
    echo "  ❌ Gitea no está listo"
fi

# Verificar aplicaciones de ArgoCD
echo ""
echo "🎯 Aplicaciones ArgoCD:"
if kubectl get applications -n argocd 2>/dev/null | grep -q "dashboard\|hello-world"; then
    echo "  📊 Estado de aplicaciones:"
    kubectl get applications -n argocd -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status 2>/dev/null || echo "  ⏳ Aplicaciones aún inicializando..."
else
    echo "  ⏳ No se encontraron aplicaciones o están inicializando..."
fi

# Verificar servicios NodePort
echo ""
echo "🌐 Servicios expuestos (NodePort):"
kubectl get services --all-namespaces -o wide | grep NodePort | while read line; do
    echo "  🔗 $line"
done

echo ""
echo "💡 Para verificar el estado completo:"
echo "   kubectl get applications -n argocd"
echo "   kubectl get pods --all-namespaces"
echo ""