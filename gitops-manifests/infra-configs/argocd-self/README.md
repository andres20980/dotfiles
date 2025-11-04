# Auto-configuración de Argo CD (Self-Managed)

Este directorio contiene la configuración declarativa de Argo CD para el entorno de aprendizaje:

- ConfigMaps (`argocd-cm`, `argocd-rbac-cm`, `argocd-cmd-params-cm`)
- Service `argocd-server` expuesto como NodePort 30080 (HTTP)
- AppProjects (`argocd-config`, `gitops-tools`, `custom-apps`)

Argo CD se gestiona a sí mismo a través de la Application `argocd-self-config` definida en `infra-configs/applications/argo-self-management.yaml`.

Notas:
- Acceso anónimo y modo inseguro están habilitados para facilitar el aprendizaje (NO usar en producción).
- Si quieres endurecer, cambia estos ficheros y Argo CD reconciliará automáticamente.
