# 🤖 GitHub Copilot Chat - Guía de Uso

> **Guía para contribuyentes: uso efectivo de GitHub Copilot Chat en este repositorio GitOps**

## 1. 🎯 Política de Modelos

**Regla principal**: Prioriza SIEMPRE modelos gratuitos para desarrollo general.

**Excepciones críticas** (cambia temporalmente a modelo avanzado):
- Modificaciones en `scripts/install.sh`
- Edición de `gitops/bootstrap/app-of-apps.yaml` 
- Configuración RBAC/Projects de ArgoCD
- Manifests de Ingress/NGINX

**Protocolo**: Al inicio del turno, declara explícitamente el cambio de modelo y justificación. Vuelve al modelo gratuito tras completar la tarea crítica.

## 2. 📋 Convenciones Congeladas

### Namespaces
- `argocd`: ArgoCD controller y UI
- `monitoring`: Prometheus, Grafana, herramientas observabilidad
- `argo-rollouts`: Argo Rollouts controller y dashboard
- `sealed-secrets`: Sealed Secrets controller
- `gitea`: Git server local
- `hello-world`: Aplicaciones demo
- `kubernetes-dashboard`: Dashboard Kubernetes

### Puertos NodePort
- `30080`: ArgoCD UI
- `30081`: Kubernetes Dashboard
- `30082`: Hello World App
- `30083`: Gitea Git Server
- `30084`: Argo Rollouts Dashboard
- `30085`: Argo Workflows UI (futuro)
- `30086`: Argo Image Updater webhook
- `30087`: Hello World Canary (ejemplo)
- `30092`: Prometheus
- `30093`: Grafana
- `30094`: Argo Events webhook endpoint
- `30095-30099`: Reservados expansión futura

### Credenciales Demo
- ArgoCD: `admin / [PASSWORD_FROM_ENV]`
- Gitea: `gitops / [PASSWORD_FROM_ENV]`
- Grafana: `admin / [PASSWORD_FROM_ENV]`
- Dashboard: Skip login habilitado

### Cluster Kind
- Nombre: `mini-cluster`
- Configuración: `config/kind-config.yaml`
- Versión Kubernetes: latest estable

### Árbol del Repositorio
- `scripts/`: Instalación modular orquestada
- `setup/`: Scripts por fase (system, docker, cluster)  
- `gitops/`: Bootstrap y configuración ArgoCD
- `manifests/`: YAMLs Kubernetes (infrastructure/applications)
- `source-code/`: Código fuente aplicaciones
- `config/`: Configuraciones cluster y herramientas

## 3. ✅ Validación Obligatoria

Tras cada entrega, ejecutar en orden:

```
# Validación sintaxis YAML
yamllint .

# Validación conformidad Kubernetes
kubeconform -strict -summary \
  -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/' \
  manifests/**/*.yaml

# Validación scripts bash
shellcheck scripts/*.sh setup/*.sh gitops/**/*.sh
```

**No proceder** sin resolver todos los errores/warnings.

## 4. 📄 Formato de Entrega

### Archivo NUEVO
- Entregar contenido completo en bloque Markdown
- Incluir encabezados de sección y documentación

### Archivo EXISTENTE  
- Solo parche `unified diff` (-/+ format)
- Incluir 3-5 líneas contexto antes/después del cambio
- Especificar razón del cambio

### Ejecución Directa
- **CRÍTICO**: Las modificaciones de ficheros o código se ejecutan directamente usando herramientas de edición
- **NO mostrar** el código modificado en el chat
- Solo confirmar la acción realizada (ej: "Archivo modificado correctamente")
- Mostrar código únicamente si el usuario lo solicita explícitamente

Ejemplo diff:
```
--- manifests/applications/app.yaml
+++ manifests/applications/app.yaml  
@@ -8,7 +8,8 @@
   labels:
     app: hello-world
 spec:
-  replicas: 1
+  replicas: 3
+  strategy: RollingUpdate
   selector:
     matchLabels:
```

## 5. ⚠️ Bloques Críticos (Modelo Avanzado)

Cambiar temporalmente a modelo avanzado para:

1. **`scripts/install.sh`**: Instalador maestro, lógica orquestación
2. **`gitops/bootstrap/app-of-apps.yaml`**: Pattern ArgoCD crítico  
3. **RBAC/Projects ArgoCD**: Permisos y seguridad cluster
4. **Ingress/NGINX**: Configuraciones exposición servicios

**Justificación**: Estos componentes afectan funcionamiento completo del cluster y patrones GitOps. Errores aquí requieren reinstalación completa.

## 6. 🚀 Prompt Inicial Recomendado (Modo Auto)

```
Trabajando en repositorio GitOps con arquitectura modular:

1. CONVENCIONES CONGELADAS: puertos 30080-30099, namespaces 
   (argocd/monitoring/gitea/hello-world/kubernetes-dashboard), 
   credenciales demo, cluster kind "mini-cluster"

2. ESTRUCTURA: scripts/install.sh (orquestador) → setup/* (fases) 
   → gitops/bootstrap → manifests/infrastructure|applications

3. SECUENCIA: árbol análisis → install.sh modificación → 
   app-of-apps.yaml → ArgoCD Applications deployment

4. VALIDACIÓN: yamllint + kubeconform + shellcheck obligatorios

5. ENTREGA: diff patches para existentes, completo para nuevos

Usar modelo gratuito por defecto. Cambiar a avanzado solo para 
install.sh, app-of-apps.yaml, RBAC, Ingress (declarar cambio).
```

## 7. ✅ Checklist Pre-Merge

Verificar antes de cualquier merge:

### Validación Código
- [ ] `yamllint .` sin errores
- [ ] `kubeconform` conformidad strict
- [ ] `shellcheck` scripts sin warnings

### Funcionalidad Cluster  
- [ ] `kubectl get pods --all-namespaces` todos Running
- [ ] `kubectl get applications -n argocd` todos Synced & Healthy
- [ ] URLs accesibles (30080-30093)

### GitOps Workflow
- [ ] ArgoCD UI muestra aplicaciones sincronizadas
- [ ] Cambios manifests reflejados automáticamente  
- [ ] No drift entre Git y cluster

### Acceso Servicios
- [ ] ArgoCD: http://localhost:30080 (admin/[SECURE_PASSWORD])
- [ ] Dashboard: https://localhost:30081 (skip login)
- [ ] Hello World: http://localhost:30082 
- [ ] Gitea: http://localhost:30083 (gitops/[SECURE_PASSWORD])
- [ ] Prometheus: http://localhost:30092
- [ ] Grafana: http://localhost:30093 (admin/[SECURE_PASSWORD])

---

> **💡 Contribuyentes**: Este proyecto busca excelencia en organización Git, documentación y instalación modular. Respeta las convenciones establecidas para mantener la coherencia del entorno de aprendizaje GitOps.