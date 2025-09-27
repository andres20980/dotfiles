# ArgoCD + Gitea Local Setup

Este setup instala ArgoCD y Gitea localmente en el cluster de Kubernetes para proporcionar un entorno completo de GitOps sin dependencias externas.

## Arquitectura

- **ArgoCD**: Herramienta de GitOps para despliegue continuo
- **Gitea**: Servidor Git ligero (SQLite, sin autenticación) que aloja los repositorios locales
- **Aplicaciones**: Dashboard de Kubernetes y aplicación Hello World como ejemplos

## Estructura de Directorios

```
argo-apps/
├── gitops-tools/           # Herramientas de GitOps
│   ├── dashboard/         # Kubernetes Dashboard
│   │   ├── application.yaml
│   │   └── manifests/     # Manifiestos K8s
│   └── .git/             # Repositorio Git
└── custom-apps/          # Aplicaciones personalizadas
    ├── hello-world/      # App de ejemplo
    │   ├── application.yaml
    │   └── manifests/    # Manifiestos K8s
    └── .git/             # Repositorio Git
```

## Servicios Disponibles

| Servicio | URL | Puerto | Descripción |
|----------|-----|--------|-------------|
| ArgoCD | http://localhost:30080 | 30080 | Interfaz de ArgoCD |
| Gitea | http://localhost:30083 | 30083 | Servidor Git local |
| Dashboard | https://localhost:30081 | 30081 | Kubernetes Dashboard |
| Hello World | http://localhost:30082 | 30082 | App de ejemplo |

## Instalación

1. **Instalación completa**:
   ```bash
   ./install.sh
   ```

2. **Crear aplicaciones en ArgoCD**:
   ```bash
   ./create-argocd-apps.sh
   ```

3. **Configurar repositorios** (opcional):
   ```bash
   ./setup-argocd-repos.sh
   ```

## Acceso a Gitea

- **URL**: http://localhost:30083
- **Usuario**: argocd
- **Contraseña**: argocd123

## Repositorios

- **GitOps Tools**: http://gitea.mini-cluster/argocd/gitops-tools
- **Custom Apps**: http://gitea.mini-cluster/argocd/custom-apps

## Desarrollo

Para agregar nuevas aplicaciones:

1. Crear directorio en `argo-apps/custom-apps/`
2. Agregar manifiestos en `manifests/`
3. Crear `application.yaml` apuntando al repo de Gitea
4. Hacer commit y push
5. ArgoCD detectará los cambios automáticamente

## Troubleshooting

### ArgoCD muestra "Unknown" status
- Verificar que Gitea esté corriendo: `kubectl get pods -n gitea`
- Verificar conectividad: `kubectl exec -n argocd deployment/argocd-repo-server -- git ls-remote http://gitea.gitea.svc.cluster.local:3000/argocd/gitops-tools.git`

### Aplicaciones no se sincronizan
- Revisar logs de ArgoCD: `kubectl logs -n argocd deployment/argocd-application-controller`
- Verificar configuración de aplicaciones: `kubectl get applications -n argocd -o yaml`

## Beneficios

- ✅ Todo corre localmente (sin dependencias externas)
- ✅ Gitea ligero (SQLite, sin autenticación compleja)
- ✅ ArgoCD con sync automático
- ✅ Estructura organizada para múltiples aplicaciones
- ✅ Fácil de extender con nuevas aplicaciones