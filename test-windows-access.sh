#!/bin/bash
# Script para probar conectividad GitOps desde Windows

echo "🔍 Probando conectividad GitOps desde Windows..."
echo "================================================="

WSL_IP=$(hostname -I | awk '{print $1}')
echo "📍 IP de WSL: $WSL_IP"
echo ""

echo "🌐 Probando URLs con localhost (recomendado para Windows):"
echo -n "   ArgoCD:       http://localhost:30080 -> "
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:30080 --max-time 5 || echo "ERROR"

echo -n "   Dashboard:    https://localhost:30081 -> "
curl -k -s -o /dev/null -w "%{http_code}\n" https://localhost:30081 --max-time 5 || echo "ERROR"

echo -n "   Gitea:        http://localhost:30083 -> "
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:30083 --max-time 5 || echo "ERROR"

echo -n "   Hello World:  http://localhost:30082 -> "
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:30082 --max-time 5 || echo "ERROR"

echo ""
echo "🌐 Probando URLs con IP de WSL:"
echo -n "   ArgoCD:       http://$WSL_IP:30080 -> "
curl -s -o /dev/null -w "%{http_code}\n" http://$WSL_IP:30080 --max-time 5 || echo "ERROR"

echo -n "   Dashboard:    https://$WSL_IP:30081 -> "
curl -k -s -o /dev/null -w "%{http_code}\n" https://$WSL_IP:30081 --max-time 5 || echo "ERROR"

echo -n "   Gitea:        http://$WSL_IP:30083 -> "
curl -s -o /dev/null -w "%{http_code}\n" http://$WSL_IP:30083 --max-time 5 || echo "ERROR"

echo -n "   Hello World:  http://$WSL_IP:30082 -> "
curl -s -o /dev/null -w "%{http_code}\n" http://$WSL_IP:30082 --max-time 5 || echo "ERROR"

echo ""
echo "📝 Instrucciones para Windows:"
echo "   1. Abre tu navegador en Windows"
echo "   2. Usa las URLs con 'localhost' (más compatibles):"
echo "      - ArgoCD:    http://localhost:30080"
echo "      - Dashboard: https://localhost:30081"
echo "      - Gitea:     http://localhost:30083"
echo "   3. Para Dashboard HTTPS:"
echo "      - Acepta el certificado (click 'Avanzado' -> 'Continuar')"
echo "      - En la pantalla de login, haz click en 'SKIP'"
echo ""
echo "🔧 Si no funciona desde Windows:"
echo "   - Verifica que Windows Firewall permita las conexiones"
echo "   - Asegúrate de que Docker Desktop está ejecutándose"
echo "   - Prueba con las URLs de IP: $WSL_IP:PUERTO"
