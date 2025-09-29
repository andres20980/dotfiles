#!/bin/bash
# Acceso rápido al Dashboard con skip login
echo "🚀 Abriendo Kubernetes Dashboard..."
echo "💡 En la pantalla de login, haz click en 'SKIP'"
cmd.exe /c start https://$(hostname -I | awk '{print $1}'):30081 2>/dev/null || \
xdg-open https://$(hostname -I | awk '{print $1}'):30081 2>/dev/null || \
echo "🌐 Abre manualmente: https://$(hostname -I | awk '{print $1}'):30081"
