# GitOps Learning Platform - Instalación Automática

[![Kind](https://img.shields.io/badge/Kind-v0.30.0-blue)](https://kind.sigs.k8s.io/)
[![ArgoCD](https://img.shields.io/badge/ArgoCD-v3.1.9-blue)](https://argo-cd.readthedocs.io/)
[![Gitea](https://img.shields.io/badge/Gitea-v1.25.0-blue)](https://docs.gitea.io/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

Plataforma GitOps completa de aprendizaje, instalable en un solo comando, siguiendo **best-practices oficiales** de Kubernetes, Kind, ArgoCD y Gitea.

## 🎯 ¿Qué es esto?

Una plataforma GitOps **100% funcional** que se instala automáticamente y te permite:

- **Aprender GitOps** de forma práctica
- **Practicar CI/CD** con Argo Workflows
- **Experimentar con deployments** progresivos (Argo Rollouts, Kargo)
- **Gestionar infraestructura como código** con ArgoCD
- **Todo local** - no requiere cloud ni costes externos

## ✨ Características

### 🚀 Instalación Automatizada

```bash
./install.sh
```

**Resultado en 5-10 minutos:**
- ✅ 13 aplicaciones GitOps desplegadas
- ✅ Todas Synced & Healthy
- ✅ Accesibles vía localhost (NodePort)
- ✅ Credenciales mostradas claramente

### 🛠️ Stack Tecnológico

**GitOps Core:**
- **Kind**: Cluster Kubernetes local (single-node, optimizado para aprendizaje)
- **ArgoCD**: Motor GitOps con UI accesible (modo anónimo para learning)
- **Gitea**: Source of truth - Git server local

**CI/CD & Delivery:**
- **Argo Events**: Event-driven workflows (webhooks Git → pipelines)
- **Argo Workflows**: CI/CD pipelines (build, test, deploy)
- **Argo Rollouts**: Deployments progresivos (canary, blue-green)
- **Kargo**: Promoción multi-stage (dev → staging → prod)

**Observability:**
- **Prometheus**: Métricas de cluster y aplicaciones
- **Grafana**: Dashboards de visualización
- **Kubernetes Dashboard**: Vista del cluster

**Infraestructura:**
- **Docker Registry**: Registry local para imágenes custom
- **Sealed Secrets**: Gestión segura de credenciales
- **Redis**: Cache compartido

### 🎓 Best-Practices Implementadas

Siguiendo documentación oficial:

**Kind** ([kind.sigs.k8s.io](https://kind.sigs.k8s.io/)):
- ✅ `apiServerAddress: 127.0.0.1` (security)
- ✅ extraPortMappings para NodePort
- ✅ Validación de pre-requisitos
- ✅ Configuración containerd para registry insecure

**ArgoCD** ([argo-cd.readthedocs.io](https://argo-cd.readthedocs.io/)):
- ✅ `server.insecure: true` (HTTP para learning)
- ✅ `users.anonymous.enabled: true` (acceso sin login)
- ✅ App of Apps pattern (root-app → ApplicationSets)
- ✅ List generators (explícitos, no git discovery)
- ✅ Project separation (sistema, gitops-tools, argo)

**Gitea** ([docs.gitea.io](https://docs.gitea.io/)):
- ✅ CLI admin user creation (método oficial)
- ✅ Health endpoint validation (`/api/healthz`)
- ✅ API token authentication

**General:**
- ✅ NetworkPolicies habilitadas (zero-trust)
- ✅ No PodDisruptionBudgets (single-node optimization)
- ✅ No Ingress (NodePort directo para Kind)
- ✅ Sealed Secrets para credenciales
- ✅ Auto-sync habilitado (GitOps continuo)

## 📋 Pre-requisitos

### Obligatorios

- **Linux/WSL2** con Ubuntu
- **Docker** instalado y ejecutándose
  ```bash
  docker --version
  docker ps  # Debe funcionar sin errores
  ```

### Recomendados

- **4GB+ RAM** disponible
- **10GB+ disco** libre
- **Conexión a internet** (para descargar imágenes)

### Auto-instalados

El script instala automáticamente si faltan:
- `kubectl` (v1.34.1+)
- `kind` (v0.30.0+)
- `helm` (v3.19.0+)
- `jq`, `curl`, `git`

## 🚀 Instalación

### Paso 1: Clonar repositorio

```bash
git clone https://github.com/andres20980/dotfiles.git
cd dotfiles
```

### Paso 2: Ejecutar instalación

```bash
./install.sh
```

El script:
1. ✅ Valida pre-requisitos
2. ✅ Instala dependencias faltantes
3. ✅ Crea cluster Kind
4. ✅ Instala ArgoCD
5. ✅ Despliega Gitea
6. ✅ Inicializa repositorios
7. ✅ Bootstrap GitOps (root-app)
8. ✅ Verifica estado (13/13 Synced & Healthy)

### Paso 3: Acceder a las UIs

Al finalizar, el script muestra:

```
════════════════════════════════════════════════════════════
📋 CREDENCIALES DE ACCESO (¡GUÁRDALAS!):
════════════════════════════════════════════════════════════

Argo CD:
  URL:      http://localhost:30080
  Usuario:  admin (o acceso anónimo habilitado)
  Password: <generado automáticamente>

Gitea (Source of Truth):
  URL:      http://localhost:30083
  Usuario:  gitops
  Password: gitops

Grafana:
  URL:      http://localhost:30082
  Usuario:  admin
  Password: gitops

Kargo:
  URL:      http://localhost:30085
  Usuario:  admin
  Password: gitops
```

## 📚 Uso

### Ver aplicaciones en ArgoCD

```bash
# CLI
argocd app list

# UI
open http://localhost:30080
```

### Modificar una aplicación

```bash
# 1. Edita manifests en Gitea
open http://localhost:30083/gitops/gitops-manifests

# 2. Commit + Push
cd gitops-manifests
git add .
git commit -m "feat: actualizar app"
git push gitea main

# 3. ArgoCD detecta cambios y sincroniza automáticamente (self-heal enabled)
```

### Ver logs de aplicaciones

```bash
# Desde CLI
kubectl logs -n <namespace> -l app=<app-name>

# Desde ArgoCD UI
# Click en app → Tab "Logs"
```

### Monitorizar con Grafana

```bash
open http://localhost:30082
# Usuario: admin / Password: gitops
```

## 🔧 Troubleshooting

### Cluster no arranca

```bash
# Ver logs de Kind
kind get clusters
docker ps -a | grep kind

# Recrear cluster
kind delete cluster --name gitops-local
./install.sh
```

### ArgoCD no sincroniza

```bash
# Forzar sync manual
argocd app sync <app-name>

# Ver logs del controller
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller
```

### Gitea no accesible

```bash
# Verificar pod
kubectl get pods -n gitea

# Ver logs
kubectl logs -n gitea -l app=gitea

# Port-forward directo (bypass NodePort)
kubectl port-forward -n gitea svc/gitea 3000:3000
# Acceder: http://localhost:3000
```

### Aplicación en "Progressing"

```bash
# Verificar pods
kubectl get pods -n <namespace>

# Ver eventos
kubectl get events -n <namespace> --sort-by='.lastTimestamp'

# Verificar sync status
argocd app get <app-name>
```

## 🎯 Estructura del Proyecto

```
dotfiles/
├── install.sh                          # Script instalación automatizada
├── README.md                           # Esta documentación
├── gitops-manifests/                   # Manifests Kubernetes (source of truth)
│   ├── infra-configs/
│   │   ├── apps-sistema/              # Apps bootstrap (argocd-self, sealed-secrets, gitea)
│   │   └── argocd-manifests/          # Configuración ArgoCD (projects, RBAC, etc)
│   ├── gitops-tools/                  # GitOps infrastructure tools
│   │   ├── argo-events/               # Event-driven automation
│   │   ├── argo-workflows/            # CI/CD pipelines
│   │   ├── argo-rollouts/             # Progressive delivery
│   │   ├── kargo/                     # Multi-stage promotion
│   │   ├── dashboard/                 # Kubernetes Dashboard
│   │   ├── grafana/                   # Observability - visualization
│   │   ├── prometheus/                # Observability - metrics
│   │   ├── redis/                     # Shared cache
│   │   └── registry/                  # Docker registry local
│   ├── custom-apps/                   # Tus aplicaciones custom (vacío por defecto)
│   └── instalacion/
│       ├── kind-config.yaml           # Config cluster Kind
│       └── root-app.yaml              # Root App (App of Apps pattern)
└── gitops-source-code/                # Source code de aplicaciones custom
    └── app-demo/                      # Ejemplo: Node.js app
```

## 🧹 Limpieza

### Eliminar cluster completo

```bash
kind delete cluster --name gitops-local
```

### Eliminar solo una aplicación

```bash
# Via ArgoCD CLI
argocd app delete <app-name>

# Via kubectl
kubectl delete application <app-name> -n argocd
```

### Reset completo

```bash
# 1. Eliminar cluster
kind delete cluster --name gitops-local

# 2. Limpiar Docker images (opcional)
docker system prune -a

# 3. Reinstalar desde cero
./install.sh
```

## 📖 Recursos de Aprendizaje

### Documentación Oficial

- [Kubernetes Concepts](https://kubernetes.io/docs/concepts/)
- [Kind Quick Start](https://kind.sigs.k8s.io/docs/user/quick-start/)
- [ArgoCD Getting Started](https://argo-cd.readthedocs.io/en/stable/getting_started/)
- [Gitea Documentation](https://docs.gitea.io/)
- [Argo Workflows Examples](https://github.com/argoproj/argo-workflows/tree/master/examples)

### Tutoriales Recomendados

1. **GitOps Basics**: [ArgoCD Core Concepts](https://argo-cd.readthedocs.io/en/stable/core_concepts/)
2. **CI/CD Pipelines**: [Argo Workflows User Guide](https://argo-workflows.readthedocs.io/en/latest/walk-through/)
3. **Progressive Delivery**: [Argo Rollouts Getting Started](https://argoproj.github.io/argo-rollouts/)

## 🤝 Contribuir

Este proyecto sigue best-practices oficiales. Si encuentras mejoras:

1. Fork el repositorio
2. Crea branch (`git checkout -b feature/mejora`)
3. Commit (`git commit -m 'feat: mejora X'`)
4. Push (`git push origin feature/mejora`)
5. Abre Pull Request

## 📝 Licencia

MIT - Ver [LICENSE](LICENSE) para detalles.

## 🙏 Créditos

Basado en documentación oficial de:
- [Kubernetes](https://kubernetes.io/)
- [Kind](https://kind.sigs.k8s.io/)
- [Argo Project](https://argoproj.github.io/)
- [Gitea](https://docs.gitea.io/)

---

**¿Preguntas?** Abre un [issue](https://github.com/andres20980/dotfiles/issues) 

**¿Funciona?** Dale una ⭐ al repo!
