# Argo Events - Configuración y Notas

## ServiceAccount del Sensor

**Comportamiento conocido:** El Sensor controller de Argo Events v2.4.x a veces ignora `spec.template.serviceAccountName` en el CRD del Sensor y crea el Deployment con la ServiceAccount `default` en lugar de la especificada.

### Solución implementada

En lugar de parchear dinámicamente el Deployment (frágil, nombre aleatorio), garantizamos **RBAC para AMBAS ServiceAccounts**:

1. **`argo-events-sensor-sa`** - ServiceAccount correcta y declarada en el Sensor CRD
2. **`default`** - ServiceAccount de fallback que usa el controller en algunos casos

Ambas están configuradas en `rbac-sensor.yaml` con:
- `Role`: `sensor-workflow-creator` (crear workflows en namespace `argo-workflows`)
- `RoleBinding`: `sensor-workflow-creator-binding` con ambas SAs como subjects

### Orden de despliegue (sync-waves)

- **Wave -1**: RBAC (ServiceAccount, Role, RoleBinding) - se crea primero
- **Wave 0**: Sensors (gitea-workflow-trigger, gitea-visor-trigger) - se crea después

Esto garantiza que los permisos existan antes de que el Sensor controller cree los pods.

### Verificación

Para verificar qué SA está usando el Sensor:

```bash
kubectl get pods -n argo-events -l sensor-name=gitea-workflow-trigger \
  -o jsonpath='{.items[0].spec.serviceAccountName}'
```

Resultado esperado: `default` o `argo-events-sensor-sa` (ambos tienen permisos correctos).

### Referencias

- Argo Events Sensor Spec: https://argoproj.github.io/argo-events/sensors/sensor-guide/
- Issue conocido: https://github.com/argoproj/argo-events/issues/2156
