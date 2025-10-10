# GitOps Stack - Fixes Completos Aplicados

## Resumen Ejecutivo

**Fecha**: 2024-10-10
**Problema Principal**: Argo Workflows v3.7.2 bug de status.nodes NULL + múltiples issues en pipeline CI/CD
**Solución**: Downgrade a v3.6.11 oficial + 6 fixes adicionales
**Resultado**: Pipeline end-to-end funcionando (git push → build → update manifests)

---

## Bug Crítico: Argo Workflows v3.7.2

### Síntoma
- Workflows se ejecutaban (pods completaban exitosamente)
- Status permanecía NULL: `{phase: null, progress: null, nodes: []}`
- Controller logs mostraban: "Node was nil, will be initialized as type Skipped"

### Investigación
- GitHub Issue #12352: Race condition con INFORMER_WRITE_BACK=true
- INFORMER_WRITE_BACK=false NO solucionó el problema
- Install.yaml customizado tenía env vars no presentes en versión oficial

### Solución Aplicada
**Downgrade a v3.6.11 oficial**:
```bash
curl -sL https://github.com/argoproj/argo-workflows/releases/download/v3.6.11/install.yaml
```

**Cambios**:
- Reemplazado install.yaml completo (3167 líneas)
- Cambiado namespace de `argo` a `argo-workflows`
- Mantenido solo env var esencial: `LEADER_ELECTION_IDENTITY`
- ConfigMap minimal: solo `instanceID: default`

**Resultado**: ✅ status.nodes ahora persiste correctamente

**Commits**:
- `7519fa2` - ConfigMap YAML válido (sin UTF-8)
- `8fc8547` - Eliminado ConfigMap vacío de install.yaml

---

## Fix 1: ConfigMap Vacío en install.yaml

### Problema
- `install.yaml` oficial de v3.6.11 contenía ConfigMap vacío (líneas 3043-3048)
- ArgoCD aplicaba AMBOS archivos: `configmap.yaml` (con data) + `install.yaml` (vacío)
- El último aplicado (vacío) machacaba el correcto
- Controller no encontraba `instanceID` → no procesaba workflows

### Solución
Eliminado ConfigMap de `install.yaml`:
```yaml
# ANTES (línea 3043-3048)
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: workflow-controller-configmap
  namespace: argo-workflows
---

# DESPUÉS
# (eliminado completamente)
```

Mantener solo `configmap.yaml` separado:
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: workflow-controller-configmap
  namespace: argo-workflows
data:
  config: |
    instanceID: default
```

**Resultado**: ✅ Controller con instanceID correcto, workflows procesados

**Commit**: `8fc8547` - Remove empty ConfigMap from install.yaml

---

## Fix 2: Registry Service Name Incorrecto

### Problema
- Sensor pasaba parámetro: `registry.registry.svc.cluster.local:5000`
- Servicio real se llama: `docker-registry`
- Kaniko fallaba con: "no such host registry.registry.svc.cluster.local"

### Solución
Actualizado `sensor-gitea.yaml`:
```yaml
# ANTES
parameters:
  - name: registry
    value: "registry.registry.svc.cluster.local:5000"

# DESPUÉS
parameters:
  - name: registry
    value: "docker-registry.registry.svc.cluster.local:5000"
```

**Resultado**: ✅ Kaniko construye y pushea imagen correctamente

**Commit**: `73918a9` - Correct registry service name

---

## Fix 3: RoleBinding con ServiceAccount Incorrecto

### Problema
- RoleBinding apuntaba a: `argo-events-sensor-sa`
- Sensor deployment usaba (por bug v1.9.7): `argo-events-sa`
- Sensor no podía crear Workflows: "User system:serviceaccount:argo-events:argo-events-sa cannot create resource workflows"

### Solución
Actualizado `rbac-sensor.yaml`:
```yaml
# ANTES
subjects:
  - kind: ServiceAccount
    name: argo-events-sensor-sa
    namespace: argo-events

# DESPUÉS
subjects:
  - kind: ServiceAccount
    name: argo-events-sa
    namespace: argo-events
```

**Resultado**: ✅ Sensor crea workflows exitosamente

**Commit**: `9b03d73` - RoleBinding uses correct SA

---

## Fix 4: Kaniko Shell Wrapper Error

### Problema
- WorkflowTemplate usaba: `command: [sh, /scripts/docker-build-push.sh]`
- Kaniko executor es imagen `scratch` → no tiene shell
- Error: `exec: "sh": executable file not found in $PATH`

### Solución
Cambio a args directos en `workflowtemplate-ci.yaml`:
```yaml
# ANTES
container:
  image: gcr.io/kaniko-project/executor:latest
  command: [sh, /scripts/docker-build-push.sh]

# DESPUÉS
container:
  image: gcr.io/kaniko-project/executor:latest
  args:
    - --dockerfile=/workspace/Dockerfile
    - --context=/workspace
    - --destination={{inputs.parameters.registry}}/{{inputs.parameters.image-name}}:{{inputs.parameters.commit-sha}}
    - --destination={{inputs.parameters.registry}}/{{inputs.parameters.image-name}}:latest
    - --insecure
    - --skip-tls-verify
```

**Resultado**: ✅ Kaniko ejecuta build sin errores

**Commit**: `06959d1` - Kaniko direct args (no shell wrapper)

---

## Fix 5: Branch Name con refs/heads/ Prefix

### Problema
- Gitea webhook envía: `refs/heads/main`
- Git clone script esperaba: `main`
- Error: "pathspec 'refs/heads/main' did not match any file(s) known to git"

### Solución
Agregado limpieza en `configmap-ci-scripts.yaml`:
```bash
# git-clone.sh
BRANCH="${1:-main}"
CLEAN_BRANCH=$(echo "$BRANCH" | sed 's|refs/heads/||')
git checkout "$CLEAN_BRANCH"
```

**Resultado**: ✅ Git clone funciona con refs/heads/main

**Commit**: `b44a025` - Clean branch name (remove refs/heads/)

---

## Fix 6: Update-Manifests Sin Credenciales Git

### Problema
- Script clonaba: `http://gitea.gitea.svc.cluster.local:3000/gitops/custom-apps.git`
- Sin credenciales → `fatal: could not read Username`
- Repo incorrecto: esperaba `gitops-repo` pero era `custom-apps`

### Solución
Actualizado `configmap-ci-scripts.yaml`:
```bash
# ANTES
git clone http://gitea.gitea.svc.cluster.local:3000/gitops/gitops-repo.git

# DESPUÉS
git clone http://gitops:n5Sn4efguDMnUgIx@gitea.gitea.svc.cluster.local:3000/gitops/custom-apps.git
cd custom-apps/demo-app
sed -i "s|newTag:.*|newTag: $COMMIT_SHA|g" kustomization.yaml
git push
```

**Creado repo custom-apps** con manifests kustomize:
- `demo-app/kustomization.yaml`
- `demo-app/deployment.yaml`
- `demo-app/service.yaml`

**Resultado**: ✅ Manifests actualizados automáticamente en Gitea

**Commit**: `6a7a786` - update-manifests with git credentials and correct repo path

---

## Fix 7: Documentación Bug Argo Events v1.9.7

### Problema
- Argo Events v1.9.7 ignora `spec.serviceAccountName` en Sensor
- Deployment generado usa `argo-events-sa` por defecto
- Requiere patch manual tras cada recreación

### Solución
Documentado en `sensor-gitea.yaml`:
```yaml
spec:
  # NOTE: Argo Events v1.9.7 bug - sensor-controller ignores this field
  # Deployment uses 'argo-events-sa' by default. Requires manual patch:
  # kubectl patch deployment -n argo-events <sensor-deployment> --type=json \
  #   -p='[{"op":"replace","path":"/spec/template/spec/serviceAccountName","value":"argo-events-sa"}]'
  serviceAccountName: argo-events-sensor-sa
```

**Resultado**: ✅ Documentado para futuros deploys

**Commit**: `172ff74` - docs: Add comment explaining Argo Events v1.9.7 SA bug

---

## Validación End-to-End

### Pipeline Completo Funcionando

**Flujo**:
```
git push (demo-app)
  ↓
Gitea webhook → http://gitea-webhook.argo-events.svc.cluster.local:12000/push
  ↓
Argo Events sensor-gitea-demo-app
  ↓
Workflow demo-app-ci-XXXXX creado
  ↓
Step 1: git-clone (alpine/git) ✅
  - Clone: http://gitea.gitea.svc.cluster.local:3000/gitops/demo-app.git
  - Branch: main (cleaned from refs/heads/main)
  - Workspace: /workspace PVC
  ↓
Step 2: docker-build (kaniko) ✅
  - Context: /workspace
  - Registry: docker-registry.registry.svc.cluster.local:5000
  - Tags: <commit-sha>, latest
  - Image pushed successfully
  ↓
Step 3: update-manifests (alpine/git) ✅
  - Clone: http://gitops:PASSWORD@gitea.gitea.svc.cluster.local:3000/gitops/custom-apps.git
  - Update: demo-app/kustomization.yaml newTag
  - Commit & push to Gitea
  ↓
ArgoCD detecta cambio en custom-apps repo
  ↓
Application demo-app synced con nueva imagen
```

**Workflows Exitosos Validados**:
- `demo-app-ci-8tkp2`: Succeeded (3/3 steps, 7 nodes)
- `demo-app-ci-n2k69`: Succeeded (3/3 steps)

**Status.nodes persiste correctamente**:
```json
{
  "phase": "Succeeded",
  "progress": "3/3",
  "nodes": {
    "demo-app-ci-8tkp2": {/* ... */},
    "demo-app-ci-8tkp2-git-clone-xxx": {/* ... */},
    "demo-app-ci-8tkp2-docker-build-xxx": {/* ... */},
    "demo-app-ci-8tkp2-update-manifests-xxx": {/* ... */}
  }
}
```

---

## Archivos Actualizados en dotfiles/

### manifests/gitops-tools/argo-workflows/
- ✅ `install.yaml` - v3.6.11 oficial sin ConfigMap vacío
- ✅ `configmap.yaml` - instanceID: default
- ✅ `configmap-ci-scripts.yaml` - Scripts con credenciales Git y branch cleaning
- ✅ `workflowtemplate-ci.yaml` - Kaniko args directos

### manifests/gitops-tools/argo-events/
- ✅ `sensor-gitea.yaml` - Registry correcto + doc bug SA
- ✅ `rbac-sensor.yaml` - RoleBinding con argo-events-sa

### manifests/custom-apps/demo-app/ (NUEVO)
- ✅ `kustomization.yaml`
- ✅ `deployment.yaml`
- ✅ `service.yaml`

### scripts/
- ✅ `sync-to-gitea.sh` - Actualizado con gitops-tools y custom-apps

---

## Comandos Útiles

### Verificar Estado Pipeline
```bash
# Ver workflows recientes
kubectl get wf -n argo-workflows --sort-by=.metadata.creationTimestamp | tail -5

# Ver status completo de workflow
kubectl get wf -n argo-workflows <workflow-name> -o json | jq '.status'

# Ver logs de step específico
kubectl logs -n argo-workflows <pod-name> -c main

# Verificar imagen en registry
curl http://localhost:30087/v2/demo-app/tags/list
```

### Trigger Manual
```bash
cd ~/gitops-repos/sourcecode-apps/demo-app
git commit --allow-empty -m "TEST: Manual trigger"
git push
```

### Patch Sensor SA (si se recrea)
```bash
kubectl get deployment -n argo-events -l sensor-name=gitea-workflow-trigger -o name | \
  xargs -I {} kubectl patch {} -n argo-events --type='json' \
  -p='[{"op":"replace","path":"/spec/template/spec/serviceAccountName","value":"argo-events-sa"}]'
```

---

## Lecciones Aprendidas

1. **Siempre buscar en GitHub Issues antes de debug extensivo**
   - v3.7.2 bug estaba documentado en issue #12352
   - Solución oficial: usar v3.6.11 stable

2. **ArgoCD aplica TODOS los archivos en directorio**
   - Duplicados (ConfigMap vacío + ConfigMap con data) causan conflicts
   - Último aplicado gana → verificar orden alfabético

3. **Argo Events v1.9.7 tiene bug conocido con SA**
   - Ignora `spec.serviceAccountName`
   - Requiere patch manual del Deployment generado

4. **Kaniko es imagen scratch sin shell**
   - No usar `command: [sh, ...]`
   - Args directos únicamente

5. **Gitea webhook envía refs/heads/BRANCH**
   - Limpiar con sed antes de git checkout

6. **GitOps requiere credenciales en scripts**
   - URL formato: `http://user:password@host/repo.git`
   - Password de Gitea: `kubectl get secret gitea-admin-secret`

---

## Commits en gitops-repos/gitops-tools

```
172ff74 docs: Add comment explaining Argo Events v1.9.7 SA bug
6a7a786 fix: update-manifests with git credentials and correct repo path
9b03d73 fix: RoleBinding uses correct SA (argo-events-sa)
73918a9 fix: Correct registry service name (docker-registry not registry)
8fc8547 fix: Remove empty ConfigMap from install.yaml (use separate configmap.yaml)
7519fa2 fix: ConfigMap with valid YAML syntax (no UTF-8 comments)
06959d1 fix: Kaniko direct args (no shell wrapper)
b44a025 fix: Clean branch name (remove refs/heads/) in git-clone script
6648d7d fix: Use internal Gitea URL instead of webhook localhost
c06e506 fix: Argo Workflows v3.6.11 + sensor without clusterScope
```

---

## Referencias

- [Argo Workflows Issue #12352](https://github.com/argoproj/argo-workflows/issues/12352) - INFORMER_WRITE_BACK race condition
- [Argo Workflows v3.6.11 Release](https://github.com/argoproj/argo-workflows/releases/tag/v3.6.11)
- [Kaniko Documentation](https://github.com/GoogleContainerTools/kaniko) - No shell in scratch image
- [Argo Events v1.9.7](https://github.com/argoproj/argo-events/releases/tag/v1.9.7)
