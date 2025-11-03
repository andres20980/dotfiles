#!/bin/bash
set -e

# ============================================================================
# Bootstrap GitOps - Instalación Inicial
# ============================================================================
# Este script se ejecuta UNA SOLA VEZ para inicializar el cluster GitOps
# Después de esto, TODO se gestiona declarativamente desde Git
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARGO_VERSION="v2.13.2"

echo "🚀 Iniciando Bootstrap GitOps Best-Practices..."
echo ""

# Colores para output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ============================================================================
# PASO 1: Validar prerequisitos
# ============================================================================
echo -e "${BLUE}📋 PASO 1: Validando prerequisitos...${NC}"

if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl no encontrado. Instálalo primero."
    exit 1
fi

if ! command -v kind &> /dev/null; then
    echo "❌ kind no encontrado. Instálalo primero."
    exit 1
fi

if ! kubectl cluster-info &> /dev/null; then
    echo "❌ No hay cluster de Kubernetes activo."
    echo "   Ejecuta primero: kind create cluster --config=config/kind-config.yaml"
    exit 1
fi

echo -e "${GREEN}✅ Prerequisitos validados${NC}"
echo ""

# ============================================================================
# PASO 2: Instalar Argo CD
# ============================================================================
echo -e "${BLUE}📦 PASO 2: Instalando Argo CD ${ARGO_VERSION}...${NC}"

# Crear namespace
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

# Instalar Argo CD
kubectl apply -n argocd -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGO_VERSION}/manifests/install.yaml"

echo -e "${GREEN}✅ Argo CD instalado${NC}"
echo ""

# ============================================================================
# PASO 3: Esperar a que Argo CD esté ready
# ============================================================================
echo -e "${BLUE}⏳ PASO 3: Esperando a que Argo CD esté listo...${NC}"

kubectl wait --for=condition=available --timeout=300s \
    deployment/argocd-server \
    deployment/argocd-repo-server \
    deployment/argocd-applicationset-controller \
    -n argocd

kubectl wait --for=condition=ready --timeout=300s \
    pod -l app.kubernetes.io/name=argocd-application-controller \
    -n argocd

# Configurar Argo CD para entorno local de aprendizaje
echo "  - Configurando Argo CD para acceso local sin autenticación..."
kubectl patch svc argocd-server -n argocd -p '{"spec":{"type":"NodePort","ports":[{"name":"http","port":80,"protocol":"TCP","targetPort":8080,"nodePort":30080}]}}' > /dev/null 2>&1
kubectl patch configmap argocd-cmd-params-cm -n argocd --type merge -p '{"data":{"server.insecure":"true"}}' > /dev/null 2>&1
kubectl patch configmap argocd-cm -n argocd --type merge -p '{"data":{"users.anonymous.enabled":"true"}}' > /dev/null 2>&1
kubectl patch configmap argocd-rbac-cm -n argocd --type merge -p '{"data":{"policy.default":"role:admin"}}' > /dev/null 2>&1
kubectl rollout restart deployment argocd-server -n argocd > /dev/null 2>&1
kubectl rollout status deployment argocd-server -n argocd --timeout=60s > /dev/null 2>&1

echo -e "${GREEN}✅ Argo CD está listo (HTTP sin autenticación)${NC}"
echo ""

# ============================================================================
# PASO 4: Aplicar Root Application (App of Apps)
# ============================================================================
echo -e "${BLUE}🌳 PASO 4: Desplegando Root Application (App of Apps)...${NC}"
echo ""

# Verificar que el root-app.yaml tiene una URL válida
REPO_URL=$(grep "repoURL:" "$SCRIPT_DIR/root-app.yaml" | head -1 | awk '{print $2}')
echo "  - Repositorio configurado: $REPO_URL"

# Aplicar root app
kubectl apply -f "$SCRIPT_DIR/root-app.yaml"

echo -e "${GREEN}✅ Root Application aplicada${NC}"
echo ""

# ============================================================================
# PASO 5: Esperar a que infrastructure esté ready
# ============================================================================
echo -e "${BLUE}⏳ PASO 5: Esperando a que infrastructure se despliegue...${NC}"
echo "Esto puede tardar varios minutos..."
echo ""

# Esperar Sealed Secrets
echo "  - Esperando Sealed Secrets..."
kubectl wait --for=condition=available --timeout=300s \
    deployment/sealed-secrets-controller \
    -n sealed-secrets 2>/dev/null || true

# Esperar Docker Registry
echo "  - Esperando Docker Registry..."
kubectl wait --for=condition=available --timeout=300s \
    deployment/docker-registry \
    -n registry 2>/dev/null || true

# Esperar Gitea
echo "  - Esperando Gitea..."
kubectl wait --for=condition=available --timeout=300s \
    deployment/gitea \
    -n gitea 2>/dev/null || true

echo -e "${GREEN}✅ Infrastructure desplegada${NC}"
echo ""

# ============================================================================
# PASO 6: Obtener información de acceso
# ============================================================================
echo -e "${BLUE}🔑 PASO 6: Información de acceso${NC}"
echo ""

# Argo CD admin password
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

echo "═══════════════════════════════════════════════════════"
echo "  Argo CD:"
echo "    URL: https://localhost:30080"
echo "    Usuario: admin"
echo "    Password: $ARGOCD_PASSWORD"
echo ""
echo "  Gitea:"
echo "    URL: http://localhost:30083"
echo "    Usuario: gitops"
echo "    Password: (definido en sealed-secret)"
echo ""
echo "  Docker Registry:"
echo "    Internal: docker-registry.registry.svc.cluster.local:5000"
echo "    External: localhost:30087"
echo "═══════════════════════════════════════════════════════"
echo ""

# ============================================================================
# SIGUIENTES PASOS
# ============================================================================
echo -e "${YELLOW}📝 SIGUIENTES PASOS:${NC}"
echo ""
echo "1. Accede a Argo CD: https://localhost:30080"
echo "   - Verifica que las aplicaciones se están sincronizando"
echo ""
echo "2. Accede a Gitea: http://localhost:30083"
echo "   - Completa la configuración inicial si es necesario"
echo ""
echo "3. Ejecuta el script de migración:"
echo "   ./migrate-to-gitea.sh"
echo "   - Esto creará los repositorios en Gitea"
echo "   - Hará push de todos los manifests"
echo "   - Actualizará Argo CD para usar Gitea como fuente"
echo ""
echo "4. A partir de aquí: ¡100% GitOps desde Gitea!"
echo ""
echo -e "${GREEN}✨ Bootstrap completado exitosamente${NC}"
