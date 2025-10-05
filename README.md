# 🚀 GitOps Learning Environment - **Excelencia Educativa**# 🚀 Entorno de Desarrollo GitOps Completo



[![GitOps](https://img.shields.io/badge/GitOps-ArgoCD-blue.svg)](https://argoproj.github.io/cd/)Este repositorio contiene la configuración automática para crear un **entorno GitOps completo** con Kubernetes, ArgoCD, Gitea y aplicaciones de ejemplo. Todo se instala y configura automáticamente con un solo comando.

[![Kubernetes](https://img.shields.io/badge/Kubernetes-kind-326ce5.svg)](https://kind.sigs.k8s.io/)

[![Observability](https://img.shields.io/badge/Observability-Prometheus%2BGrafana-orange.svg)](https://prometheus.io/)## 🎯 ¿Qué incluye este entorno?

[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

### 🔧 **Herramientas Base:**

> **🎯 El entorno GitOps más simple, limpio y educativo para aprender en local**- ✅ **Docker** - Containerización

> - ✅ **kubectl** - Cliente Kubernetes

> Diseñado siguiendo **best practices** para que novatos puedan entender **cómo funciona GitOps** desde cero con un ecosistema **mínimo pero funcional**.- ✅ **kind** - Kubernetes local en Docker

- ✅ **zsh + Oh My Zsh** - Shell mejorado con plugins

## 📋 **¿Qué aprenderás?**- ✅ **Git Credential Manager** - Gestión de credenciales



- 🏗️ **Arquitectura GitOps**: Separación clara entre código e infraestructura### 🏗️ **Stack GitOps:**

- 🚀 **ArgoCD**: Despliegue declarativo automático  - ✅ **Kubernetes Cluster** (kind) - Cluster local completo

- 📊 **Observabilidad**: Métricas con Prometheus + Grafana- ✅ **ArgoCD** - Controlador GitOps con UI web

- 🐳 **Containers**: Docker + Kubernetes locales- ✅ **Gitea** - Servidor Git local (como GitHub local)

- 📦 **Manifests**: Kubernetes YAML best practices- ✅ **NGINX Ingress** - Controlador de ingreso

- 🔧 **Automatización**: Scripts modulares y mantenibles- ✅ **Kubernetes Dashboard** - UI web de Kubernetes



---### � **Herramientas de Observabilidad:**

- ✅ **Prometheus** - Recolección de métricas y alertas

## ⚡ **Instalación Ultra-Rápida**- ✅ **Grafana** - Dashboards y visualización de métricas

- ✅ **Métricas Nativas** - Aplicaciones con métricas Prometheus integradas

```bash

# 1️⃣ Clonar repositorio### �📱 **Aplicaciones de Ejemplo:**

git clone https://github.com/tuusuario/gitops-learning.git- ✅ **Dashboard** - UI de administración de Kubernetes

cd gitops-learning- ✅ **Demo API Modern** - Aplicación Go con observabilidad completa



# 2️⃣ Ejecutar instalación completa (15 min)---

./scripts/install.sh

## ⚡ Instalación Rápida (Un Solo Comando)

# 🎉 ¡Ya tienes GitOps funcionando!

``````bash

# 1. Clonar el repositorio

**📊 URLs instantáneas** (después de la instalación):

- ArgoCD: http://localhost:30080 (sin login)
- Gitea: http://localhost:30083
- Prometheus: http://localhost:30081
- Grafana: http://localhost:30082 (admin/admin123)
- Kubernetes Dashboard: http://localhost:30086 (skip login)
- Argo Rollouts: http://localhost:30084
- App Demo: http://localhost:30082

Para instalar:

```bash
git clone https://github.com/andres20980/dotfiles.git ~/dotfiles
cd ~/dotfiles && chmod +x install.sh && ./install.sh
```

**¡Eso es todo!** En ~10-15 minutos tendrás un entorno GitOps completo funcionando.

---

## 🔗 Accesos rápidos integrados

- Usa `./install.sh --open <servicio>` para abrir ArgoCD, Gitea, Dashboard, Grafana, Prometheus o Argo Rollouts desde cualquier terminal.
- El instalador añade aliases (`dashboard`, `argocd`, `gitea`, `grafana`, `prometheus`, `rollouts`) a tu shell para accesos rápidos.
- El Dashboard expone HTTP plano en `http://localhost:30085`, pensado para uso personal en entornos de laboratorio.

## 📁 Repos GitOps generados

- `~/gitops-repos/gitops-infrastructure/` → Manifests de infraestructura gestionados por ArgoCD.
- `~/gitops-repos/gitops-applications/` → Plantillas para aplicaciones personalizadas (opcional).
- `~/gitops-repos/argo-config/` → Configuración declarativa de ArgoCD (AppProjects, ApplicationSets, ConfigMaps).
- `~/gitops-repos/sourcecode-apps/` → Código fuente de aplicaciones de desarrollo (por defecto `demo-api`).

---

## 🏗️ **Arquitectura del Proyecto**

## 🌐 URLs de Acceso (Después de la Instalación)

### **📁 Estructura Perfecta**

```text
dotfiles/
├── install.sh                  # Instalador maestro que orquesta todo
├── argo-config/                # Config declarativa de ArgoCD (projects, appsets, configmaps)
├── manifests/
│   ├── infrastructure/         # Stack de herramientas (ArgoCD, Grafana, Prometheus, Dashboard, Kargo, etc.)
│   └── applications/
│       └── demo-api/           # Manifests de la aplicación demo Node.js
├── sourcecode-apps/
│   └── demo-api/               # Código fuente de la app demo (Node.js)
├── scripts/                    # Utilidades (check-status, open dashboards, etc.)
├── config/                     # Configuración auxiliar (kind-config, etc.)
└── docs/                       # Documentación (arquitectura, troubleshooting, learning path)
```

> 💡 Consejo: Usa `./scripts/check-windows-access.sh` para obtener las URLs exactas si accedes desde Windows/WSL.
│   │   ├── prometheus/          # Stack de métricas# Acceso con token automático

│   │   └── grafana/            # Visualizacióndashboard-full    # Abre Dashboard + token en clipboard

│   └── applications/            # Aplicaciones de negocio

│       └── demo-api/         # App demo con observabilidad# Otros servicios

├── 💻 source-code/              # Código fuente puro (developer workflow)argocd           # Abre ArgoCD UI directamente

│   └── demo-api/      # App Go con métricas Prometheusgitea            # Abre Gitea UI directamente

│       ├── main.go             # Aplicación con /metrics endpointk8s-dash         # Alias corto para dashboard

│       ├── Dockerfile          # Build optimizado multi-stage  ```

│       └── go.mod              # Dependencias mínimas

├── 🔧 scripts/                  # Herramientas y utilidades---

│   ├── install.sh              # Instalador maestro orquestador

│   ├── check-status.sh         # Verificar estado del sistema## 📋 Verificación del Sistema

│   └── (usa ./install.sh --open <servicio>)  # Accesos rápidos integrados

├── ⚙️ config/                   # Configuraciones del entorno### **1. Verificar Estado General:**

│   └── kind-config.yaml        # Cluster local optimizado```bash

└── 📚 docs/                     # Documentación educativa./verify-setup.sh                    # Script de verificación completo

    ├── ARCHITECTURE.md          # Arquitectura detallada./check-windows-access.sh           # URLs y credenciales para Windows

    ├── TROUBLESHOOTING.md      # Solución de problemas```

    └── LEARNING-PATH.md        # Ruta de aprendizaje

```### **2. Verificar Aplicaciones ArgoCD:**

```bash

### **🎯 Filosofía de Diseño**kubectl get applications -n argocd   # Deberían mostrar "Synced & Healthy"

```

1. **🔧 Separación Clara**: Sistema ≠ GitOps ≠ Código ≠ Manifests

2. **📚 Educativo Primero**: Cada componente enseña un concepto GitOps específico  ### **3. Verificar Pods:**

3. **⚡ Mínimo Viable**: Solo lo esencial para entender GitOps```bash

4. **🏭 Enterprise Ready**: Patterns escalables a producciónkubectl get pods --all-namespaces   # Todos los pods deberían estar "Running"

5. **🔄 Best Practices**: Siguiendo estándares de la industria```



------



## 🎓 **Conceptos GitOps que Aprenderás**## 🔧 Solución de Problemas



### **1. 🏗️ Declarative Infrastructure**### **❌ Las aplicaciones no se sincronizan:**

- **Manifests**: Toda la infraestructura como código YAML```bash

- **Git como Source of Truth**: Repositorio único de la verdad# Forzar sincronización manual de todas las aplicaciones

- **Immutable Deployments**: Despliegues inmutables y rastreableskubectl patch application dashboard -n argocd --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'

kubectl patch application demo-api -n argocd --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'

### **2. 🚀 Continuous Deployment** kubectl patch application prometheus -n argocd --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'

- **ArgoCD**: Controlador que mantiene el estado deseadokubectl patch application grafana -n argocd --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'

- **App-of-Apps Pattern**: Gestión jerárquica de aplicaciones```

- **Auto-Sync**: Sincronización automática Git → Kubernetes

### **❌ No puedo acceder desde Windows:**

### **3. 📊 Observability**```bash

- **Prometheus**: Recolección de métricas de aplicaciones + cluster# Obtener IP correcta de WSL

- **Grafana**: Visualización y dashboards personalizables./check-windows-access.sh

- **Health Checks**: Aplicaciones con endpoints de salud

# Verificar que todos los puertos estén abiertos

### **4. 🔒 Security & RBAC**netstat -tlnp | grep -E ':(30080|30081|30082|30083|30090|30091)'

- **Projects Separation**: Infraestructura vs Aplicaciones```

- **Least Privilege**: Permisos mínimos necesarios

- **Secrets Management**: Gestión segura de credenciales### **❌ El Dashboard pide token:**

```bash

---# Generar token de administrador

kubectl -n kubernetes-dashboard create token admin-user

## 🚀 **Guía de Uso Rápido**

# O usar acceso sin token (más fácil)

### **📊 Verificar Estado**# En el Dashboard, simplemente haz clic en "SKIP"

```bash```

# Estado general del sistema

./scripts/check-status.sh### **❌ Gitea no responde:**

```bash

# Aplicaciones ArgoCD# Reiniciar Gitea

kubectl get applications -n argocdkubectl rollout restart deployment/gitea -n gitea

kubectl wait --for=condition=available --timeout=120s deployment/gitea -n gitea

# Pods ejecutándose  ```

kubectl get pods --all-namespaces

```---



### **🔧 Comandos de Acceso** (después de `source ~/.zshrc`)## 📁 Estructura del Repositorio

```bash

dashboard       # Dashboard K8s (skip login)```

argocd          # ArgoCD UI  dotfiles/

prometheus      # Métricas├── install.sh                    # 🔥 Script de instalación principal

grafana         # Dashboards├── verify-setup.sh              # ✅ Verificación del sistema

check-gitops    # Estado completo├── check-windows-access.sh      # 🌐 URLs para acceso desde Windows

```├── (usa ./install.sh --open dashboard)   # 🚀 Acceso rápido al Dashboard  

├── (aliases en tu shell)        # 🔑 Usa 'dashboard', 'argocd', 'gitea', ...

### **🔄 Workflow de Desarrollo**├── kind-config.yaml             # ⚙️ Configuración del cluster

```bash├── .gitops_aliases              # 📋 Aliases de comandos

# 1. Modificar código fuente├── argo-apps/                   # 📦 Definiciones de aplicaciones ArgoCD

cd source-code/demo-api/│   ├── gitops-tools/           # Dashboard y herramientas

# ... hacer cambios ...│   └── custom-apps/            # Aplicaciones personalizadas

└── README.md                    # 📚 Esta documentación

# 2. Build + deploy automático```

docker build -t demo-api:v2 .

kind load docker-image demo-api:v2 --name mini-cluster---



# 3. ArgoCD sincroniza automáticamente## 🎯 ¿Qué hace automáticamente `install.sh`?

# Ver en: http://localhost:30080

```El script realiza una **instalación completa desde cero**:



---### **1. 🔧 Instalación de Herramientas Base:**

- Actualiza el sistema Ubuntu/WSL

## 📊 **Stack Tecnológico**- Instala Docker, kubectl, kind

- Configura zsh + Oh My Zsh con plugins

| Componente | Versión | Propósito | Puerto |- Instala Git Credential Manager

|------------|---------|-----------|--------|

| **kind** | v0.23.0 | Kubernetes local | - |### **2. 🏗️ Creación del Cluster Kubernetes:**

| **ArgoCD** | latest | GitOps controller | 30080 |- Crea cluster kind llamado "mini-cluster"

| **Gitea** | 1.21.11 | Git server local | 30083 |- Configura red para acceso desde Windows

| **Prometheus** | latest | Métricas | 30081 |- Expone servicios como NodePort

| **Grafana** | latest | Dashboards | 30082 |

| **Dashboard** | latest | K8s UI | 30086 |

| **Demo API** | custom | Demo app | 30082 |- Instala ArgoCD desde manifests oficiales

- Configura credenciales admin/admin123

### **🎯 Características Mínimas pero Funcionales**- Expone UI en puertos 30080 (HTTP) y 30443 (HTTPS)

- ✅ **ArgoCD**: UI web + auto-sync + RBAC básico

- ✅ **Prometheus**: Service discovery + métricas K8s + apps### **4. 📚 Instalación de Gitea:**

- ✅ **Grafana**: Datasource automático + acceso admin- Despliega Gitea como servidor Git local

- ✅ **Gitea**: Repos privados + webhooks + usuario demo- Crea usuario gitops con password seguro generado

- ✅ **Dashboard**: Skip-login + cluster-admin + métricas- Expone en puerto 30083

- ✅ **Apps**: Health checks + Prometheus metrics + logs

### **5. 🌐 Configuración de NGINX Ingress:**

---- Instala controlador de ingreso

- Configura para acceso por hostname

## 🛠️ **Solución de Problemas**- Expone en puerto 30090



### **❌ "Las aplicaciones no se sincronizan"**### **6. 📦 Creación de Repositorios Git:**

```bash- Crea repositorio `gitops-tools` (Dashboard)

# Forzar refresh de ArgoCD- Crea repositorio `custom-apps` (Demo API)

kubectl patch application demo-api -n argocd --type merge \- Sube manifests iniciales a Gitea

  -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'

```### **7. 📊 Instalación de Stack de Observabilidad:**

- Despliega Prometheus para recolección de métricas

### **❌ "No puedo acceder desde Windows"**- Instala Grafana con datasource automático

```bash- Construye aplicación Demo API moderna con métricas

# Verificar IP de WSL- Configura RBAC para monitoreo de cluster

hostname -I | awk '{print $1}'

### **8. 🎯 Configuración de Aplicaciones ArgoCD:**

# Usar URLs con localhost (más compatibles)- Crea proyectos ArgoCD

# http://localhost:30080 en lugar de http://IP:30080- Configura secrets de autenticación de repositorios

```- Despliega aplicaciones Dashboard, Demo API, Prometheus y Grafana

- Configura sincronización automática

### **❌ "Prometheus no encuentra métricas"**

```bash### **9. 🚀 Scripts de Acceso Automático:**

# Verificar service discovery- Crea scripts para abrir Dashboard automáticamente

kubectl logs deployment/prometheus -n monitoring- Configura aliases de comandos

- Genera tokens de acceso automáticos

# Verificar endpoint de métricas de app- Configura apertura de navegador desde WSL

curl http://localhost:30082/metrics

```---



---## 🎉 Resultado Final



## 🎓 **Ruta de Aprendizaje Recomendada**Después de ejecutar `install.sh`, tendrás:



### **👶 Nivel Beginner**### **✅ Estado Esperado:**

1. **Ejecutar instalación completa** (`./scripts/install.sh`)- **ArgoCD Applications:** `Synced & Healthy`

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
