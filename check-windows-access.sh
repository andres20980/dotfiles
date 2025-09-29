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
