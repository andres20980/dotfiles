# 🚀 Entorno de Desarrollo GitOps Completo

Este repositorio contiene la configuración automática para crear un **entorno GitOps completo** con Kubernetes, ArgoCD, Gitea y aplicaciones de ejemplo. Todo se instala y configura automáticamente con un solo comando.

## 🎯 ¿Qué incluye este entorno?

### 🔧 **Herramientas Base:**
- ✅ **Docker** - Containerización
- ✅ **kubectl** - Cliente Kubernetes
- ✅ **kind** - Kubernetes local en Docker
- ✅ **zsh + Oh My Zsh** - Shell mejorado con plugins
- ✅ **Git Credential Manager** - Gestión de credenciales

### 🏗️ **Stack GitOps:**
- ✅ **Kubernetes Cluster** (kind) - Cluster local completo
- ✅ **ArgoCD** - Controlador GitOps con UI web
- ✅ **Gitea** - Servidor Git local (como GitHub local)
- ✅ **NGINX Ingress** - Controlador de ingreso
- ✅ **Kubernetes Dashboard** - UI web de Kubernetes

### 📱 **Aplicaciones de Ejemplo:**
- ✅ **Dashboard** - UI de administración de Kubernetes
- ✅ **Hello World** - Aplicación de prueba con Nginx

---

## ⚡ Instalación Rápida (Un Solo Comando)

```bash
# 1. Clonar el repositorio
git clone https://github.com/andres20980/dotfiles.git ~/dotfiles

# 2. Ejecutar la instalación completa
cd ~/dotfiles && chmod +x install.sh && ./install.sh
```

**¡Eso es todo!** En ~10-15 minutos tendrás un entorno GitOps completo funcionando.

---

## 🌐 URLs de Acceso (Después de la Instalación)

Una vez instalado, podrás acceder a todos los servicios desde Windows usando estas URLs:

| Servicio | URL | Credenciales |
|----------|-----|--------------|
| **ArgoCD** | `http://IP_WSL:30080` | `admin` / `admin123` |
| **Gitea** | `http://IP_WSL:30083` | `gitops` / `gitops123` |
| **Dashboard** | `https://IP_WSL:30081` | Click "SKIP" o usar token |
| **Hello World** | `http://IP_WSL:30082` | Sin credenciales |

> **💡 Tip:** Usa `./check-windows-access.sh` para obtener las URLs exactas con tu IP de WSL.

---

## 🚀 Comandos de Acceso Rápido

Después de la instalación, tendrás estos **aliases automáticos**:

```bash
# Acceso súper rápido al Dashboard (recomendado)
dashboard         # Abre Dashboard - haz clic en "SKIP" 

# Acceso con token automático
dashboard-full    # Abre Dashboard + token en clipboard

# Otros servicios
argocd           # Abre ArgoCD UI directamente
gitea            # Abre Gitea UI directamente
k8s-dash         # Alias corto para dashboard
```

---

## 📋 Verificación del Sistema

### **1. Verificar Estado General:**
```bash
./verify-setup.sh                    # Script de verificación completo
./check-windows-access.sh           # URLs y credenciales para Windows
```

### **2. Verificar Aplicaciones ArgoCD:**
```bash
kubectl get applications -n argocd   # Deberían mostrar "Synced & Healthy"
```

### **3. Verificar Pods:**
```bash
kubectl get pods --all-namespaces   # Todos los pods deberían estar "Running"
```

---

## 🔧 Solución de Problemas

### **❌ Las aplicaciones no se sincronizan:**
```bash
# Forzar sincronización manual
kubectl patch application dashboard -n argocd --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
kubectl patch application hello-world -n argocd --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
```

### **❌ No puedo acceder desde Windows:**
```bash
# Obtener IP correcta de WSL
./check-windows-access.sh

# Verificar que los puertos estén abiertos
netstat -tlnp | grep -E ':(30080|30081|30082|30083)'
```

### **❌ El Dashboard pide token:**
```bash
# Generar token de administrador
kubectl -n kubernetes-dashboard create token admin-user

# O usar acceso sin token (más fácil)
# En el Dashboard, simplemente haz clic en "SKIP"
```

### **❌ Gitea no responde:**
```bash
# Reiniciar Gitea
kubectl rollout restart deployment/gitea -n gitea
kubectl wait --for=condition=available --timeout=120s deployment/gitea -n gitea
```

---

## 📁 Estructura del Repositorio

```
dotfiles/
├── install.sh                    # 🔥 Script de instalación principal
├── verify-setup.sh              # ✅ Verificación del sistema
├── check-windows-access.sh      # 🌐 URLs para acceso desde Windows
├── dashboard.sh                 # 🚀 Acceso rápido al Dashboard  
├── open-dashboard.sh            # 🔑 Dashboard con token automático
├── kind-config.yaml             # ⚙️ Configuración del cluster
├── .gitops_aliases              # 📋 Aliases de comandos
├── argo-apps/                   # 📦 Definiciones de aplicaciones ArgoCD
│   ├── gitops-tools/           # Dashboard y herramientas
│   └── custom-apps/            # Aplicaciones personalizadas
└── README.md                    # 📚 Esta documentación
```

---

## 🎯 ¿Qué hace automáticamente `install.sh`?

El script realiza una **instalación completa desde cero**:

### **1. 🔧 Instalación de Herramientas Base:**
- Actualiza el sistema Ubuntu/WSL
- Instala Docker, kubectl, kind
- Configura zsh + Oh My Zsh con plugins
- Instala Git Credential Manager

### **2. 🏗️ Creación del Cluster Kubernetes:**
- Crea cluster kind llamado "mini-cluster"
- Configura red para acceso desde Windows
- Expone servicios como NodePort

### **3. 🚢 Instalación de ArgoCD:**
- Instala ArgoCD desde manifests oficiales
- Configura credenciales admin/admin123
- Expone UI en puertos 30080 (HTTP) y 30443 (HTTPS)

### **4. 📚 Instalación de Gitea:**
- Despliega Gitea como servidor Git local
- Crea usuario gitops/gitops123
- Expone en puerto 30083

### **5. 🌐 Configuración de NGINX Ingress:**
- Instala controlador de ingreso
- Configura para acceso por hostname
- Expone en puerto 30090

### **6. 📦 Creación de Repositorios Git:**
- Crea repositorio `gitops-tools` (Dashboard)
- Crea repositorio `custom-apps` (Hello World)
- Sube manifests iniciales a Gitea

### **7. 🎯 Configuración de Aplicaciones ArgoCD:**
- Crea proyectos ArgoCD
- Configura secrets de autenticación de repositorios
- Despliega aplicaciones Dashboard y Hello World
- Configura sincronización automática

### **8. 🚀 Scripts de Acceso Automático:**
- Crea scripts para abrir Dashboard automáticamente
- Configura aliases de comandos
- Genera tokens de acceso automáticos
- Configura apertura de navegador desde WSL

---

## 🎉 Resultado Final

Después de ejecutar `install.sh`, tendrás:

### **✅ Estado Esperado:**
- **ArgoCD Applications:** `Synced & Healthy`
- **Todos los Pods:** `Running` 
- **Servicios:** Accesibles desde Windows
- **Git Repositories:** Configurados y funcionando
- **Acceso Automático:** Comandos `dashboard`, `argocd`, `gitea` funcionando

### **🌐 Acceso desde Windows:**
- Abres un navegador en Windows
- Usas las IPs proporcionadas por `check-windows-access.sh`
- Dashboard accesible con "SKIP" login
- ArgoCD y Gitea con credenciales automáticas

### **🔄 GitOps Funcional:**
- Cambios en Git → Sincronización automática en Kubernetes
- UI de ArgoCD para monitorear aplicaciones
- Repositorios Git locales totalmente funcionales

---

## 💡 Consejos de Uso

### **📈 Para Desarrollo:**
1. Clona repos en Gitea: `http://IP_WSL:30083`
2. Modifica manifests de Kubernetes
3. Push a Git → ArgoCD sincroniza automáticamente
4. Monitorea en ArgoCD UI: `http://IP_WSL:30080`

### **🔄 Para Probar GitOps:**
1. Edita archivos en `/tmp/gitops-tools-repo/` 
2. `git add . && git commit -m "test" && git push`
3. Ve a ArgoCD UI y observa la sincronización automática

### **🛠️ Para Debugging:**
```bash
kubectl logs -f deployment/argocd-application-controller -n argocd  # Logs ArgoCD
kubectl get events --all-namespaces --sort-by='.lastTimestamp'     # Eventos del cluster
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