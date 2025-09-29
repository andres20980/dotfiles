#!/bin/bash
echo "🚀 Abriendo Kubernetes Dashboard..."
echo "💡 En la pantalla de login, haz click en 'SKIP'"
kubectl proxy --port=8001 &
sleep 3
if command -v cmd.exe >/dev/null 2>&1; then
    cmd.exe /c start http://localhost:8001/api/v1/namespaces/dashboard/services/https:kubernetes-dashboard:/proxy/ 2>/dev/null
else
    echo "Dashboard disponible en: http://localhost:8001/api/v1/namespaces/dashboard/services/https:kubernetes-dashboard:/proxy/"
fi
