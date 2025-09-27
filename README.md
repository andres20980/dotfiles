# Mi Configuración de WSL (Dotfiles)

Este repositorio contiene la configuración de mi entorno de desarrollo en WSL (Ubuntu). Incluye la configuración de `zsh`, `Oh My Zsh`, `nvm`, `docker`, `kubectl`, `kind`, ArgoCD y otros. También incluye un script (`install.sh`) para automatizar la instalación de todas las herramientas.

## 🚀 Cómo restaurar la configuración en una máquina nueva

1.  **Clonar este repositorio:**
    ```bash
    # Clona el repositorio en tu directorio home
    git clone https://github.com/andres20980/dotfiles.git ~/dotfiles
    ```

2.  **Ejecutar el script de instalación:**
    Este script instalará todas las aplicaciones, herramientas y configuraciones necesarias.
    ```bash
    # Navega a la carpeta
    cd ~/dotfiles

    # Dale permisos de ejecución y lánzalo
    chmod +x install.sh
    ./install.sh
    ```
    *Nota: El script usará `sudo`, por lo que te pedirá tu contraseña. Instalará **Docker Engine**, **Git Credential Manager**, desplegará **ArgoCD**, **Gitea** y configurará aplicaciones GitOps automáticamente.*

4.  **Crear el enlace simbólico:**
    El script no sobreescribe tu `.zshrc` por seguridad. Después de que el script termine, enlaza el `.zshrc` de este repositorio a tu `home`.
    ```bash
    # Borra el .zshrc por defecto si existe
    rm ~/.zshrc

    # Crea el enlace simbólico
    ln -s ~/dotfiles/.zshrc ~/.zshrc
    ```

5.  **Configurar tu identidad de Git:**
    El script no configura tus datos personales. Hazlo con los siguientes comandos:
    ```bash
    git config --global user.name "tu-nombre"
    git config --global user.email "tu-email@example.com"
    ```

6.  **Reiniciar la Terminal:**
    Cierra y vuelve a abrir la terminal para que todos los cambios (`zsh`, `nvm`, `docker`, etc.) se carguen correctamente.

7.  **Autenticar Git con GitHub:**
    La primera vez que hagas `git push` a un repositorio privado, el Git Credential Manager (instalado por el script) te pedirá que te autentiques en GitHub. Solo tendrás que hacerlo una vez.

¡Y listo! Tu entorno estará replicado.

## 🐳 Entorno Kubernetes (kind + Docker)
## 🌐 Exposición de servicios (NodePort)

El script configura automáticamente los servicios de **ArgoCD** y **Dashboard de Kubernetes** como **NodePort**, lo que significa que están disponibles directamente en `localhost` sin necesidad de mantener terminales abiertas con port-forwarding.

**URLs de acceso desde Windows:**
- **ArgoCD HTTP:** `http://localhost:30080` (o `http://argocd.mini-cluster`)
- **Gitea:** `http://localhost:30083` (o `http://gitea.mini-cluster`)
- **NGINX Ingress:** `http://localhost:30090`
- **Dashboard Kubernetes:** `https://dashboard.mini-cluster` (via ingress)
- **Hello World App:** `http://hello-world.mini-cluster` (via ingress)

Esta configuración es ideal para desarrollo local con kind, ya que los NodePorts se mapean automáticamente a localhost.
*Nota: Gracias a la configuración especial de kind, ahora puedes acceder directamente desde tu navegador de Windows usando `localhost` sin necesidad de configuración adicional en el hosts de Windows.*/
*Nota: El script configura automáticamente entradas en `/etc/hosts` para dominios personalizados en WSL. Para Windows, usa directamente `localhost` gracias a la configuración especial de kind.*


El script de instalación prepara todo lo necesario para levantar un clúster de Kubernetes local usando Docker como motor.

Para crear tu primer clúster, simplemente usa:

```bash
kind create cluster
```

`kind` usará Docker automáticamente, que es su motor por defecto y el más probado.

## ⚙️ Post-instalación de Docker (Uso cómodo)

Después de que el script principal termine, se recomienda ejecutar estos dos pasos para poder usar Docker sin `sudo` y para que se inicie automáticamente.

1.  **Añadir tu usuario al grupo `docker`:**
    ```bash
    # Esto te permite ejecutar comandos de docker sin sudo
    sudo usermod -aG docker $USER
    ```
    **¡Importante!** Después de este comando, debes cerrar y volver a abrir la terminal.

2.  **Configurar el arranque automático del servicio de Docker:**
    Esto permite que el servicio de Docker se inicie sin pedir contraseña, para poder automatizarlo en el `.zshrc`.
    ```bash
    # La variable $USER se reemplazará por tu nombre de usuario actual
    echo "$USER ALL=(ALL) NOPASSWD: /usr/sbin/service docker start" | sudo tee /etc/sudoers.d/docker-service
    ```
    *Nota: El script que hemos añadido a tu `.zshrc` usará este permiso para iniciar Docker automáticamente en nuevas terminales.*

## 🖥️ Acceder a los servicios (sin port-forwarding necesario)

El Dashboard de Kubernetes y las aplicaciones custom se instalan y gestionan a través de ArgoCD usando el script `create-argocd-apps.sh`.

### Acceder al Dashboard de Kubernetes:
1.  **Obtén el token de login** para acceder al Dashboard:
    ```bash
    kubectl -n kubernetes-dashboard create token kubernetes-dashboard
    ```
    Copia el token que se mostrará.

2.  **Abre el navegador** en la siguiente URL, elige "Token" y pega el token para entrar:
    `https://dashboard.mini-cluster` (accesible via NGINX Ingress)

### Acceder a la aplicación Hello World:
La aplicación Hello World es un ejemplo simple que demuestra GitOps. Está desplegada y gestionada por ArgoCD.

**Estado actual:** ✅ Desplegada y funcionando (accesible via NGINX Ingress en `http://hello-world.mini-cluster`)

## 🚀 Acceder a ArgoCD

El script de instalación despliega ArgoCD (Argo Continuous Delivery) mínimamente y lo configura para funcionar **sin autenticación** en entornos locales y privados.

### Acceder a ArgoCD:

1. **Abre el navegador** directamente en la siguiente URL (sin necesidad de port-forwarding):
   `http://localhost:30080` (o `http://argocd.mini-cluster`)

*Nota: ArgoCD está configurado en modo inseguro (`server.insecure=true`) y sin autenticación (`server.disable.auth=true`) para facilitar el desarrollo local. No uses esta configuración en entornos de producción.*

## 🚀 Acceder a Gitea

El script de instalación despliega Gitea como repositorio Git local usando SQLite y sin autenticación.

### Acceder a Gitea:

1. **Abre el navegador** directamente en la siguiente URL:
   `http://localhost:30083` (o `http://gitea.mini-cluster`)

*Nota: Gitea está configurado sin autenticación para facilitar el desarrollo local. Los repositorios se crean automáticamente durante la instalación.*

### Crear tu primer Application con ArgoCD:
#### Gestionar herramientas con ArgoCD (GitOps)

El script `install.sh` crea automáticamente dos tipos de aplicaciones organizadas en proyectos de ArgoCD:

**🔧 GitOps Tools** (`argocd-apps/gitops-tools/`):
- Herramientas de infraestructura gestionadas por ArgoCD
- Versión más ligera posible, sin autenticación cuando sea viable
- Actualmente incluye: Kubernetes Dashboard
- Repositorio: `http://gitea.mini-cluster/argocd/gitops-tools`

**🛠️ Custom Apps** (`argocd-apps/custom-apps/`):
- Tus aplicaciones personalizadas
- Ejemplos para aprender GitOps
- Actualmente incluye: Hello World (aplicación de ejemplo)
- Repositorio: `http://gitea.mini-cluster/argocd/custom-apps`

Todas las aplicaciones se consideran correctas cuando muestran estado **Synced** y **Healthy** en ArgoCD.


Una vez que tengas repositorios Git con tus manifiestos de Kubernetes, puedes crear aplicaciones en ArgoCD desde la interfaz web o usando la CLI:

```bash
# Ejemplo de creación de una aplicación
kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/tu-usuario/tu-repo
    targetRevision: HEAD
    path: k8s-manifests
  destination:
    server: https://kubernetes.default.svc
    namespace: default
EOF
```
