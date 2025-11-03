#!/bin/bash
set -e

# ============================================================================
# Migración a Gitea - Convertir Gitea en Fuente de Verdad
# ============================================================================
# Este script se ejecuta DESPUÉS del bootstrap inicial
# Migra todos los repositorios a Gitea y actualiza Argo CD
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GITEA_URL="${GITEA_URL:-http://localhost:30083}"
GITEA_USER="${GITEA_USER:-gitops}"
GITEA_PASSWORD="${GITEA_PASSWORD:?Error: GITEA_PASSWORD environment variable must be set}"
GITEA_TOKEN_FILE="$HOME/.gitops-credentials/gitea-token.txt"

# Colores
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "🔄 Iniciando migración a Gitea..."
echo ""

# ============================================================================
# PASO 1: Validar que Gitea está accesible
# ============================================================================
echo -e "${BLUE}📋 PASO 1: Validando acceso a Gitea...${NC}"

if ! curl -f -s "$GITEA_URL/api/v1/version" > /dev/null; then
    echo "❌ No se puede acceder a Gitea en $GITEA_URL"
    echo "   Asegúrate de que Gitea está desplegado y accesible."
    exit 1
fi

echo -e "${GREEN}✅ Gitea accesible${NC}"
echo ""

# ============================================================================
# PASO 2: Obtener o crear token de API
# ============================================================================
echo -e "${BLUE}🔑 PASO 2: Configurando token de API...${NC}"

mkdir -p "$HOME/.gitops-credentials"

if [ -f "$GITEA_TOKEN_FILE" ]; then
    GITEA_TOKEN=$(cat "$GITEA_TOKEN_FILE")
    echo "Token existente encontrado"
else
    echo "Creando nuevo token de API..."
    GITEA_TOKEN=$(curl -s -X POST "$GITEA_URL/api/v1/users/$GITEA_USER/tokens" \
        -H "Content-Type: application/json" \
        -u "$GITEA_USER:$GITEA_PASSWORD" \
        -d '{
            "name": "gitops-migration-'$(date +%s)'",
            "scopes": ["write:repository", "write:user"]
        }' | jq -r '.sha1')
    
    if [ -z "$GITEA_TOKEN" ] || [ "$GITEA_TOKEN" == "null" ]; then
        echo "❌ No se pudo crear el token de API"
        exit 1
    fi
    
    echo "$GITEA_TOKEN" > "$GITEA_TOKEN_FILE"
    chmod 600 "$GITEA_TOKEN_FILE"
fi

echo -e "${GREEN}✅ Token configurado${NC}"
echo ""

# ============================================================================
# PASO 3: Crear repositorios en Gitea
# ============================================================================
echo -e "${BLUE}📦 PASO 3: Creando repositorios en Gitea...${NC}"

REPOS=(
    "argo-config"
    "gitops-tools"
    "gitops-custom-apps"
    "app-reloj"
    "visor-gitops"
)

for repo in "${REPOS[@]}"; do
    echo "  - Creando repositorio: $repo"
    
    # Verificar si ya existe
    if curl -f -s "$GITEA_URL/api/v1/repos/$GITEA_USER/$repo" \
        -H "Authorization: token $GITEA_TOKEN" > /dev/null 2>&1; then
        echo "    ⚠️  Ya existe, saltando..."
        continue
    fi
    
    # Crear repositorio
    curl -s -X POST "$GITEA_URL/api/v1/user/repos" \
        -H "Authorization: token $GITEA_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{
            \"name\": \"$repo\",
            \"private\": false,
            \"auto_init\": false,
            \"default_branch\": \"main\"
        }" > /dev/null
    
    echo "    ✅ Creado"
done

echo -e "${GREEN}✅ Repositorios creados${NC}"
echo ""

# ============================================================================
# PASO 4: Push de repositorios locales a Gitea
# ============================================================================
echo -e "${BLUE}🚀 PASO 4: Haciendo push de repositorios a Gitea...${NC}"

# Función para push
push_repo() {
    local repo_name=$1
    local local_path=$2
    local gitea_url="http://$GITEA_USER:$GITEA_TOKEN@localhost:30083/$GITEA_USER/$repo_name.git"
    
    echo "  - Pushing $repo_name..."
    
    if [ ! -d "$local_path" ]; then
        echo "    ❌ No existe el directorio: $local_path"
        return 1
    fi
    
    cd "$local_path"
    
    # Inicializar git si no existe
    if [ ! -d ".git" ]; then
        git init
        git add .
        git commit -m "initial commit: migrated from bootstrap"
    fi
    
    # Agregar remote o actualizar
    if git remote | grep -q "gitea"; then
        git remote set-url gitea "$gitea_url"
    else
        git remote add gitea "$gitea_url"
    fi
    
    # Push
    git push -u gitea main --force
    
    echo "    ✅ Push completado"
}

# Push todos los repos
push_repo "argo-config" "$HOME/gitops-repos/argo-config"
push_repo "gitops-tools" "$HOME/gitops-repos/gitops-tools"
push_repo "gitops-custom-apps" "$HOME/gitops-repos/gitops-custom-apps"
push_repo "app-reloj" "$HOME/dotfiles/sourcecode-apps/app-reloj"
push_repo "visor-gitops" "$HOME/dotfiles/sourcecode-apps/visor-gitops"

echo -e "${GREEN}✅ Push completado${NC}"
echo ""

# ============================================================================
# PASO 5: Actualizar Argo CD para usar Gitea
# ============================================================================
echo -e "${BLUE}🔄 PASO 5: Actualizando Argo CD para usar Gitea...${NC}"

echo "  - Actualizando root-app..."
kubectl patch application root -n argocd --type='json' -p='[
    {
        "op": "replace",
        "path": "/spec/source/repoURL",
        "value": "http://gitea.gitea.svc.cluster.local:3000/gitops/argo-config.git"
    }
]'

echo "  - Esperando sincronización..."
sleep 10

# Trigger sync manual para aplicar cambios inmediatamente
kubectl -n argocd patch app root --type merge -p '{"operation":{"sync":{}}}'

echo -e "${GREEN}✅ Argo CD actualizado${NC}"
echo ""

# ============================================================================
# PASO 6: Configurar repository credentials en Argo CD
# ============================================================================
echo -e "${BLUE}🔐 PASO 6: Configurando credenciales de repositorio...${NC}"

# Crear secret para Gitea repositories
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: gitea-repo-creds
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repo-creds
stringData:
  type: git
  url: http://gitea.gitea.svc.cluster.local:3000/gitops
  username: $GITEA_USER
  password: $GITEA_PASSWORD
EOF

echo -e "${GREEN}✅ Credenciales configuradas${NC}"
echo ""

# ============================================================================
# PASO 7: Verificar migración
# ============================================================================
echo -e "${BLUE}✅ PASO 7: Verificando migración...${NC}"

echo "  - Verificando aplicaciones en Argo CD..."
kubectl get applications -n argocd

echo ""
echo "═══════════════════════════════════════════════════════"
echo -e "${GREEN}✨ Migración completada exitosamente${NC}"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "Gitea es ahora tu fuente de verdad para GitOps"
echo ""
echo "URLs de repositorios en Gitea:"
for repo in "${REPOS[@]}"; do
    echo "  - http://localhost:30083/gitops/$repo"
done
echo ""
echo "Próximos pasos:"
echo "  1. Verifica en Argo CD que las apps se sincronizan desde Gitea"
echo "  2. Haz cambios en los repos de Gitea y observa auto-sync"
echo "  3. ¡Disfruta de GitOps 100% best-practices!"
echo ""
