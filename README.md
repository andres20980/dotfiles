# 🚀 Entorno GitOps Completo - Instalación Automatizada

[![GitOps](https://img.shields.io/badge/GitOps-ArgoCD-blue.svg)](https://argoproj.github.io/cd/)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-kind-326ce5.svg)](https://kind.sigs.k8s.io/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

Entorno de desarrollo y aprendizaje GitOps profesional con **instalación completamente automatizada**. Implementa best practices de ArgoCD, CI/CD con semantic versioning, y observabilidad integrada.

## ⚡ Instalación Rápida

```bash
git clone https://github.com/andres20980/dotfiles.git
cd dotfiles
./install.sh
```

**Tiempo:** ~8-10 minutos | **Requisitos:** Docker, kubectl, kind, jq

Al finalizar tendrás un cluster Kubernetes completo con:
- ✅ 14 aplicaciones desplegadas y sincronizadas
- ✅ Pipeline CI/CD funcional con semantic versioning
- ✅ Registry interno configurado
- ✅ Monitoreo con Prometheus + Grafana
- ✅ Gitea como fuente de verdad

## 🎯 ¿Qué incluye?

### 🔧 GitOps Tools (Infraestructura Core)

| Herramienta | Puerto | Descripción |
|-------------|--------|-------------|
| **Argo CD** | [30080](http://localhost:30080) | Motor GitOps - sincronización desde Git |
| **Gitea** | [30083](http://localhost:30083) | Git server - source of truth (gitops/gitops) |
| **Argo Workflows** | [30096](http://localhost:30096) | Motor CI/CD con semantic versioning |
| **Argo Events** | 30200 | Event-driven automation (webhooks) |
| **Argo Rollouts** | [30084](http://localhost:30084) | Despliegues progresivos (blue/green, canary) |
| **Docker Registry** | [30100](http://localhost:30100) | Registry HTTP interno |
| **Registry UI** | [30096](http://localhost:30096) | Interfaz web del registry |
| **Prometheus** | [30090](http://localhost:30090) | Recolección de métricas |
| **Grafana** | [30086](http://localhost:30086) | Dashboards (admin/gitops) |
| **K8s Dashboard** | [30091](http://localhost:30091) | Panel de Kubernetes |
| **Redis** | - | Cache para Argo Events |
| **Redis Commander** | [30097](http://localhost:30097) | Interfaz de Redis |
| **Kargo** | [30095](http://localhost:30095) | Progressive delivery multi-entorno |

### 🚀 Custom Apps (Aplicaciones Demo)

| Aplicación | Puerto | Descripción |
|------------|--------|-------------|
| **app-reloj** | [30150](http://localhost:30150) | Aplicación demo - CI/CD completo |

## 🔄 Pipeline CI/CD Automático

El entorno incluye un **pipeline completo end-to-end** con semantic versioning:

```
1. Developer → Push a gitops-source-code/app-reloj
2. Gitea Webhook → Argo Events
3. Argo Workflows → Build con Kaniko
   ├─ v{semver} (desde package.json)
   ├─ {commit-sha} (trazabilidad)
   └─ latest (conveniencia)
4. Update kustomization.yaml → newTag: v{semver}
5. ArgoCD Auto-Sync → Deploy a Kubernetes
```

**Test del pipeline:**
```bash
cd gitops-source-code/app-reloj
# Editar package.json version: "1.4.0"
git add package.json
git commit -m "bump: version 1.4.0"
git push gitea main

# Monitorear el workflow
kubectl -n argo-workflows get workflows -w
```

## 📂 Estructura del Proyecto

```
dotfiles/
├── install.sh                          # 🎯 Instalador maestro automatizado
├── README.md                           # 📖 Esta documentación
├── PORTS.md                            # 🔌 Mapa de puertos (30080-30220)
├── LICENSE                             # ⚖️  Licencia MIT
│
├── config/
│   └── kind-config.yaml               # Configuración del cluster kind
│
├── bootstrap/                          # 🔧 Configuración inicial
│   ├── install.sh                     # [DEPRECATED] Script antiguo
│   ├── root-app.yaml                  # Root Application (App of Apps)
│   └── apps/                          # Bootstrap applications
│       ├── argocd-config.yaml         # Configuración de ArgoCD
│       ├── gitea.yaml                 # Despliegue de Gitea
│       ├── sealed-secrets.yaml        # Sealed Secrets controller
│       ├── docker-registry.yaml       # Registry interno
│       └── gitops-tools-appset.yaml   # ApplicationSet para tools
│
├── gitops-manifests/                   # 📦 Manifests de Kubernetes (Source of Truth)
│   ├── custom-apps/                   # Aplicaciones de usuario
│   │   └── app-reloj/
│   │       ├── deployment.yaml
│   │       ├── service.yaml          # Con link.argocd.argoproj.io/external-link
│   │       └── kustomization.yaml    # newName/newTag para registry
│   │
│   ├── gitops-tools/                  # Herramientas GitOps
│   │   ├── argo-events/
│   │   │   ├── install.yaml
│   │   │   ├── eventbus.yaml
│   │   │   ├── eventsource-gitea.yaml
│   │   │   ├── sensor-gitea.yaml     # Trigger workflows on push
│   │   │   └── rbac-*.yaml
│   │   ├── argo-workflows/
│   │   │   ├── install.yaml
│   │   │   ├── workflowtemplate-ci.yaml    # Pipeline con sem-ver
│   │   │   ├── configmap-ci-scripts.yaml   # Scripts (git-clone, update-manifests)
│   │   │   ├── rbac-workflow-sa.yaml       # ServiceAccount + permisos
│   │   │   └── sealed-secret-gitea.yaml
│   │   ├── argo-rollouts/
│   │   ├── dashboard/
│   │   ├── gitea/
│   │   ├── grafana/
│   │   ├── kargo/
│   │   ├── prometheus/
│   │   ├── redis/
│   │   └── registry/
│   │
│   └── infra-configs/                 # Configuración de ArgoCD
│       ├── applications/              # Definición de Applications
│       │   ├── applicationsets.yaml
│       │   ├── argo-events-*.yaml
│       │   ├── argo-workflows.yaml
│       │   ├── custom-apps.yaml      # ApplicationSet auto-discovery
│       │   └── gitops-tools-*.yaml
│       ├── argocd-self/              # Auto-gestión de ArgoCD
│       ├── configmaps/               # ConfigMaps de ArgoCD
│       ├── projects/                 # AppProjects
│       └── repositories/             # Repository credentials
│
└── gitops-source-code/                # 💻 Código fuente de aplicaciones
    └── app-reloj/
        ├── Dockerfile
        ├── package.json              # version para sem-ver
        ├── server.js
        └── README.md
```

## 🏗️ Arquitectura GitOps

Este proyecto implementa el **patrón App of Apps** de ArgoCD:

```
root (Application)
├── argocd-self-config (auto-gestión)
│   ├── ConfigMaps (argocd-cm, argocd-rbac-cm)
│   ├── Projects (gitops-tools, custom-apps)
│   └── Applications (definición de todas las apps)
│
├── gitops-tools (ApplicationSet)
│   ├── argo-events
│   ├── argo-workflows
│   ├── argo-rollouts
│   ├── registry
│   ├── prometheus
│   ├── grafana
│   └── ...
│
└── custom-apps (ApplicationSet)
    └── app-reloj
        └── [auto-discovery de nuevas apps]
```

### 🔐 Best Practices Implementadas

#### GitOps Principles (OpenGitOps)
- ✅ **Declarative**: Todo definido en Git como YAML
- ✅ **Versioned & Immutable**: Git es source of truth
- ✅ **Pulled Automatically**: ArgoCD sincroniza automáticamente
- ✅ **Continuously Reconciled**: Self-healing habilitado

#### ArgoCD Best Practices
- ✅ **App of Apps Pattern**: Gestión jerárquica
- ✅ **ApplicationSets**: Auto-discovery de aplicaciones
- ✅ **Projects**: Aislamiento por equipos (gitops-tools, custom-apps)
- ✅ **Sync Waves**: Orden de despliegue con annotations
- ✅ **Health Checks**: Estado de recursos
- ✅ **Automated Sync**: prune + selfHeal
- ✅ **Retry Logic**: backoff exponencial
- ✅ **External Links**: Anotaciones en servicios

#### CI/CD Best Practices
- ✅ **Semantic Versioning**: v{major}.{minor}.{patch}
- ✅ **Immutable Tags**: commit-sha para trazabilidad
- ✅ **Image Scanning**: (preparado para integración)
- ✅ **GitOps Workflow**: Separación código/config
- ✅ **Event-Driven**: Webhooks → Events → Workflows

#### Security Best Practices
- ✅ **Sealed Secrets**: Encriptación de secretos en Git
- ✅ **RBAC**: ServiceAccounts con permisos mínimos
- ✅ **No Root**: Contenedores sin privilegios
- ✅ **Registry Privado**: Imágenes en registry interno
- ✅ **Network Policies**: (preparado para implementación)

## 📋 Requisitos

### Sistema Operativo
- Ubuntu 22.04+ / Debian 11+
- WSL2 en Windows (recomendado)
- macOS 12+

### Software Requerido
```bash
# Docker
docker --version  # >= 20.10

# kubectl
kubectl version --client  # >= 1.28

# kind
kind version  # >= 0.20

# jq (procesamiento JSON)
jq --version  # >= 1.6

# curl, git (normalmente pre-instalados)
```

### Recursos Hardware
- **CPU**: 4 cores (mínimo 2)
- **RAM**: 8 GB (mínimo 4 GB)
- **Disco**: 20 GB libres

## 🚀 Guía de Uso

### Primera Instalación

```bash
# 1. Clonar repositorio
git clone https://github.com/andres20980/dotfiles.git
cd dotfiles

# 2. Ejecutar instalador
./install.sh

# 3. Esperar ~8-10 minutos
# El script mostrará URLs al finalizar
```

### Verificar Instalación

```bash
# Estado del cluster
kubectl get nodes

# Aplicaciones en ArgoCD
kubectl -n argocd get applications

# Pods en todos los namespaces
kubectl get pods -A

# Acceder a ArgoCD
open http://localhost:30080
```

### Añadir Nueva Aplicación

```bash
# 1. Crear código fuente
mkdir -p gitops-source-code/mi-app
# Añadir Dockerfile, código, etc.

# 2. Crear manifests
mkdir -p gitops-manifests/custom-apps/mi-app
cd gitops-manifests/custom-apps/mi-app

# 3. Crear deployment.yaml
cat > deployment.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mi-app
  namespace: mi-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mi-app
  template:
    metadata:
      labels:
        app: mi-app
    spec:
      containers:
      - name: mi-app
        image: mi-app:latest
        ports:
        - containerPort: 8080
EOF

# 4. Crear service.yaml con link externo
cat > service.yaml <<EOF
apiVersion: v1
kind: Service
metadata:
  name: mi-app
  namespace: mi-app
  annotations:
    link.argocd.argoproj.io/external-link: 'http://localhost:30151'
spec:
  type: NodePort
  selector:
    app: mi-app
  ports:
  - port: 80
    targetPort: 8080
    nodePort: 30151
EOF

# 5. Crear kustomization.yaml
cat > kustomization.yaml <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - deployment.yaml
  - service.yaml
images:
- name: mi-app
  newName: <REGISTRY_IP>:5000/mi-app
  newTag: v1.0.0
EOF

# 6. Commit y push
cd ../../..
git add gitops-manifests/custom-apps/mi-app
git commit -m "feat: add mi-app"
git push gitea main

# 7. ApplicationSet auto-detecta y despliega
# Ver en ArgoCD: http://localhost:30080
```

### Limpiar Entorno

```bash
# Eliminar cluster completo
kind delete cluster --name gitops-local

# Re-crear desde cero
./install.sh
```

## 🔍 Troubleshooting

### Problema: Pods en ImagePullBackOff

```bash
# Verificar registry
kubectl -n registry get svc docker-registry

# Verificar configuración containerd
docker exec gitops-local-control-plane cat /etc/containerd/config.toml | grep registry

# Re-aplicar configuración
kubectl -n registry rollout restart deployment docker-registry
```

### Problema: ArgoCD no sincroniza

```bash
# Forzar refresh
kubectl -n argocd patch app <APP_NAME> --type merge \
  -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'

# Ver logs
kubectl -n argocd logs -l app.kubernetes.io/name=argocd-application-controller
```

### Problema: Workflow falla

```bash
# Ver workflows
kubectl -n argo-workflows get workflows

# Ver logs del workflow
kubectl -n argo-workflows logs <WORKFLOW_NAME>

# Ver pods del workflow
kubectl -n argo-workflows get pods -l workflows.argoproj.io/workflow=<WORKFLOW_NAME>
```

### Problema: Webhook no funciona

```bash
# Verificar EventSource
kubectl -n argo-events get eventsource
kubectl -n argo-events logs -l eventsource-name=gitea-webhook

# Verificar Sensor
kubectl -n argo-events get sensor
kubectl -n argo-events logs -l sensor-name=gitea-workflow-trigger

# Verificar webhook en Gitea
curl -s http://localhost:30083/api/v1/repos/gitops/app-reloj/hooks -u gitops:gitops | jq
```

## 📚 Recursos

### Documentación Oficial
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Argo Workflows](https://argoproj.github.io/workflows/)
- [Argo Events](https://argoproj.github.io/events/)
- [Argo Rollouts](https://argoproj.github.io/rollouts/)
- [OpenGitOps Principles](https://opengitops.dev/)

### Documentación Interna
- [PORTS.md](PORTS.md) - Mapa completo de puertos
- [bootstrap/README.md](bootstrap/README.md) - Fase de bootstrap
- [gitops-manifests/gitops-tools/kargo/README.md](gitops-manifests/gitops-tools/kargo/README.md) - Kargo setup

### Semantic Versioning
- [SemVer 2.0.0](https://semver.org/)
- [Conventional Commits](https://www.conventionalcommits.org/)

## 🤝 Contribuir

Este proyecto sigue best practices de Git:

```bash
# 1. Fork del repositorio
# 2. Crear rama feature
git checkout -b feature/mi-mejora

# 3. Commits descriptivos (conventional commits)
git commit -m "feat: add support for multi-cluster"
git commit -m "fix: resolve webhook timeout"
git commit -m "docs: update installation guide"

# 4. Push y Pull Request
git push origin feature/mi-mejora
```

### Tipos de Commit
- `feat`: Nueva funcionalidad
- `fix`: Corrección de bug
- `docs`: Documentación
- `refactor`: Refactorización
- `test`: Tests
- `chore`: Mantenimiento

## 📝 Licencia

MIT License - Ver [LICENSE](LICENSE)

## 🙏 Créditos

Construido con:
- [ArgoCD](https://argoproj.github.io/cd/)
- [Kubernetes](https://kubernetes.io/)
- [kind](https://kind.sigs.k8s.io/)
- [Gitea](https://gitea.io/)
- [Prometheus](https://prometheus.io/)
- [Grafana](https://grafana.com/)

---

**Hecho con ❤️ para la comunidad GitOps**
