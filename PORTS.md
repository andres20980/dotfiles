# 🚪 Estrategia de Puertos del Cluster GitOps

Este cluster Kind está configurado con un amplio rango de puertos expuestos para permitir la adición dinámica de nuevas herramientas GitOps y aplicaciones custom sin necesidad de reconfigurar el cluster.

## 📋 Rangos de Puertos

### 🔧 GitOps Tools Principales (30080-30099)
Puertos reservados para herramientas GitOps core del ecosistema Argo y Kubernetes.

| Puerto | Herramienta | URL | Descripción |
|--------|-------------|-----|-------------|
| 30080 | ArgoCD | http://localhost:30080 | Motor GitOps principal |
| 30083 | Gitea | http://localhost:30083 | Source of Truth (Git) |
| 30086 | Grafana | http://localhost:30086 | Observabilidad y dashboards |
| 30090 | Prometheus | http://localhost:30090 | Métricas y monitoreo |
| 30091 | Kargo | http://localhost:30091 | Progressive Delivery |
| 30092 | Redis | http://localhost:30092 | Cache y pub/sub |
| 30093 | Argo Workflows | http://localhost:30093 | CI/CD workflows |
| 30094 | Argo Rollouts | http://localhost:30094 | Despliegues avanzados |
| 30096 | Registry UI | http://localhost:30096 | Interfaz web del registry |
| 30443 | Dashboard | https://localhost:30443 | Kubernetes Dashboard |

**Puertos disponibles**: 30081-30082, 30084-30085, 30087-30089, 30095, 30097-30099

### 🐳 Registry y CI/CD (30100-30149)
Puertos dedicados a Docker Registry, herramientas de build y CI/CD adicionales.

| Puerto | Herramienta | URL | Descripción |
|--------|-------------|-----|-------------|
| 30100 | Docker Registry | http://localhost:30100 | Registro de imágenes Docker |

**Puertos disponibles**: 30101-30149 (49 puertos libres para futuras herramientas de CI/CD)

### 🚀 Custom Apps (30150-30199)
Puertos para aplicaciones custom desarrolladas en este entorno de aprendizaje.

| Puerto | App | URL | Descripción |
|--------|-----|-----|-------------|
| 30150 | app-reloj | http://localhost:30150 | App de ejemplo: reloj con CI/CD |

**Puertos disponibles**: 30151-30199 (49 puertos libres para nuevas custom apps)

### 🔮 Futuras GitOps Tools (30200-30249)
Reservado para herramientas GitOps adicionales que se añadan posteriormente.

**Puertos disponibles**: 30200-30249 (50 puertos libres)

Ejemplos de herramientas que podrían añadirse:
- Tekton
- Flux
- Jenkins X
- Harbor
- Vault
- External Secrets Operator
- Crossplane
- KubeVirt
- Istio/Service Mesh
- etc.

## 🎯 Proceso para Añadir Nueva Herramienta GitOps

1. **Seleccionar puerto** del rango apropiado (30200-30249 para GitOps tools)

2. **Crear manifests** en `/gitops-manifests/gitops-tools/<nombre-herramienta>/`
   ```
   gitops-tools/
   └── nueva-herramienta/
       ├── deployment.yaml
       ├── service.yaml (con nodePort: 30XXX)
       ├── configmap.yaml (opcional)
       └── rbac.yaml (opcional)
   ```

3. **Commitear y pushear** a Gitea:
   ```bash
   cd /home/asanchez/Code/dotfiles/gitops-manifests
   git add gitops-tools/nueva-herramienta/
   git commit -m "feat: add nueva-herramienta"
   git push gitea main
   ```

4. **ArgoCD detectará y desplegará automáticamente** la nueva herramienta
   - El ApplicationSet `gitops-tools` genera una Application por cada subdirectorio
   - No requiere modificar ningún otro archivo

## 🚀 Proceso para Añadir Nueva Custom App

1. **Seleccionar puerto** del rango 30150-30199

2. **Crear código fuente** en `/gitops-source-code/<nombre-app>/`
   ```
   gitops-source-code/
   └── nueva-app/
       ├── Dockerfile
       ├── package.json (o similar)
       └── src/ (código de la app)
   ```

3. **Crear manifests** en `/gitops-manifests/custom-apps/<nombre-app>/`
   ```
   custom-apps/
   └── nueva-app/
       ├── deployment.yaml (imagen: localhost:30100/nueva-app:v1.0.0)
       ├── service.yaml (con nodePort: 30XXX)
       └── kustomization.yaml
   ```

4. **Crear repositorio en Gitea** y pushear código:
   ```bash
   # El install.sh ya tiene la lógica, o hacerlo manual:
   curl -X POST "http://localhost:30083/api/v1/user/repos" \
     -u "gitops:gitops" \
     -H "Content-Type: application/json" \
     -d '{"name": "nueva-app", "private": false}'
   
   cd /home/asanchez/Code/dotfiles/gitops-source-code/nueva-app
   git init && git add . && git commit -m "initial commit"
   git remote add gitea http://localhost:30083/gitops/nueva-app.git
   git push gitea main
   ```

5. **Construir y pushear imagen**:
   ```bash
   docker build -t localhost:30100/nueva-app:v1.0.0 .
   docker push localhost:30100/nueva-app:v1.0.0
   ```

6. **Commitear manifests** y ArgoCD desplegará automáticamente:
   ```bash
   cd /home/asanchez/Code/dotfiles/gitops-manifests
   git add custom-apps/nueva-app/
   git commit -m "feat: add nueva-app"
   git push gitea main
   ```

## 🔄 Flujo GitOps Completo

```
Developer
    ↓
Code in Gitea (source of truth)
    ↓
Argo Events (webhook trigger)
    ↓
Argo Workflows (build & push)
    ↓
Docker Registry (localhost:30100)
    ↓
ArgoCD (sync manifests)
    ↓
Kubernetes (deploy to cluster)
    ↓
NodePort (localhost:30XXX)
```

## 📝 Notas

- **No se requiere reiniciar el cluster** para usar nuevos puertos - todos están pre-configurados
- **Los puertos son persistentes** - sobreviven reinicios del cluster
- **Rango NodePort válido de Kubernetes**: 30000-32767
- **Puertos configurados**: 141 puertos (30080-30220)
- **Kind extraPortMappings** hace que los NodePorts sean accesibles desde Windows/Host

## 🎓 Entorno de Aprendizaje

Este setup está optimizado para:
- ✅ Añadir herramientas sin fricción
- ✅ Experimentar con diferentes stacks GitOps
- ✅ Practicar despliegues declarativos
- ✅ Probar integraciones entre herramientas
- ✅ Aprender best practices de Kubernetes y GitOps
