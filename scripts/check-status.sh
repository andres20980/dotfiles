#!/bin/bash
# Verificador de estado del sistema
echo "🔍 Estado del entorno GitOps"
echo "============================"
echo ""
echo "🏗️ Cluster:"
kubectl cluster-info --context kind-mini-cluster 2>/dev/null && echo "  ✅ Activo" || echo "  ❌ Inactivo"
echo ""
echo "📊 Aplicaciones ArgoCD:"
kubectl get applications -n argocd 2>/dev/null || echo "  ❌ Error obteniendo aplicaciones"
echo ""
echo "🌐 Servicios expuestos:"
kubectl get services --all-namespaces | grep NodePort
echo ""
WSL_IP=$(hostname -I | awk '{print $1}')
echo "🔗 URLs de acceso:"
echo "   ArgoCD:     http://$WSL_IP:30080"
echo "   Gitea:      http://$WSL_IP:30083"  
echo "   Dashboard:  https://$WSL_IP:30081"
echo "   Hello World: http://$WSL_IP:30082"
echo "   Prometheus: http://$WSL_IP:30092"
echo "   Grafana:    http://$WSL_IP:30093"
