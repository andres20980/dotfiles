# 🚀 GitOps Master Setup - Entorno Completo Automatizado# 🚀 GitOps Learning Environment - **Excelencia Educativa**# 🚀 Entorno de Desarrollo GitOps Completo



[![GitOps](https://img.shields.io/badge/GitOps-ArgoCD-blue.svg)](https://argoproj.github.io/cd/)

[![Kubernetes](https://img.shields.io/badge/Kubernetes-kind-326ce5.svg)](https://kind.sigs.k8s.io/)

[![Observability](https://img.shields.io/badge/Monitoring-Prometheus%2BGrafana-orange.svg)](https://prometheus.io/)[![GitOps](https://img.shields.io/badge/GitOps-ArgoCD-blue.svg)](https://argoproj.github.io/cd/)Este repositorio contiene la configuración automática para crear un **entorno GitOps completo** con Kubernetes, ArgoCD, Gitea y aplicaciones de ejemplo. Todo se instala y configura automáticamente con un solo comando.

[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

[![Kubernetes](https://img.shields.io/badge/Kubernetes-kind-326ce5.svg)](https://kind.sigs.k8s.io/)

> **Un entorno GitOps completo y listo para producción que se instala en minutos**

[![Observability](https://img.shields.io/badge/Observability-Prometheus%2BGrafana-orange.svg)](https://prometheus.io/)## 🎯 ¿Qué incluye este entorno?

Este repositorio contiene un instalador completamente automatizado para crear un **entorno GitOps** profesional con Kubernetes, ArgoCD, Gitea, monitoreo, y todas las herramientas necesarias para desarrollo y aprendizaje.

[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

## ✨ Características Principales

### 🔧 **Herramientas Base:**

- 🎯 **Instalación Automatizada** - Un solo comando para todo el stack

- 🔄 **GitOps Nativo** - Todo gestionado declarativamente con ArgoCD> **🎯 El entorno GitOps más simple, limpio y educativo para aprender en local**- ✅ **Docker** - Containerización

- 📊 **Observabilidad Completa** - Prometheus + Grafana incluidos

- 🔐 **Seguridad First** - Sealed Secrets, credenciales seguras, sin hardcoding> - ✅ **kubectl** - Cliente Kubernetes

- 🐳 **100% Local** - No requiere cloud, funciona en tu laptop

- 🔧 **Modular y Extensible** - Activa/desactiva componentes fácilmente> Diseñado siguiendo **best practices** para que novatos puedan entender **cómo funciona GitOps** desde cero con un ecosistema **mínimo pero funcional**.- ✅ **kind** - Kubernetes local en Docker

- 📸 **Snapshots** - Sistema de backup y recuperación integrado

- 🧪 **Smoke Tests** - Validación automática post-instalación- ✅ **zsh + Oh My Zsh** - Shell mejorado con plugins



---## 📋 **¿Qué aprenderás?**- ✅ **Git Credential Manager** - Gestión de credenciales



## 🎯 ¿Qué Incluye?



### 🏗️ **Infraestructura GitOps**- 🏗️ **Arquitectura GitOps**: Separación clara entre código e infraestructura### 🏗️ **Stack GitOps:**

- ✅ **Kubernetes (kind)** - Cluster local multi-nodo

- ✅ **ArgoCD** - Continuous Delivery GitOps con UI- 🚀 **ArgoCD**: Despliegue declarativo automático  - ✅ **Kubernetes Cluster** (kind) - Cluster local completo

- ✅ **Gitea** - Servidor Git local con Actions (CI/CD)

- ✅ **Sealed Secrets** - Gestión segura de secrets en Git- 📊 **Observabilidad**: Métricas con Prometheus + Grafana- ✅ **ArgoCD** - Controlador GitOps con UI web

- ✅ **Argo Rollouts** - Deployments progresivos (Blue/Green, Canary)

- ✅ **Kargo** - Promoción avanzada de releases- 🐳 **Containers**: Docker + Kubernetes locales- ✅ **Gitea** - Servidor Git local (como GitHub local)



### 📊 **Observabilidad**- 📦 **Manifests**: Kubernetes YAML best practices- ✅ **NGINX Ingress** - Controlador de ingreso

- ✅ **Prometheus** - Métricas y alerting

- ✅ **Grafana** - Dashboards y visualización- 🔧 **Automatización**: Scripts modulares y mantenibles- ✅ **Kubernetes Dashboard** - UI web de Kubernetes

- ✅ **Kubernetes Dashboard** - UI de administración del cluster



### 🚀 **Aplicaciones de Ejemplo**

- ✅ **Demo API** - Aplicación Node.js con CI/CD completo---### � **Herramientas de Observabilidad:**

- ✅ **Registry Local** - Docker registry para imágenes custom

- ✅ **Prometheus** - Recolección de métricas y alertas

---

## ⚡ **Instalación Ultra-Rápida**- ✅ **Grafana** - Dashboards y visualización de métricas

## ⚡ Instalación Rápida

- ✅ **Métricas Nativas** - Aplicaciones con métricas Prometheus integradas

### Prerequisitos

- Ubuntu/Debian Linux (o WSL2 en Windows)```bash

- Usuario con permisos sudo

- Conexión a Internet# 1️⃣ Clonar repositorio### �📱 **Aplicaciones de Ejemplo:**

- Al menos 4GB RAM disponible y 10GB de espacio en disco

git clone https://github.com/tuusuario/gitops-learning.git- ✅ **Dashboard** - UI de administración de Kubernetes

### Instalación Completa

cd gitops-learning- ✅ **Demo API Modern** - Aplicación Go con observabilidad completa

```bash

# 1. Clonar el repositorio

git clone https://github.com/andres20980/dotfiles.git

cd dotfiles# 2️⃣ Ejecutar instalación completa (15 min)---



# 2. Ejecutar instalador (modo desatendido)./scripts/install.sh

./install.sh --unattended

## ⚡ Instalación Rápida (Un Solo Comando)

# 3. ¡Listo! El entorno estará disponible en ~10-15 minutos

```# 🎉 ¡Ya tienes GitOps funcionando!



### Instalación por Fases``````bash



```bash# 1. Clonar el repositorio

# Ver las fases disponibles

./install.sh --list-stages**📊 URLs instantáneas** (después de la instalación):



# Ejecutar solo una fase específica- ArgoCD: http://localhost:30080 (sin login)

./install.sh --stage docker- Gitea: http://localhost:30083

- Prometheus: http://localhost:30092

# Ejecutar desde una fase hasta el final- Grafana: http://localhost:30093 (admin/admin123)

./install.sh --start-from cluster --unattended- Kubernetes Dashboard: http://localhost:30085 (skip login)

```- Argo Rollouts: http://localhost:30084

- App Demo: http://localhost:30082

---

Para instalar:

## 🌐 Acceso a Servicios

```bash

Después de la instalación, los servicios estarán disponibles en:git clone https://github.com/andres20980/dotfiles.git ~/dotfiles

cd ~/dotfiles && chmod +x install.sh && ./install.sh

| Servicio | URL | Credenciales | Puerto |```

|----------|-----|--------------|--------|

| **ArgoCD** | http://localhost:30080 | Sin autenticación | 30080 |**¡Eso es todo!** En ~10-15 minutos tendrás un entorno GitOps completo funcionando.

| **Gitea** | http://localhost:30083 | gitops / (generado) | 30083 |

| **Kubernetes Dashboard** | http://localhost:30085 | Skip login | 30085 |---

| **Prometheus** | http://localhost:30092 | - | 30092 |

| **Grafana** | http://localhost:30093 | admin / admin123 | 30093 |## 🔗 Accesos rápidos integrados

| **Argo Rollouts** | http://localhost:30084 | - | 30084 |

| **Kargo** | http://localhost:30094 | admin / admin123 | 30094 |- Usa `./install.sh --open <servicio>` para abrir ArgoCD, Gitea, Dashboard, Grafana, Prometheus o Argo Rollouts desde cualquier terminal.

| **Demo API** | http://localhost:30070 | - | 30070 |- El instalador añade aliases (`dashboard`, `argocd`, `gitea`, `grafana`, `prometheus`, `rollouts`) a tu shell para accesos rápidos.

- El Dashboard expone HTTP plano en `http://localhost:30085`, pensado para uso personal en entornos de laboratorio.

### Acceso Rápido desde CLI

## 📁 Repos GitOps generados

```bash

# Abrir servicios directamente- `~/gitops-repos/gitops-infrastructure/` → Manifests de infraestructura gestionados por ArgoCD.

./install.sh --open argocd- `~/gitops-repos/gitops-applications/` → Plantillas para aplicaciones personalizadas (opcional).

./install.sh --open dashboard- `~/gitops-repos/argo-config/` → Configuración declarativa de ArgoCD (AppProjects, ApplicationSets, ConfigMaps).

./install.sh --open gitea- `~/gitops-repos/sourcecode-apps/` → Código fuente de aplicaciones de desarrollo (por defecto `demo-api`).

./install.sh --open grafana

```---



---## 🏗️ **Arquitectura del Proyecto**



## 📁 Estructura del Proyecto## 🌐 URLs de Acceso (Después de la Instalación)



```### **📁 Estructura Perfecta**

dotfiles/

├── install.sh                      # 🎯 Instalador maestro```text

├── config.env                      # ⚙️  Configuración personalizabledotfiles/

├── argo-config/                    # 🔧 Configuración de ArgoCD├── install.sh                  # Instalador maestro que orquesta todo

│   ├── projects/                   # AppProjects├── argo-config/                # Config declarativa de ArgoCD (projects, appsets, configmaps)

│   ├── applications/               # ApplicationSets├── manifests/

│   ├── repositories/               # Git repositories│   ├── infrastructure/         # Stack de herramientas (ArgoCD, Grafana, Prometheus, Dashboard, Kargo, etc.)

│   └── configmaps/                 # Configuración de ArgoCD│   └── applications/

├── manifests/                      # 📦 Manifests Kubernetes│       └── demo-api/           # Manifests de la aplicación demo Node.js

│   ├── infrastructure/             # Herramientas GitOps├── sourcecode-apps/

│   │   ├── argo-rollouts/│   └── demo-api/               # Código fuente de la app demo (Node.js)

│   │   ├── sealed-secrets/├── scripts/                    # Utilidades (check-status, open dashboards, etc.)

│   │   ├── prometheus/├── config/                     # Configuración auxiliar (kind-config, etc.)

│   │   ├── grafana/└── docs/                       # Documentación (arquitectura, troubleshooting, learning path)

│   │   ├── kargo/```

│   │   └── ...

│   └── applications/               # Aplicaciones custom> 💡 Consejo: Usa `./scripts/check-windows-access.sh` para obtener las URLs exactas si accedes desde Windows/WSL.

│       └── demo-api/│   │   ├── prometheus/          # Stack de métricas# Acceso con token automático

├── sourcecode-apps/                # 💻 Código fuente de apps

│   └── demo-api/                   # App Node.js demo│   │   └── grafana/            # Visualizacióndashboard-full    # Abre Dashboard + token en clipboard

├── scripts/                        # 🔧 Utilidades

│   └── sync-to-gitea.sh           # Sincronizar cambios locales│   └── applications/            # Aplicaciones de negocio

├── docs/                           # 📚 Documentación

│   ├── ARCHITECTURE.md│       └── demo-api/         # App demo con observabilidad# Otros servicios

│   └── SECURITY.md

└── config/├── 💻 source-code/              # Código fuente puro (developer workflow)argocd           # Abre ArgoCD UI directamente

    └── kind-config.yaml            # Configuración del cluster

```│   └── demo-api/      # App Go con métricas Prometheusgitea            # Abre Gitea UI directamente



---│       ├── main.go             # Aplicación con /metrics endpointk8s-dash         # Alias corto para dashboard



## 🔧 Configuración Avanzada│       ├── Dockerfile          # Build optimizado multi-stage  ```



### Archivo `config.env`│       └── go.mod              # Dependencias mínimas



Personaliza la instalación editando `config.env`:├── 🔧 scripts/                  # Herramientas y utilidades---



```bash│   ├── install.sh              # Instalador maestro orquestador

# Feature flags

ENABLE_CUSTOM_APPS=true          # Habilitar aplicaciones de ejemplo│   ├── check-status.sh         # Verificar estado del sistema## 📋 Verificación del Sistema

ENABLE_MONITORING=true           # Habilitar Prometheus + Grafana

ENABLE_KARGO=true                # Habilitar Kargo│   └── (usa ./install.sh --open <servicio>)  # Accesos rápidos integrados

PARALLEL_INSTALL=true            # Instalación paralela de herramientas

├── ⚙️ config/                   # Configuraciones del entorno### **1. Verificar Estado General:**

# Puertos personalizados

ARGOCD_PORT=30080│   └── kind-config.yaml        # Cluster local optimizado```bash

GITEA_PORT=30083

GRAFANA_PORT=30093└── 📚 docs/                     # Documentación educativa./verify-setup.sh                    # Script de verificación completo



# Debugging    ├── ARCHITECTURE.md          # Arquitectura detallada./check-windows-access.sh           # URLs y credenciales para Windows

DEBUG_MODE=false                 # Modo debug con trazas completas

VERBOSE_LOGGING=false            # Logs detallados    ├── TROUBLESHOOTING.md      # Solución de problemas```

SKIP_CLEANUP_ON_ERROR=false      # Preservar cluster en errores

RUN_SMOKE_TESTS=true            # Tests automáticos al finalizar    └── LEARNING-PATH.md        # Ruta de aprendizaje



# Recursos```### **2. Verificar Aplicaciones ArgoCD:**

MIN_MEMORY_GB=4

MIN_DISK_GB=10```bash

```

### **🎯 Filosofía de Diseño**kubectl get applications -n argocd   # Deberían mostrar "Synced & Healthy"

### Uso de Variables

```

```bash

# Cargar configuración personalizada1. **🔧 Separación Clara**: Sistema ≠ GitOps ≠ Código ≠ Manifests

source config.env && ./install.sh --unattended

2. **📚 Educativo Primero**: Cada componente enseña un concepto GitOps específico  ### **3. Verificar Pods:**

# O exportar variables específicas

export DEBUG_MODE=true VERBOSE_LOGGING=true3. **⚡ Mínimo Viable**: Solo lo esencial para entender GitOps```bash

./install.sh --stage cluster

```4. **🏭 Enterprise Ready**: Patterns escalables a producciónkubectl get pods --all-namespaces   # Todos los pods deberían estar "Running"



---5. **🔄 Best Practices**: Siguiendo estándares de la industria```



## 📸 Snapshots y Recuperación



### Crear Snapshot------



```bash

# Crear snapshot con nombre automático

./install.sh --snapshot## 🎓 **Conceptos GitOps que Aprenderás**## 🔧 Solución de Problemas



# Crear snapshot con nombre personalizado

./install.sh --snapshot mi-backup-produccion

```### **1. 🏗️ Declarative Infrastructure**### **❌ Las aplicaciones no se sincronizan:**



Los snapshots incluyen:- **Manifests**: Toda la infraestructura como código YAML```bash

- Estado completo de recursos Kubernetes

- Configuración de ArgoCD (Applications, Projects)- **Git como Source of Truth**: Repositorio único de la verdad# Forzar sincronización manual de todas las aplicaciones

- Bundles de repositorios Git

- **Immutable Deployments**: Despliegues inmutables y rastreableskubectl patch application dashboard -n argocd --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'

### Restaurar desde Snapshot

kubectl patch application demo-api -n argocd --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'

```bash

# Restaurar desde snapshot### **2. 🚀 Continuous Deployment** kubectl patch application prometheus -n argocd --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'

./install.sh --restore ~/.gitops-snapshots/mi-backup-produccion

- **ArgoCD**: Controlador que mantiene el estado deseadokubectl patch application grafana -n argocd --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'

# O desde archivo comprimido

./install.sh --restore ~/.gitops-snapshots/mi-backup-produccion.tar.gz- **App-of-Apps Pattern**: Gestión jerárquica de aplicaciones```

```

- **Auto-Sync**: Sincronización automática Git → Kubernetes

---

### **❌ No puedo acceder desde Windows:**

## 🧪 Smoke Tests y Validación

### **3. 📊 Observability**```bash

El instalador ejecuta automáticamente smoke tests al finalizar:

- **Prometheus**: Recolección de métricas de aplicaciones + cluster# Obtener IP correcta de WSL

```bash

# Ejecutar solo smoke tests (requiere cluster activo)- **Grafana**: Visualización y dashboards personalizables./check-windows-access.sh

# Los tests se ejecutan automáticamente al finalizar

# Para deshabilitar: export RUN_SMOKE_TESTS=false- **Health Checks**: Aplicaciones con endpoints de salud

```

# Verificar que todos los puertos estén abiertos

Tests incluidos:

- ✅ Cluster kind activo### **4. 🔒 Security & RBAC**netstat -tlnp | grep -E ':(30080|30081|30082|30083|30090|30091)'

- ✅ ArgoCD API responde

- ✅ Gitea API funcional- **Projects Separation**: Infraestructura vs Aplicaciones```

- ✅ Todas las Applications Synced

- ✅ Todas las Applications Healthy- **Least Privilege**: Permisos mínimos necesarios

- ✅ Sealed Secrets operativo

- ✅ Prometheus y Grafana accesibles- **Secrets Management**: Gestión segura de credenciales### **❌ El Dashboard pide token:**



---```bash



## 🔄 Flujo de Trabajo GitOps---# Generar token de administrador



### Desarrollo Local → Gitea → ArgoCDkubectl -n kubernetes-dashboard create token admin-user



```bash## 🚀 **Guía de Uso Rápido**

# 1. Realizar cambios en manifests locales

vim manifests/infrastructure/grafana/deployment.yaml# O usar acceso sin token (más fácil)



# 2. Commit localmente### **📊 Verificar Estado**# En el Dashboard, simplemente haz clic en "SKIP"

git add .

git commit -m "feat: increase grafana replicas"```bash```



# 3. Sincronizar a Gitea# Estado general del sistema

./scripts/sync-to-gitea.sh

./scripts/check-status.sh### **❌ Gitea no responde:**

# 4. ArgoCD detecta cambios automáticamente y sincroniza

# Ver en: http://localhost:30080```bash

```

# Aplicaciones ArgoCD# Reiniciar Gitea

### Estructura de Repositorios Gitea

kubectl get applications -n argocdkubectl rollout restart deployment/gitea -n gitea

Los repositorios se crean automáticamente en `~/gitops-repos/`:

kubectl wait --for=condition=available --timeout=120s deployment/gitea -n gitea

- `gitops-infrastructure/` - Manifests de infraestructura

- `gitops-applications/` - Manifests de aplicaciones# Pods ejecutándose  ```

- `argo-config/` - Configuración de ArgoCD

- `sourcecode-apps/demo-api/` - Código fuente de aplicacioneskubectl get pods --all-namespaces



---```---



## 🐛 Debugging y Troubleshooting



### Modo Debug### **🔧 Comandos de Acceso** (después de `source ~/.zshrc`)## 📁 Estructura del Repositorio



```bash```bash

# Activar modo debug completo

DEBUG_MODE=true VERBOSE_LOGGING=true ./install.sh --stage clusterdashboard       # Dashboard K8s (skip login)```

```

argocd          # ArgoCD UI  dotfiles/

En caso de error, el instalador captura automáticamente:

- Logs de todos los podsprometheus      # Métricas├── install.sh                    # 🔥 Script de instalación principal

- Eventos del cluster

- Estado de Applications de ArgoCDgrafana         # Dashboards├── verify-setup.sh              # ✅ Verificación del sistema

- Configuración de services y endpoints

check-gitops    # Estado completo├── check-windows-access.sh      # 🌐 URLs para acceso desde Windows

Los logs se guardan en `/tmp/gitops-debug-<timestamp>/`

```├── (usa ./install.sh --open dashboard)   # 🚀 Acceso rápido al Dashboard  

### Comandos Útiles

├── (aliases en tu shell)        # 🔑 Usa 'dashboard', 'argocd', 'gitea', ...

```bash

# Ver estado de todas las aplicaciones### **🔄 Workflow de Desarrollo**├── kind-config.yaml             # ⚙️ Configuración del cluster

kubectl get applications -n argocd

```bash├── .gitops_aliases              # 📋 Aliases de comandos

# Ver logs de ArgoCD

kubectl logs -n argocd deployment/argocd-server -f# 1. Modificar código fuente├── argo-apps/                   # 📦 Definiciones de aplicaciones ArgoCD



# Ver estado del clustercd source-code/demo-api/│   ├── gitops-tools/           # Dashboard y herramientas

kubectl get pods -A

# ... hacer cambios ...│   └── custom-apps/            # Aplicaciones personalizadas

# Verificar NodePorts

kubectl get svc -A | grep NodePort└── README.md                    # 📚 Esta documentación



# Debug de aplicación específica# 2. Build + deploy automático```

kubectl describe app <app-name> -n argocd

```docker build -t demo-api:v2 .



### Problemas Comuneskind load docker-image demo-api:v2 --name mini-cluster---



**1. ArgoCD no sincroniza**

```bash

# Forzar refresh manual# 3. ArgoCD sincroniza automáticamente## 🎯 ¿Qué hace automáticamente `install.sh`?

kubectl patch app <app-name> -n argocd \

  -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' --type merge# Ver en: http://localhost:30080

```

```El script realiza una **instalación completa desde cero**:

**2. Pods en estado Pending**

```bash

# Verificar eventos

kubectl get events -A --sort-by='.lastTimestamp'---### **1. 🔧 Instalación de Herramientas Base:**



# Verificar recursos- Actualiza el sistema Ubuntu/WSL

kubectl describe pod <pod-name> -n <namespace>

```## 📊 **Stack Tecnológico**- Instala Docker, kubectl, kind



**3. Servicios no accesibles**- Configura zsh + Oh My Zsh con plugins

```bash

# Verificar mapeos de puertos en kind| Componente | Versión | Propósito | Puerto |- Instala Git Credential Manager

docker port <cluster-name>-control-plane

|------------|---------|-----------|--------|

# Verificar services

kubectl get svc -A -o wide| **kind** | v0.23.0 | Kubernetes local | - |### **2. 🏗️ Creación del Cluster Kubernetes:**

```

| **ArgoCD** | latest | GitOps controller | 30080 |- Crea cluster kind llamado "mini-cluster"

---

| **Gitea** | 1.21.11 | Git server local | 30083 |- Configura red para acceso desde Windows

## 🏗️ Arquitectura

| **Prometheus** | latest | Métricas | 30092 |- Expone servicios como NodePort

### Flujo GitOps

| **Grafana** | latest | Dashboards | 30093 |

```

┌─────────────┐         ┌─────────────┐         ┌─────────────┐| **Dashboard** | latest | K8s UI | 30085 |

│   Código    │         │   Gitea     │         │   ArgoCD    │

│   Local     │ ──push─>│  (Git Repo) │<─watch──│ (Controller)│| **Demo API** | custom | Demo app | 30082 |- Instala ArgoCD desde manifests oficiales

└─────────────┘         └─────────────┘         └──────┬──────┘

                                                        │- Configura credenciales admin/admin123

                                                     deploy

                                                        │### **🎯 Características Mínimas pero Funcionales**- Expone UI en puertos 30080 (HTTP) y 30443 (HTTPS)

                                                        ▼

                                                ┌───────────────┐- ✅ **ArgoCD**: UI web + auto-sync + RBAC básico

                                                │  Kubernetes   │

                                                │   Cluster     │- ✅ **Prometheus**: Service discovery + métricas K8s + apps### **4. 📚 Instalación de Gitea:**

                                                └───────────────┘

```- ✅ **Grafana**: Datasource automático + acceso admin- Despliega Gitea como servidor Git local



### Componentes Principales- ✅ **Gitea**: Repos privados + webhooks + usuario demo- Crea usuario gitops con password seguro generado



1. **kind** - Cluster Kubernetes local en Docker- ✅ **Dashboard**: Skip-login + cluster-admin + métricas- Expone en puerto 30083

2. **ArgoCD** - Lee manifests de Gitea y los aplica al cluster

3. **Gitea** - Source of truth para todos los manifests- ✅ **Apps**: Health checks + Prometheus metrics + logs

4. **Sealed Secrets** - Encripta secrets para almacenarlos en Git

5. **Prometheus + Grafana** - Observabilidad del stack### **5. 🌐 Configuración de NGINX Ingress:**



Para más detalles, ver [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)---- Instala controlador de ingreso



---- Configura para acceso por hostname



## 🔐 Seguridad## 🛠️ **Solución de Problemas**- Expone en puerto 30090



- ✅ **Sin credenciales hardcodeadas** - Todas se generan dinámicamente

- ✅ **Passwords seguros** - Múltiples fuentes de entropía

- ✅ **Sealed Secrets** - Secrets encriptados en Git### **❌ "Las aplicaciones no se sincronizan"**### **6. 📦 Creación de Repositorios Git:**

- ✅ **No-auth para demos** - ArgoCD sin autenticación para laboratorio local

- ✅ **Rotación automática** - Nuevas credenciales en cada instalación```bash- Crea repositorio `gitops-tools` (Dashboard)



Ver [docs/SECURITY.md](docs/SECURITY.md) para más información.# Forzar refresh de ArgoCD- Crea repositorio `custom-apps` (Demo API)



---kubectl patch application demo-api -n argocd --type merge \- Sube manifests iniciales a Gitea



## 🤝 Contribuir  -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'



¡Las contribuciones son bienvenidas! Por favor:```### **7. 📊 Instalación de Stack de Observabilidad:**



1. Fork el repositorio- Despliega Prometheus para recolección de métricas

2. Crea una rama para tu feature (`git checkout -b feature/amazing-feature`)

3. Commit tus cambios (`git commit -m 'feat: add amazing feature'`)### **❌ "No puedo acceder desde Windows"**- Instala Grafana con datasource automático

4. Push a la rama (`git push origin feature/amazing-feature`)

5. Abre un Pull Request```bash- Construye aplicación Demo API moderna con métricas



---# Verificar IP de WSL- Configura RBAC para monitoreo de cluster



## 📚 Recursos y Aprendizajehostname -I | awk '{print $1}'



- [Documentación de ArgoCD](https://argo-cd.readthedocs.io/)### **8. 🎯 Configuración de Aplicaciones ArgoCD:**

- [Guía de GitOps](https://www.gitops.tech/)

- [Kubernetes Documentation](https://kubernetes.io/docs/)# Usar URLs con localhost (más compatibles)- Crea proyectos ArgoCD

- [Prometheus Docs](https://prometheus.io/docs/)

- [Sealed Secrets](https://sealed-secrets.netlify.app/)# http://localhost:30080 en lugar de http://IP:30080- Configura secrets de autenticación de repositorios



---```- Despliega aplicaciones Dashboard, Demo API, Prometheus y Grafana



## 📝 Licencia- Configura sincronización automática



MIT License - Ver [LICENSE](LICENSE) para más detalles.### **❌ "Prometheus no encuentra métricas"**



---```bash### **9. 🚀 Scripts de Acceso Automático:**



## 🙏 Agradecimientos# Verificar service discovery- Crea scripts para abrir Dashboard automáticamente



- **ArgoCD Team** - Por la increíble herramienta GitOpskubectl logs deployment/prometheus -n monitoring- Configura aliases de comandos

- **Kubernetes Community** - Por kind y todo el ecosistema

- **Gitea Project** - Por el servidor Git ligero y potente- Genera tokens de acceso automáticos

- **CNCF** - Por promover las mejores prácticas cloud native

# Verificar endpoint de métricas de app- Configura apertura de navegador desde WSL

---

curl http://localhost:30082/metrics

## 📞 Soporte

```---

¿Encontraste un problema? ¿Tienes una sugerencia?



- 🐛 [Reportar un bug](https://github.com/andres20980/dotfiles/issues/new?labels=bug)

- 💡 [Solicitar una feature](https://github.com/andres20980/dotfiles/issues/new?labels=enhancement)---## 🎉 Resultado Final

- 📖 [Ver documentación completa](docs/)



---

## 🎓 **Ruta de Aprendizaje Recomendada**Después de ejecutar `install.sh`, tendrás:

<div align="center">



**⭐ Si este proyecto te ayudó, considera darle una estrella ⭐**

### **👶 Nivel Beginner**### **✅ Estado Esperado:**

Hecho con ❤️ para la comunidad GitOps

1. **Ejecutar instalación completa** (`./scripts/install.sh`)- **ArgoCD Applications:** `Synced & Healthy`

</div>

2. **Explorar ArgoCD UI** (http://localhost:30080)- **Todos los Pods:** `Running` 

3. **Ver aplicaciones sincronizadas** (Dashboard, Demo API)- **Servicios:** Accesibles desde Windows

4. **Modificar replicas** en manifests y ver auto-sync- **Git Repositories:** Configurados y funcionando

- **Acceso Automático:** Comandos `dashboard`, `argocd`, `gitea` funcionando

### **🧑‍💻 Nivel Intermediate** 

1. **Crear nueva aplicación** en `source-code/`### **🌐 Acceso desde Windows:**

2. **Agregar manifests** en `manifests/applications/`- Abres un navegador en Windows

3. **Configurar ArgoCD Application** en `gitops/applications/`- Usas las IPs proporcionadas por `check-windows-access.sh`

4. **Ver despliegue automático**- Dashboard accesible con "SKIP" login

- ArgoCD y Gitea con credenciales automáticas

### **👨‍🔬 Nivel Advanced**

1. **Implementar App-of-Apps** pattern completo### **🔄 GitOps Funcional:**

2. **Configurar Prometheus alerts** personalizadas  - Cambios en Git → Sincronización automática en Kubernetes

3. **Crear Grafana dashboards** para nuevas métricas- UI de ArgoCD para monitorear aplicaciones

4. **Integrar GitOps** en pipeline CI/CD real- Repositorios Git locales totalmente funcionales



------



## 🤝 **Contribución**## 💡 Consejos de Uso



Este proyecto busca **excelencia educativa**. Contribuciones welcome:### **📈 Para Desarrollo:**

1. Clona repos en Gitea: `http://IP_WSL:30083`

1. 🐛 **Bug Reports**: Anything que rompa la experiencia de aprendizaje2. Modifica manifests de Kubernetes

2. 📚 **Documentación**: Mejoras en explicaciones o ejemplos3. Push a Git → ArgoCD sincroniza automáticamente

3. 🚀 **Features**: Solo si mantienen la simplicidad educativa4. Monitorea en ArgoCD UI: `http://IP_WSL:30080`

4. 🧹 **Clean Code**: Refactors que mejoren legibilidad

### **🔄 Para Probar GitOps:**

### **📋 Guidelines**1. Edita archivos en `/tmp/gitops-tools-repo/` 

- **Simplicidad**: Si no ayuda a aprender GitOps, no lo incluyas2. `git add . && git commit -m "test" && git push`

- **Best Practices**: Todo debe seguir estándares de industria  3. Ve a ArgoCD UI y observa la sincronización automática

- **Documentación**: Cambios requieren updates en docs

- **Testing**: Probar instalación completa en entorno limpio### **🛠️ Para Debugging:**

```bash

---kubectl logs -f deployment/argocd-application-controller -n argocd  # Logs ArgoCD

kubectl get events --all-namespaces --sort-by='.lastTimestamp'     # Eventos del cluster

## 📄 **Licencia**```



MIT License - Ver [LICENSE](LICENSE) para detalles.---



---## 📊 Stack de Observabilidad Enterprise



## 🙏 **Reconocimientos**### **🎯 ¿Qué métricas obtienes automáticamente?**



- **ArgoCD Team**: Por el mejor GitOps controller#### **📈 Prometheus - Métricas del Sistema:**

- **Kubernetes Community**: Por kind y toda la toolchain- **Métricas de Kubernetes:** CPU, memoria, red de todos los pods

- **Prometheus/Grafana**: Por observability de clase mundial- **Métricas de Aplicaciones:** Demo API expone métricas HTTP automáticamente

- **GitOps Working Group**: Por definir los estándares- **Métricas del Cluster:** Estado de nodos, eventos, recursos

- **Alertas Básicas:** Configuradas para detectar problemas comunes

---

#### **📊 Grafana - Visualización:**

**🎉 ¡Feliz aprendizaje GitOps!** - **Acceso:** http://localhost:30091 (admin/admin123)

- **Datasource Automático:** Prometheus preconfigurado

> *"GitOps no es solo una herramienta, es una filosofía de trabajo que cambiará cómo despliegas software para siempre."*- **Dashboards Listos:** Para usar inmediatamente

- **Personalización:** Crea tus propios dashboards fácilmente

---

#### **🔍 Demo API Moderna - Métricas de Aplicación:**

## 🔗 **Enlaces Útiles**- **Endpoint Métricas:** `/metrics` - Formato Prometheus nativo

- **Health Checks:** `/health` y `/ready` para monitoreo

- 📖 [Documentación ArgoCD](https://argo-cd.readthedocs.io/)- **API Funcional:** Guestbook interactivo en `/api/entries`

- 🎯 [GitOps Principles](https://opengitops.dev/)- **Instrumentación:** Middleware automático para todas las requests

- 🚀 [Kubernetes Learning](https://kubernetes.io/docs/tutorials/)

- 📊 [Prometheus Best Practices](https://prometheus.io/docs/practices/)### **📋 Cómo usar el Stack de Observabilidad:**

- 🎨 [Grafana Tutorials](https://grafana.com/tutorials/)
```bash
# Ver métricas en tiempo real
curl http://localhost:30082/metrics

# Acceder a Prometheus para queries
# http://localhost:30090 - Busca: http_requests_total

# Crear dashboards en Grafana  
# http://localhost:30091 - Login: admin/admin123

# Ver health de la aplicación
curl http://localhost:30082/health
```

---

## ⚙️ Personalización

### **🔧 Agregar Nueva Aplicación:**
1. Crea manifests en `custom-apps/nueva-app/manifests/`
2. Commit y push al repo `custom-apps`
3. Crea Application en ArgoCD apuntando a la nueva carpeta

### **🌐 Cambiar URLs de Acceso:**
- Edita `kind-config.yaml` para cambiar puertos
- Modifica services en `argo-apps/` para cambiar NodePorts

### **🔑 Cambiar Credenciales:**
- ArgoCD: Edita secret `argocd-secret` en namespace `argocd`  
- Gitea: Usa UI web o kubectl exec para cambiar en DB

---

## 📞 Soporte

Si tienes problemas:

1. **🔍 Ejecuta verificación:** `./verify-setup.sh`
2. **📋 Revisa logs:** `kubectl logs -n argocd deployment/argocd-application-controller`
3. **🔄 Reinicia servicios:** `kubectl rollout restart deployment/NOMBRE -n NAMESPACE`
4. **💾 Re-ejecuta:** Si todo falla, ejecuta `install.sh` de nuevo

---

## 🏆 Características Avanzadas

- ✅ **Auto-login al Dashboard** (sin copiar tokens)
- ✅ **Apertura automática de navegador** desde WSL
- ✅ **Sincronización GitOps automática**
- ✅ **Acceso directo desde Windows** (sin port-forwarding)
- ✅ **Repositorios Git locales** (sin dependencias externas)
- ✅ **Aliases de comandos** para acceso rápido
- ✅ **Scripts de verificación** y debugging
- ✅ **Configuración persistente** (sobrevive reinicios)

¡Disfruta de tu nuevo entorno GitOps! 🚀