# ArgoCD Applications Structure

Este directorio contiene todas las aplicaciones gestionadas por ArgoCD, organizadas en dos categorías principales:

## 📁 Estructura de Directorios

```
argocd-apps/
├── gitops-tools/          # 🔧 Herramientas de GitOps/Infrastructure
│   └── dashboard/         # Kubernetes Dashboard (versión ligera)
└── custom-apps/           # 🛠️ Tus aplicaciones personalizadas
    └── hello-world/       # Aplicación de ejemplo para aprender GitOps
```

## 🔧 GitOps Tools

Herramientas de infraestructura que se despliegan de forma centralizada. Características:
- **Versión ligera**: Configuración mínima necesaria
- **Sin autenticación**: Cuando sea posible para facilitar desarrollo
- **Gestionadas por ArgoCD**: Siguen principios GitOps
- **Estado esperado**: Synced + Healthy

### Herramientas actuales:
- **Kubernetes Dashboard**: UI para gestión del cluster (puerto 30081)

## 🛠️ Custom Apps

Tus aplicaciones personalizadas. Cada aplicación debe tener:
- `application.yaml`: Definición de la aplicación ArgoCD
- `manifests/`: Directorio con los manifests de Kubernetes
- **Estado esperado**: Synced + Healthy

### Aplicaciones actuales:
- **Hello World**: Ejemplo simple con Nginx (puerto 30082)

## 🚀 Cómo añadir nuevas aplicaciones

### Para GitOps Tools:
```bash
mkdir -p argocd-apps/gitops-tools/<nombre-herramienta>
# Crear application.yaml y manifests según sea necesario
```

### Para Custom Apps:
```bash
mkdir -p argocd-apps/custom-apps/<nombre-app>
# Crear application.yaml apuntando a manifests/
mkdir manifests/
# Crear tus manifests de Kubernetes
```

## 📋 Estados de ArgoCD

Una aplicación se considera correctamente desplegada cuando:
- **SYNC STATUS**: `Synced`
- **HEALTH STATUS**: `Healthy`

Si ves `Unknown` o `Degraded`, revisa los logs de ArgoCD y los eventos del namespace.