#!/bin/bash

# Script para mapear puertos faltantes usando socat
# Esto es temporal hasta que se recree el cluster con la configuración correcta

echo "🔌 Configurando mapeo de puertos faltantes..."

# Obtener la IP del contenedor kind
KIND_IP=$(docker inspect mini-cluster-control-plane | grep '"IPAddress":' | grep -v null | head -1 | cut -d'"' -f4)

if [ -n "$KIND_IP" ]; then
    echo "📍 IP del cluster kind: $KIND_IP"
    
    # Mapear puerto 30081 (Dashboard) - matar proceso anterior si existe
    pkill -f "socat.*30081" 2>/dev/null || true
    socat TCP-LISTEN:30081,fork TCP:$KIND_IP:30081 &
    
    # Mapear puerto 30082 (Hello World) - matar proceso anterior si existe  
    pkill -f "socat.*30082" 2>/dev/null || true
    socat TCP-LISTEN:30082,fork TCP:$KIND_IP:30082 &
    
    echo "✅ Puertos mapeados:"
    echo "   Dashboard: localhost:30081"
    echo "   Hello World: localhost:30082"
else
    echo "❌ No se pudo detectar la IP del contenedor kind"
fi
