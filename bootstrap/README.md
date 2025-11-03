# GitOps Bootstrap - Best Practices Architecture

## 🎯 Objetivo

Implementar un entorno GitOps 100% best-practices siguiendo los [principios de OpenGitOps](https://opengitops.dev/) y la [documentación oficial de Argo CD](https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/).

## 📐 Arquitectura

```
┌─────────────────────────────────────────────┐
│  1. kubectl apply bootstrap/root-app.yaml   │  ← ÚNICA acción manual
└──────────────┬──────────────────────────────┘
               │
               v
┌──────────────────────────────────────────────┐
│    Argo CD (self-managed via App of Apps)   │
└──────────────┬───────────────────────────────┘
               │
               ├──> Sealed-Secrets (gestión de secretos)
               ├──> Docker Registry (almacenamiento de imágenes)
               ├──> Gitea (Git server - fuente de verdad)
               └──> Argo CD Config (auto-configuración)
                    │
                    └──> Después de migración:
                         ├─> gitops-tools (desde Gitea)
                         └─> gitops-custom-apps (desde Gitea)
```

## 🔄 Flujo de Bootstrap

### Fase 1: Bootstrap Inicial (Temporal)

```bash
./bootstrap/install.sh
```

1. **Instala Argo CD** (única acción imperativa)
2. **Aplica root-app.yaml** que despliega:
   - `sealed-secrets` (Helm chart)
   - `docker-registry` (desde GitHub/local temporal)
   - `gitea` (desde GitHub/local temporal)
   - `argocd-config` (desde GitHub/local temporal)

Durante esta fase, los repos apuntan a GitHub público o repo local temporal.

### Fase 2: Migración a Gitea (Fuente de Verdad Final)

```bash
./bootstrap/migrate-to-gitea.sh
```

1. **Crea repositorios en Gitea**:
   - `argo-config`
   - `gitops-tools`
   - `gitops-custom-apps`
   - `app-reloj`
   - `visor-gitops`

2. **Push de código local a Gitea**

3. **Actualiza Argo CD** para usar Gitea como fuente:
   ```bash
   kubectl patch application root -n argocd --type='json' -p='[{
       "op": "replace",
       "path": "/spec/source/repoURL",
       "value": "http://gitea.gitea.svc.cluster.local:3000/gitops/argo-config.git"
   }]'
   ```

4. **A partir de aquí**: ¡100% GitOps desde Gitea!

## 📁 Estructura de Directorios

```
dotfiles/
├── bootstrap/
│   ├── install.sh                    # Script de instalación inicial
│   ├── migrate-to-gitea.sh          # Script de migración a Gitea
│   ├── root-app.yaml                # Root Application (App of Apps)
│   └── apps/
│       ├── sealed-secrets.yaml      # Gestión de secretos
│       ├── docker-registry.yaml     # Registry interno
│       ├── gitea.yaml               # Git server
│       └── argocd-config.yaml       # Self-management de Argo CD
│
├── config/
│   └── kind-config.yaml             # Configuración del cluster Kind
│
└── sourcecode-apps/
    ├── app-reloj/                   # Aplicación de ejemplo
    └── visor-gitops/                # Aplicación de ejemplo

gitops-repos/
├── argo-config/                     # Configuración de Argo CD
│   ├── projects/                    # AppProjects
│   ├── applications/                # Applications
│   └── repositories/                # Repository credentials
│
├── gitops-tools/                    # Herramientas de infrastructure
│   ├── sealed-secrets/
│   ├── docker-registry/
│   ├── gitea/
│   ├── argo-workflows/
│   ├── argo-events/
│   ├── argo-rollouts/
│   └── prometheus/
│
└── gitops-custom-apps/              # Aplicaciones custom
    ├── app-reloj/
    └── visor-gitops/
```

## ✅ Principios GitOps Cumplidos

### 1. **Declarative** ✅
- Todo definido en YAML
- Sin comandos imperativos (excepto bootstrap inicial)
- Estado deseado explícito

### 2. **Versioned and Immutable** ✅
- Git como única fuente de verdad
- Historia completa en commits
- Rollback trivial con `git revert`

### 3. **Pulled Automatically** ✅
- Argo CD pull desde Git cada 3 minutos
- No push desde CI/CD a cluster
- Cluster self-heals automáticamente

### 4. **Continuously Reconciled** ✅
- Argo CD reconcilia continuamente
- Auto-sync enabled
- Self-heal enabled

## 🚀 Guía de Uso

### Instalación Inicial

```bash
# 1. Crear cluster Kind
kind create cluster --config=config/kind-config.yaml

# 2. Ejecutar bootstrap
./bootstrap/install.sh

# 3. Esperar a que todo esté ready (5-10 min)
kubectl get applications -n argocd --watch

# 4. Acceder a Argo CD
# URL: https://localhost:30080
# Usuario: admin
# Password: (mostrado al final del script)
```

### Migración a Gitea

```bash
# 1. Verificar que Gitea está accessible
curl http://localhost:30083/api/v1/version

# 2. Ejecutar migración
./bootstrap/migrate-to-gitea.sh

# 3. Verificar en Argo CD que apps usan Gitea
kubectl get app root -n argocd -o jsonpath='{.spec.source.repoURL}'
```

### Operaciones Diarias

```bash
# Hacer cambios en aplicaciones
cd ~/gitops-repos/gitops-custom-apps/app-reloj
vim deployment.yaml
git commit -am "Update replicas"
git push

# Argo CD detecta y aplica automáticamente (≤ 3 min)

# Ver estado de sincronización
kubectl get applications -n argocd
```

## 🔧 Troubleshooting

### Argo CD no sincroniza

```bash
# Ver logs del application controller
kubectl logs -n argocd deploy/argocd-application-controller --tail=100

# Forzar sync manual
kubectl -n argocd patch app <APP_NAME> --type merge -p '{"operation":{"sync":{}}}'
```

### Gitea no accesible

```bash
# Ver estado del pod
kubectl get pods -n gitea
kubectl logs -n gitea deploy/gitea

# Ver service
kubectl get svc -n gitea
```

### Reset completo

```bash
# Eliminar cluster y empezar de nuevo
kind delete cluster
kind create cluster --config=config/kind-config.yaml
./bootstrap/install.sh
```

## 📚 Referencias

- [OpenGitOps Principles](https://opengitops.dev/)
- [Argo CD Declarative Setup](https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/)
- [Argo CD App of Apps](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/)
- [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets)
- [Gitea Documentation](https://docs.gitea.com/)

## 🎓 Conceptos Clave

### App of Apps Pattern

El `root-app.yaml` es una Application que despliega otras Applications. Esto permite:
- Gestionar múltiples apps como una unidad
- Dependency management automático
- Single source of truth para toda la infrastructure

### Self-Management

Argo CD se gestiona a sí mismo a través de `argocd-config` Application:
- Actualiza su propia configuración desde Git
- Agrega nuevos repositorios declarativamente
- Modifica RBAC y settings sin tocar el cluster

### Bootstrap Chicken-and-Egg

**Problema**: Gitea debe estar en el cluster para ser fuente de verdad, pero necesitamos fuente de verdad para desplegar Gitea.

**Solución**:
1. Bootstrap temporal desde GitHub/local
2. Desplegar Gitea
3. Migrar repos a Gitea
4. Actualizar Argo CD para usar Gitea
5. Gitea ahora se auto-gestiona desde sí mismo

## 🎯 Best Practices Implementadas

✅ Separation of Concerns (argo-config, gitops-tools, custom-apps)
✅ Secret Management (Sealed Secrets)
✅ GitOps Principles (Declarative, Versioned, Pulled, Reconciled)
✅ Infrastructure as Code
✅ Self-Service (developers push code, GitOps does the rest)
✅ Audit Trail (Git history)
✅ Disaster Recovery (restore from Git)
✅ Environment Parity (same manifests, different overlays)

## 🔐 Seguridad

- **Sealed Secrets**: Secretos encriptados en Git
- **RBAC**: Control de acceso granular en Argo CD
- **Network Policies**: Aislamiento entre namespaces
- **GitOps Audit**: Cada cambio rastreable en Git
- **No credentials in cluster**: Secrets managed outside

---

**Mantenido por**: Tu equipo GitOps
**Última actualización**: 2025-11-03
**Versión**: 1.0.0
