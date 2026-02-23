# GitOps Learning Platform

[![Kind](https://img.shields.io/badge/Kind-v0.30.0-blue)](https://kind.sigs.k8s.io/)
[![ArgoCD](https://img.shields.io/badge/ArgoCD-v3.1.9-blue)](https://argo-cd.readthedocs.io/)
[![Gitea](https://img.shields.io/badge/Gitea-v1.25.0-blue)](https://docs.gitea.io/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

> **Un laboratorio GitOps completo que se instala en un solo comando.**
> Aprende GitOps de forma práctica, en tu portátil, sin cloud, sin costes.

---

## Antes de empezar: ¿Qué es GitOps?

### La versión corta

Imagina que tienes un documento de Google Docs compartido. Cualquiera que haga un cambio en el documento, todos lo ven al instante. Si alguien borra algo por error, puedes volver a una versión anterior.

**GitOps es exactamente eso, pero para servidores y aplicaciones.**

En vez de un Google Docs, usas un **repositorio Git** (como GitHub). En vez de texto, escribes **archivos YAML** que describen qué aplicaciones quieres ejecutar y cómo. Un "robot" (**ArgoCD**) vigila ese repositorio constantemente y se asegura de que lo que está en Git sea exactamente lo que hay desplegado en el servidor.

### ¿Por qué es útil?

| Sin GitOps | Con GitOps |
|---|---|
| Despliegas manualmente con comandos | Haces un commit en Git y se despliega solo |
| "¿Quién tocó el servidor?" — nadie sabe | Todo cambio queda registrado en Git (quién, cuándo, qué) |
| Si algo se rompe, pánico | Reviertes al commit anterior y listo |
| Cada servidor puede estar diferente | Git es la "fuente de verdad" — todo está sincronizado |

### El flujo en este laboratorio

```
TÚ                              GITEA (Git)                   ARGOCD (Robot)               KUBERNETES (Servidor)
 |                                |                              |                              |
 |  1. Editas un archivo YAML     |                              |                              |
 |  ----------------------------► |                              |                              |
 |                                |  2. ArgoCD detecta el cambio |                              |
 |                                |  --------------------------► |                              |
 |                                |                              |  3. Aplica los cambios       |
 |                                |                              |  --------------------------► |
 |                                |                              |                              |
 |  4. Ves el resultado en tu navegador  ◄───────────────────────────────────────────────────── |
```

---

## Glosario: Palabras que verás mucho

No necesitas memorizar esto ahora — vuelve aquí cuando encuentres un término que no entiendas.

| Término | ¿Qué es? | Analogía |
|---|---|---|
| **Kubernetes (K8s)** | Sistema que gestiona aplicaciones en contenedores | El "sistema operativo" de un datacenter |
| **Cluster** | Un grupo de máquinas que ejecutan Kubernetes | Como un equipo de ordenadores trabajando juntos |
| **Pod** | La unidad más pequeña en K8s — un contenedor ejecutándose | Como un proceso en tu ordenador |
| **Deployment** | Dice a K8s "quiero X copias de esta app corriendo" | Como una receta: "haz 2 pizzas de este tipo" |
| **Service** | Da una dirección estable a una app (porque los pods van y vienen) | Como el numero de teléfono de una empresa (no de un empleado) |
| **Namespace** | Carpeta virtual para organizar apps en K8s | Como departamentos en una empresa |
| **Kind** | Crea un cluster K8s dentro de Docker (para practicar en local) | Como un simulador de vuelo (parece real, pero es tu portátil) |
| **ArgoCD** | El "robot" GitOps que vigila Git y sincroniza con K8s | El Google Docs que auto-actualiza |
| **Gitea** | Servidor Git local (como un GitHub privado en tu máquina) | Tu propio GitHub personal |
| **Helm** | Gestor de paquetes para K8s (instala apps complejas de un tirón) | El "apt-get" o "brew" de Kubernetes |
| **Kustomize** | Herramienta para personalizar YAML sin copiar-pegar | Plantillas con variaciones |
| **Manifest** | Un archivo YAML que describe algo en K8s | Las instrucciones de montaje de un mueble IKEA |
| **Synced** | ArgoCD confirmó que Git y K8s están iguales | "Todo al día" |
| **Healthy** | La app está funcionando correctamente | Luz verde |
| **NodePort** | Forma de acceder a una app K8s desde tu navegador via localhost:PUERTO | La puerta de entrada a la app |
| **Registry** | Almacén de imágenes Docker (como DockerHub pero local) | La estantería donde guardas los .exe |
| **CI/CD** | Integración Continua / Despliegue Continuo — automatizar build y deploy | La cadena de montaje de una fábrica |

---

## Qué necesitas antes de instalar

### 1. Un Linux (o WSL2 en Windows)

Si usas **Windows**, necesitas WSL2. Abre PowerShell como administrador:
```powershell
wsl --install -d Ubuntu
```
Reinicia, abre Ubuntu, y ya estás.

Si usas **Mac** o **Linux nativo**, ya estás listo.

### 2. Docker instalado y funcionando

Docker es como una "máquina virtual ligera" que permite ejecutar aplicaciones aisladas.

**Instalar Docker** (en Ubuntu/WSL2):
```bash
# Instalar Docker
curl -fsSL https://get.docker.com | sh

# Permitir usar Docker sin sudo
sudo usermod -aG docker $USER

# IMPORTANTE: Cierra y abre la terminal para que aplique
# Luego verifica:
docker ps
# Si no da error, Docker funciona
```

### 3. Recursos mínimos

- **4 GB de RAM** disponible (Docker + Kind + apps)
- **10 GB de disco** libre (imágenes Docker)
- **Conexión a internet** (solo para la primera instalación)

### 4. Git (para clonar el repo)

```bash
# Normalmente ya viene instalado. Comprueba:
git --version

# Si no está:
sudo apt install git
```

> **El script (install.sh) instala automáticamente todo lo demás**: kubectl, kind, helm, jq... No tienes que instalar nada más.

---

## Instalación (5-10 minutos)

### Paso 1: Clonar y ejecutar

```bash
git clone https://github.com/andres20980/gitops-poc.git
cd gitops-poc
./install.sh
```

Eso es todo. Siéntate y mira.

### Paso 2: Qué hace el script (no necesitas hacer nada)

El script ejecuta estas fases automáticamente:

```
FASE 1/7 — Instala herramientas (kubectl, kind, helm...)
FASE 2/7 — Crea un cluster Kubernetes en Docker (Kind)
FASE 3/7 — Instala ArgoCD (el "robot" GitOps)
FASE 4/7 — Instala Gitea (servidor Git local) + inicializa repos
FASE 5/7 — Bootstrap GitOps (activa el App of Apps pattern)
FASE 6/7 — Construye y despliega la app demo (app-reloj)
FASE 7/7 — Verifica que todo funciona (14/14 Synced & Healthy)
```

### Paso 3: Resultado esperado

Al terminar, verás algo así:

```
╔════════════════════════════════════════════════════════════╗
║          INSTALACIÓN COMPLETADA EXITOSAMENTE              ║
╚════════════════════════════════════════════════════════════╝

CREDENCIALES DE ACCESO:

Argo CD:
  URL:      http://localhost:30080
  Usuario:  admin (o acceso anónimo habilitado)

Gitea (Source of Truth):
  URL:      http://localhost:30083
  Usuario:  gitops
  Password: gitops

Grafana:
  URL:      http://localhost:30082
  Usuario:  admin
  Password: gitops

INSTALACIÓN PERFECTA - Score 6/6
```

> **Si ves "Score 6/6"** o "14/14 Synced & Healthy": todo funciona. Puedes empezar.

---

## Guía de aprendizaje (haz esto en orden)

### Ejercicio 1: Explora ArgoCD — ver cómo GitOps gestiona todo

**Objetivo:** Entender qué es ArgoCD y cómo visualiza el estado de tus aplicaciones.

1. Abre tu navegador y ve a: **http://localhost:30080**
2. Verás un panel con **14 rectángulos**, cada uno es una aplicación:

```
┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐
│  argocd-self │  │    gitea    │  │   grafana   │  │  app-reloj  │
│  ✓ Healthy   │  │  ✓ Healthy  │  │  ✓ Healthy  │  │  ✓ Healthy  │
│  ✓ Synced    │  │  ✓ Synced   │  │  ✓ Synced   │  │  ✓ Synced   │
└─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘
        ... y 10 más
```

3. **Haz click en cualquier aplicación** (por ejemplo, `app-reloj`). Verás:
   - Un **árbol visual** con todos los recursos de Kubernetes que la componen
   - Flechas que muestran cómo se relacionan: Deployment → ReplicaSet → Pod
   - Colores: verde = todo bien, amarillo = progresando, rojo = error

4. **¿Qué significa "Synced"?** Que lo que hay en Git es exactamente lo que hay desplegado.
5. **¿Qué significa "Healthy"?** Que la aplicación está funcionando sin errores.

> **Concepto clave**: ArgoCD es el centro de control. Desde aquí ves TODO lo que está desplegado, su estado, y si algo falla.

---

### Ejercicio 2: Visita la app-reloj — una app real desplegada con GitOps

**Objetivo:** Comprobar que una aplicación real funciona y entender sus endpoints.

1. Abre: **http://localhost:30150**
   - Verás un **reloj en tiempo real** con tema oscuro y la versión desplegada

2. Abre: **http://localhost:30150/health**
   - Verás algo como: `{"status":"ok","version":"1.0.0","uptime":234.5}`
   - Esto es un **health check**: una URL que las herramientas usan para saber si la app vive

3. Abre: **http://localhost:30150/api/time**
   - Verás la hora en formato JSON — esto es una **API REST**

> **Concepto clave**: Esta app se desplegó AUTOMÁTICAMENTE porque sus archivos YAML están en Git. Nadie ejecutó `docker run` ni `kubectl apply` manualmente.

---

### Ejercicio 3: Explora Gitea — la "fuente de verdad"

**Objetivo:** Entender que Git es el centro de todo en GitOps.

1. Abre: **http://localhost:30083**
2. Haz login con **gitops** / **gitops**
3. Haz click en el repo **gitops-manifests** — este es el repo que ArgoCD vigila
4. Navega a `custom-apps/app-reloj/` y abre `deployment.yaml`
5. Verás algo como:

```yaml
spec:
  replicas: 1          # <-- Esto dice "quiero 1 copia de la app"
  ...
  containers:
    - name: app-reloj
      image: app-reloj:latest    # <-- Esta es la imagen Docker que ejecuta
```

> **Concepto clave**: Este archivo YAML en Gitea es la "fuente de verdad". ArgoCD lee esto y se asegura de que exactamente 1 réplica de app-reloj esté corriendo en Kubernetes.

---

### Ejercicio 4: Haz tu primer cambio GitOps (escalar la app)

**Objetivo:** Cambiar algo en Git y ver cómo ArgoCD lo aplica automáticamente.

Este es el "momento mágico" — el ejercicio que demuestra GitOps de verdad.

```bash
# 1. Clona el repo de manifests desde Gitea a tu máquina
cd /tmp
git clone http://gitops:gitops@localhost:30083/gitops/gitops-manifests.git
cd gitops-manifests

# 2. Mira cuántas réplicas tiene ahora (debería ser 1)
grep "replicas" custom-apps/app-reloj/deployment.yaml

# 3. Cámbialo a 3 réplicas
sed -i 's/replicas: 1/replicas: 3/' custom-apps/app-reloj/deployment.yaml

# 4. Confirma el cambio
grep "replicas" custom-apps/app-reloj/deployment.yaml
# Salida: replicas: 3

# 5. Commit y push a Gitea
git add .
git commit -m "scale: app-reloj a 3 replicas"
git push

# 6. Observa la magia:
# Abre http://localhost:30080, click en app-reloj
# Verás cómo ArgoCD detecta el cambio y crea 2 pods nuevos (para llegar a 3)

# 7. Verifica desde la terminal (espera ~30 segundos)
kubectl get pods -n app-reloj
# Deberías ver 3 pods Running
```

**¿Qué acaba de pasar?**
1. Cambiaste un número en un archivo de texto (YAML)
2. Lo subiste a Git (push)
3. ArgoCD detectó el cambio (en menos de 3 minutos)
4. Kubernetes creó 2 pods nuevos automáticamente
5. Ahora hay 3 copias de tu app corriendo

**Nadie ejecutó ningún comando en el servidor.** Solo un `git push`. Eso es GitOps.

---

### Ejercicio 5: Rompe algo y observa el self-healing

**Objetivo:** Ver cómo Kubernetes + ArgoCD protegen tu app.

```bash
# 1. Borra un pod "a mano" (simula un fallo)
kubectl delete pod -n app-reloj -l app=app-reloj --wait=false

# 2. Mira cómo Kubernetes lo recrea INSTANTÁNEAMENTE
kubectl get pods -n app-reloj -w
# Verás pods "Terminating" y otros "Running" que los reemplazan

# (Pulsa Ctrl+C para salir del watch)
```

**¿Qué aprendiste?** Kubernetes mantiene SIEMPRE el estado que definiste en el YAML. Si un pod muere, crea otro. Eso es **self-healing** (auto-reparación).

---

### Ejercicio 6: Explora las demás herramientas

Ahora que entiendes el concepto, curiosea:

| URL | Herramienta | Qué verás |
|---|---|---|
| http://localhost:30080 | **ArgoCD** | Panel de control GitOps — todas las apps y su estado |
| http://localhost:30083 | **Gitea** | Servidor Git — los repos con los YAML (login: gitops/gitops) |
| http://localhost:30082 | **Grafana** | Dashboards con gráficas de métricas (login: admin/gitops) |
| http://localhost:30081 | **Prometheus** | Métricas crudas del cluster (queries PromQL) |
| http://localhost:30090 | **Dashboard** | Vista nativa de Kubernetes (pods, deployments, etc.) |
| http://localhost:30150 | **App Reloj** | Tu app demo — un reloj en tiempo real |

> No necesitas entender todo hoy. El objetivo es que te suene y que sepas dónde encontrar cada cosa.

---

## App Reloj — La app demo incluida

### ¿Qué es?

Una web app Node.js muy sencilla que muestra un reloj. Existe para demostrar el ciclo GitOps completo con una app real (no solo infraestructura).

| Endpoint | Qué hace |
|---|---|
| `http://localhost:30150` | Página web con reloj visual (tema oscuro, se actualiza cada segundo) |
| `http://localhost:30150/health` | Health check JSON: `{"status":"ok","version":"1.0.0","uptime":...}` |
| `http://localhost:30150/api/time` | API REST con hora, fecha, timestamp ISO |

### Cómo llega del código al cluster (el ciclo GitOps)

```
 gitops-source-code/app-reloj/           (1) Código fuente de la app
         |
         v
 docker build -> localhost:30100         (2) Se construye imagen Docker y se guarda en registry
         |
         v
 gitops-manifests/custom-apps/           (3) Manifests K8s dicen "despliega esta imagen"
    app-reloj/
         |
         v
 Gitea (localhost:30083)                 (4) Los manifests están en Git (fuente de verdad)
         |
         v
 ArgoCD (localhost:30080)                (5) Detecta el repo, sincroniza con el cluster
         |
         v
 Kubernetes                              (6) app-reloj corriendo en pod, accesible en :30150
```

### Quiero crear mi propia app

Usa app-reloj como plantilla. El proceso resumido:

1. **Crea tu app** con un `server.js` y `Dockerfile` en `gitops-source-code/mi-app/`
2. **Build y push** la imagen Docker al registry local (`localhost:30100`)
3. **Crea los manifests K8s** en `gitops-manifests/custom-apps/mi-app/` (copia y adapta los de app-reloj)
4. **Push a Gitea** — ArgoCD detecta el nuevo directorio y despliega automáticamente

Ejemplo completo paso a paso:

```bash
# --- PASO 1: Crear source code ---
mkdir -p gitops-source-code/mi-app

# Un servidor web mínimo
cat > gitops-source-code/mi-app/server.js << 'EOF'
const http = require("http");
http.createServer((req, res) => {
  if (req.url === "/health") {
    res.writeHead(200, {"Content-Type": "application/json"});
    return res.end(JSON.stringify({status: "ok"}));
  }
  res.writeHead(200, {"Content-Type": "text/html"});
  res.end("<h1>Hola! Soy mi-app desplegada con GitOps</h1>");
}).listen(8080, () => console.log("Running on 8080"));
EOF

cat > gitops-source-code/mi-app/package.json << 'EOF'
{"name":"mi-app","version":"1.0.0","main":"server.js"}
EOF

cat > gitops-source-code/mi-app/Dockerfile << 'EOF'
FROM node:20-alpine
WORKDIR /app
COPY package.json server.js ./
USER node
EXPOSE 8080
CMD ["node", "server.js"]
EOF

# --- PASO 2: Build y push al registry ---
docker build -t localhost:30100/mi-app:v1.0.0 gitops-source-code/mi-app/
docker push localhost:30100/mi-app:v1.0.0

# --- PASO 3: Crear manifests K8s ---
mkdir -p gitops-manifests/custom-apps/mi-app
# Copia los de app-reloj y adapta (cambia "app-reloj" por "mi-app", nodePort a 30151)
cp gitops-manifests/custom-apps/app-reloj/deployment.yaml gitops-manifests/custom-apps/mi-app/
cp gitops-manifests/custom-apps/app-reloj/service.yaml gitops-manifests/custom-apps/mi-app/
cp gitops-manifests/custom-apps/app-reloj/kustomization.yaml gitops-manifests/custom-apps/mi-app/
# Editar: reemplaza app-reloj por mi-app y 30150 por 30151

# --- PASO 4: Push a Gitea ---
cd /tmp && git clone http://gitops:gitops@localhost:30083/gitops/gitops-manifests.git gitea-update
cp -r gitops-manifests/custom-apps/mi-app gitea-update/custom-apps/
cd gitea-update && git add . && git commit -m "feat: add mi-app" && git push

# ArgoCD detecta el nuevo directorio y despliega automaticamente
# Espera ~2 minutos y abre: http://localhost:30151
```

---

## Arquitectura — Cómo encajan todas las piezas

```
+-----------------------------------------------------------------------------+
|                           Tu portátil (Docker)                              |
|                                                                             |
|  +-----------------------------------------------------------------------+  |
|  |                    Cluster Kubernetes (Kind)                          |  |
|  |                                                                       |  |
|  |  +-------------+  +-------------+  +-------------------------------+ |  |
|  |  |   ArgoCD     |  |   Gitea     |  |     Tus Apps (custom-apps)   | |  |
|  |  |  :30080      |  |  :30083     |  |  +----------+ +----------+  | |  |
|  |  |  (GitOps     |  |  (Git       |  |  |app-reloj | | mi-app   |  | |  |
|  |  |   engine)    |<-|  server)    |  |  | :30150   | | :30151   |  | |  |
|  |  +-------------+  +-------------+  |  +----------+ +----------+  | |  |
|  |                                     +-------------------------------+ |  |
|  |  +----------------------------------------------------------------+   |  |
|  |  |              Herramientas de soporte                            |   |  |
|  |  |  Grafana :30082  | Prometheus :30081 | Dashboard :30090        |   |  |
|  |  |  Argo Workflows  | Argo Rollouts     | Argo Events            |   |  |
|  |  |  Kargo :30085    | Registry :30100   | Redis | Sealed Secrets  |   |  |
|  |  +----------------------------------------------------------------+   |  |
|  +-----------------------------------------------------------------------+  |
|                                                                             |
|  Acceso desde tu navegador: http://localhost:PUERTO                         |
+-----------------------------------------------------------------------------+
```

### ¿Por qué tantas herramientas?

No tienes que aprenderlas todas de golpe. Empezarás con estas 3:

| Prioridad | Herramienta | Para qué |
|---|---|---|
| Imprescindible | **ArgoCD** | El corazón de GitOps. Vigila Git y despliega en Kubernetes. |
| Imprescindible | **Gitea** | Tu servidor Git. Donde viven los YAML que definen todo. |
| Recomendada | **Grafana** | Para ver gráficas bonitas de cómo van tus apps. |

Las demás (Argo Workflows, Rollouts, Kargo, Prometheus, etc.) son herramientas avanzadas que explorarás cuando domines las básicas.

---

## Estructura del proyecto

```
gitops-poc/
├── install.sh                          # <-- Lo único que ejecutas. Hace todo.
├── README.md                           # <-- Estás aquí
│
├── gitops-manifests/                   # Los YAML que ArgoCD vigila (fuente de verdad)
│   ├── custom-apps/                    # TUS aplicaciones
│   │   └── app-reloj/                  #   App demo incluida
│   │       ├── deployment.yaml         #       "Quiero 1 réplica de app-reloj"
│   │       ├── service.yaml            #       "Exponla en puerto 30150"
│   │       └── kustomization.yaml      #       "Usa esta imagen del registry"
│   ├── gitops-tools/                   # Herramientas del lab (ArgoCD, Grafana, etc.)
│   │   ├── argo-events/
│   │   ├── argo-workflows/
│   │   ├── argo-rollouts/
│   │   ├── dashboard/
│   │   ├── gitea/
│   │   ├── grafana/
│   │   ├── kargo/ + kargo-crds/
│   │   ├── prometheus/
│   │   ├── redis/
│   │   ├── registry/
│   │   └── sealed-secrets/
│   ├── infra-configs/                  # Configuración de ArgoCD (proyectos, permisos)
│   └── instalacion/                    # Root App + config Kind
│
└── gitops-source-code/                 # Código fuente de tus apps
    └── app-reloj/                      # Source de la app demo
        ├── server.js                   # Servidor Node.js con reloj
        ├── package.json
        └── Dockerfile                  # Receta para construir la imagen Docker
```

**Regla de oro**: Los YAML en `gitops-manifests/` son la fuente de verdad. Si quieres cambiar algo, cambia el YAML y haz push a Git. Nunca ejecutes `kubectl apply` manualmente.

---

## Limpieza

### Apagar todo (eliminar el cluster)

```bash
kind delete cluster --name gitops-local
```

Esto borra todo el cluster y todas las apps. Docker sigue instalado, tus archivos siguen intactos.

### Volver a empezar desde cero

```bash
# 1. Borrar cluster
kind delete cluster --name gitops-local

# 2. (Opcional) Limpiar imágenes Docker para liberar disco
docker system prune -a

# 3. Reinstalar
cd gitops-poc
./install.sh
```

---

## Algo no funciona — Troubleshooting

### El script falla a medio instalar

```bash
# Borra el cluster roto y prueba de nuevo
kind delete cluster --name gitops-local
./install.sh
```

### ArgoCD muestra apps en amarillo ("Progressing") o rojo ("Degraded")

```bash
# Espera 2-3 minutos, a veces tarda.
# Si persiste, fuerza un re-sync:
kubectl get apps -n argocd    # Ver qué app tiene problemas

# Forzar sincronización de una app específica
kubectl patch app NOMBRE-APP -n argocd --type merge \
  -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
```

### No puedo acceder a http://localhost:30080

```bash
# Verifica que el cluster está corriendo
docker ps | grep kind

# Verifica que los pods de ArgoCD están vivos
kubectl get pods -n argocd

# Si Docker no está corriendo:
sudo systemctl start docker
```

### El pod de mi app está en "CrashLoopBackOff"

```bash
# Ver los logs para saber por qué crashea
kubectl logs -n NOMBRE-NAMESPACE -l app=NOMBRE-APP

# Ver los últimos eventos
kubectl get events -n NOMBRE-NAMESPACE --sort-by='.lastTimestamp' | tail -10
```

---

## Ruta de aprendizaje recomendada

Después de completar los 6 ejercicios de arriba:

### Nivel 1 — Básico (esta semana)
- [ ] Completa los 6 ejercicios del README
- [ ] Modifica app-reloj: cambia el color de fondo en server.js, rebuild, push, observa
- [ ] Crea tu propia custom app siguiendo la guía

### Nivel 2 — Intermedio (próximas semanas)
- [ ] Lee: [ArgoCD Core Concepts](https://argo-cd.readthedocs.io/en/stable/core_concepts/)
- [ ] Explora los manifests de gitops-tools/ — intenta entender los YAML
- [ ] Mira las métricas en Grafana y Prometheus
- [ ] Lee: [Kubernetes Concepts](https://kubernetes.io/docs/concepts/)

### Nivel 3 — Avanzado (cuando estés cómodo)
- [ ] Explora Argo Workflows: crea un pipeline CI/CD
- [ ] Experimenta con Argo Rollouts: canary deployments
- [ ] Configura Kargo para promoción multi-stage
- [ ] Lee: [Argo Workflows Walk-through](https://argo-workflows.readthedocs.io/en/latest/walk-through/)

---

## Recursos para seguir aprendiendo

| Recurso | Nivel | Enlace |
|---|---|---|
| Kubernetes Concepts | Básico | [kubernetes.io/docs/concepts](https://kubernetes.io/docs/concepts/) |
| Kind Quick Start | Básico | [kind.sigs.k8s.io](https://kind.sigs.k8s.io/docs/user/quick-start/) |
| ArgoCD Getting Started | Básico | [argo-cd.readthedocs.io](https://argo-cd.readthedocs.io/en/stable/getting_started/) |
| ArgoCD Core Concepts | Intermedio | [argo-cd.readthedocs.io](https://argo-cd.readthedocs.io/en/stable/core_concepts/) |
| Argo Workflows Guide | Avanzado | [argo-workflows.readthedocs.io](https://argo-workflows.readthedocs.io/en/latest/walk-through/) |
| Argo Rollouts | Avanzado | [argoproj.github.io/argo-rollouts](https://argoproj.github.io/argo-rollouts/) |
| Gitea Docs | Referencia | [docs.gitea.io](https://docs.gitea.io/) |

---

## Contribuir

¿Encontraste un bug? ¿Tienes una mejora? PRs son bienvenidos.

1. Fork el repositorio
2. Crea un branch (`git checkout -b feature/mi-mejora`)
3. Commit (`git commit -m 'feat: mi mejora'`)
4. Push (`git push origin feature/mi-mejora`)
5. Abre un Pull Request

## Licencia

MIT — Ver [LICENSE](LICENSE) para detalles.

---

**¿Dudas?** Abre un [issue](https://github.com/andres20980/gitops-poc/issues)

**¿Te sirve?** Dale una estrella al repo.
