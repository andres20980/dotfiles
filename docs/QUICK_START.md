# 🎯 Guía Rápida de Nuevas Funcionalidades

Esta guía documenta todas las mejoras implementadas en la versión 2.0.0

---

## 📋 Índice

1. [Configuración Personalizada](#configuración-personalizada)
2. [Modo Debug](#modo-debug)
3. [Snapshots y Backup](#snapshots-y-backup)
4. [Smoke Tests](#smoke-tests)
5. [Instalación Paralela](#instalación-paralela)
6. [Validación de Red](#validación-de-red)
7. [Gestión de Errores](#gestión-de-errores)

---

## ⚙️ Configuración Personalizada

### Uso Básico

```bash
# 1. Copiar el archivo de configuración de ejemplo
cp config.env config.local.env

# 2. Editar tu configuración local
nano config.local.env

# 3. Cargar y ejecutar
source config.local.env && ./install.sh --unattended
```

### Variables Más Útiles

```bash
# Deshabilitar aplicaciones de ejemplo (solo infraestructura)
export ENABLE_CUSTOM_APPS=false

# Cambiar puertos por defecto
export ARGOCD_PORT=31080
export GITEA_PORT=31083

# Activar modo debug
export DEBUG_MODE=true
export VERBOSE_LOGGING=true

# Preservar cluster en caso de error
export SKIP_CLEANUP_ON_ERROR=true

# Deshabilitar smoke tests (útil para desarrollo)
export RUN_SMOKE_TESTS=false

# Instalación secuencial (más lenta pero más estable)
export PARALLEL_INSTALL=false
```

### Configuración para CI/CD

```bash
# Modo CI (sin interacciones)
export CI_MODE=true
export RUN_SMOKE_TESTS=true
export SKIP_CLEANUP_ON_ERROR=false

./install.sh --unattended
```

---

## 🐛 Modo Debug

### Activación

```bash
# Método 1: Variable de entorno
DEBUG_MODE=true ./install.sh --stage cluster

# Método 2: En config.env
echo "DEBUG_MODE=true" >> config.env
echo "VERBOSE_LOGGING=true" >> config.env
source config.env && ./install.sh
```

### Lo que hace

- ✅ Activa `set -x` (traza cada comando ejecutado)
- ✅ Muestra logs detallados con `log_verbose()`
- ✅ Captura estado completo en errores automáticamente
- ✅ No limpia archivos temporales para análisis

### Logs de Debug

```bash
# Los logs se guardan automáticamente en:
/tmp/gitops-debug-<timestamp>/
├── cluster-info.txt           # Info general del cluster
├── pods.txt                   # Estado de todos los pods
├── events.txt                 # Eventos recientes
├── argocd-applications.yaml   # Estado de apps de ArgoCD
├── argocd-server.log          # Logs del servidor ArgoCD
├── gitea.log                  # Logs de Gitea
├── services.txt               # Todos los services
└── docker-kind.txt            # Estado de Docker y kind
```

### Análisis Post-Mortem

```bash
# Si la instalación falla, revisa los logs:
cd /tmp/gitops-debug-<timestamp>

# Ver pods que fallaron
grep -i "error\|failed" pods.txt

# Ver eventos de error
grep -i "error\|warning" events.txt

# Ver logs de ArgoCD
tail -100 argocd-server.log
```

---

## 📸 Snapshots y Backup

### Crear Snapshot

```bash
# Snapshot con nombre automático (fecha/hora)
./install.sh --snapshot

# Snapshot con nombre personalizado
./install.sh --snapshot mi-backup-produccion

# Snapshot antes de hacer cambios importantes
./install.sh --snapshot pre-upgrade-v2
```

### Contenido del Snapshot

Los snapshots incluyen:
- ✅ Todos los recursos de Kubernetes (YAML completo)
- ✅ Applications de ArgoCD
- ✅ Projects de ArgoCD
- ✅ ConfigMaps
- ✅ Git bundles de repos de Gitea (infrastructure, applications, argo-config)

### Restaurar Snapshot

```bash
# Restaurar desde directorio
./install.sh --restore ~/.gitops-snapshots/mi-backup-produccion

# Restaurar desde tarball
./install.sh --restore ~/.gitops-snapshots/mi-backup-produccion.tar.gz

# Verificar estado después de restaurar
kubectl get applications -n argocd
kubectl get pods -A
```

### Snapshots Automáticos

```bash
# Habilitar snapshots automáticos antes de cambios
export AUTO_SNAPSHOT=true
./install.sh --start-from gitops
```

### Ubicación de Snapshots

```bash
# Por defecto:
~/.gitops-snapshots/
├── auto-20251008-143025/
│   ├── all-resources.yaml
│   ├── argocd-applications.yaml
│   ├── gitops-infrastructure.bundle
│   └── snapshot-info.txt
└── auto-20251008-143025.tar.gz

# Personalizar ubicación
export SNAPSHOT_DIR=/mnt/backups/gitops
./install.sh --snapshot
```

---

## 🧪 Smoke Tests

### Ejecución Automática

Los smoke tests se ejecutan automáticamente al finalizar la instalación si `RUN_SMOKE_TESTS=true` (por defecto).

### Tests Incluidos

**Infraestructura:**
- ✅ Cluster kind activo
- ✅ Kubectl responde
- ✅ Namespaces creados correctamente

**APIs:**
- ✅ ArgoCD API responde en puerto configurado
- ✅ Gitea API funcional
- ✅ Prometheus accesible
- ✅ Grafana accesible

**ArgoCD:**
- ✅ Al menos 1 Application existe
- ✅ Todas las apps están Synced (opcional)
- ✅ Todas las apps están Healthy (opcional)

**Seguridad:**
- ✅ Sealed Secrets controller running
- ✅ CRD SealedSecrets existe

### Deshabilitar Smoke Tests

```bash
# Durante instalación
export RUN_SMOKE_TESTS=false
./install.sh --unattended

# En config.env
echo "RUN_SMOKE_TESTS=false" >> config.env
```

### Tests Manuales

```bash
# Verificar manualmente después de instalación
kubectl get applications -n argocd
kubectl get pods -A
curl -s http://localhost:30080/api/version | jq
```

---

## ⚡ Instalación Paralela

### Activación

```bash
# Por defecto está activado
# Para desactivar:
export PARALLEL_INSTALL=false
./install.sh --stage docker
```

### Herramientas Paralelizadas

- kubectl
- helm
- kind

Se instalan en paralelo usando jobs de bash, reduciendo el tiempo total ~20%.

### Logs de Instalación Paralela

```bash
# Ver logs individuales de cada herramienta
tail -f /tmp/install-kubectl.log
tail -f /tmp/install-helm.log
tail -f /tmp/install-kind.log
```

### Cuándo Desactivar

- ❌ Conexión de red inestable
- ❌ Problemas de permisos con sudo
- ❌ Debugging de problemas de instalación
- ❌ Entornos CI/CD con limitaciones de procesos paralelos

---

## 🌐 Validación de Red

### Funcionamiento

Se ejecuta automáticamente en la fase de prerequisitos:

```bash
./install.sh --stage prereqs
```

### URLs Verificadas

- `https://dl.k8s.io/release/stable.txt`
- `https://get.docker.com`
- `https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml`
- `https://github.com/bitnami-labs/sealed-secrets/releases`

### Manejo de Fallos

Si alguna URL no es accesible:
1. Se muestra advertencia con URLs fallidas
2. Se solicita confirmación para continuar
3. En modo CI, se puede forzar continuación

### Bypass

```bash
# Saltar verificación de red (no recomendado)
# La instalación puede fallar si no hay conectividad
# Útil solo para entornos offline con mirrors locales
```

---

## 🛡️ Gestión de Errores

### Captura Automática de Estado

Cuando ocurre un error:

1. ✅ Se captura estado completo del cluster
2. ✅ Se guardan logs de componentes críticos
3. ✅ Se preserva cluster si `SKIP_CLEANUP_ON_ERROR=true`
4. ✅ Se muestra ruta a directorio de debug

### Preservar Cluster en Errores

```bash
# Útil para diagnosticar problemas
export SKIP_CLEANUP_ON_ERROR=true
./install.sh --unattended

# Si falla, el cluster queda activo para inspección
kubectl get pods -A
kubectl logs -n argocd deployment/argocd-server
```

### Debug Paso a Paso

```bash
# Ejecutar fase por fase
./install.sh --stage prereqs
./install.sh --stage system  
./install.sh --stage docker
./install.sh --stage cluster
# ... inspeccionar entre cada fase ...
```

### Reintento Manual

```bash
# Si una fase falla, puedes reintentarla
./install.sh --stage gitops

# O continuar desde donde falló
./install.sh --start-from gitops --unattended
```

---

## 🔧 Casos de Uso Comunes

### Desarrollo Local con Debug

```bash
export DEBUG_MODE=true
export VERBOSE_LOGGING=true
export SKIP_CLEANUP_ON_ERROR=true
export RUN_SMOKE_TESTS=true

./install.sh --start-from cluster
```

### Instalación Mínima (Solo Infraestructura)

```bash
export ENABLE_CUSTOM_APPS=false
export ENABLE_KARGO=false
export ENABLE_DASHBOARD=false

./install.sh --unattended
```

### CI/CD Pipeline

```bash
export CI_MODE=true
export RUN_SMOKE_TESTS=true
export SKIP_CLEANUP_ON_ERROR=false
export PARALLEL_INSTALL=true

./install.sh --unattended
```

### Backup y Restauración Rápida

```bash
# Antes de cambios importantes
./install.sh --snapshot pre-change

# Hacer cambios...
./scripts/sync-to-gitea.sh

# Si algo falla, restaurar
./install.sh --restore ~/.gitops-snapshots/pre-change
```

---

## 📚 Recursos Adicionales

- [README.md](README.md) - Documentación principal
- [CHANGELOG.md](CHANGELOG.md) - Histórico de cambios
- [config.env](config.env) - Todas las variables configurables
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) - Arquitectura detallada
- [docs/SECURITY.md](docs/SECURITY.md) - Consideraciones de seguridad

---

<div align="center">

**¿Preguntas o problemas?**

[Reportar un issue](https://github.com/andres20980/dotfiles/issues/new)

</div>
