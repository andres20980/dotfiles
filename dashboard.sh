#!/bin/bash
set -euo pipefail
URL="https://localhost:30085"
echo "🚀 Abriendo Kubernetes Dashboard en $URL"
echo "💡 En la pantalla de login, pulsa 'SKIP'"
if command -v cmd.exe >/dev/null 2>&1; then
  cmd.exe /c start "$URL" 2>/dev/null || true
else
  xdg-open "$URL" 2>/dev/null || echo "Dashboard disponible en: $URL"
fi
