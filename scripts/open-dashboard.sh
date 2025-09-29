#!/bin/bash
# Dashboard con token automático
echo "🔑 Generando token de Dashboard..."
TOKEN=$(kubectl -n kubernetes-dashboard create token admin-user 2>/dev/null || echo "ERROR")
if [ "$TOKEN" != "ERROR" ]; then
    echo "$TOKEN" | clip.exe 2>/dev/null || echo "$TOKEN" | xclip -selection clipboard 2>/dev/null || echo "Token: $TOKEN"
    echo "✅ Token copiado al portapapeles"
fi
echo "🚀 Abriendo Dashboard..."
cmd.exe /c start https://$(hostname -I | awk '{print $1}'):30081
