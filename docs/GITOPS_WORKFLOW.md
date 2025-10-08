# 🚀 GitOps Workflow - Arquitectura End-to-End

Este documento describe el flujo completo de GitOps implementado en este proyecto, desde el commit del developer hasta el monitoreo en producción.

---

## 📐 Arquitectura General

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         GITOPS END-TO-END WORKFLOW                          │
└─────────────────────────────────────────────────────────────────────────────┘

Developer                   CI/CD Pipeline              GitOps Engine          
    │                            │                            │                 
    │ 1. git push               │                            │                 
    │ ─────────────────────────>│                            │                 
    │                            │                            │                 
    │                            │ 2. Webhook trigger         │                 
    │                            │ <────────────────────────> │                 
    │                            │    (Gitea → Argo Events)   │                 
    │                            │                            │                 
    │                            │ 3. Start Workflow          │                 
    │                            │ ────────────────────────>  │                 
    │                            │    (Argo Events → Workflows)│                
    │                            │                            │                 
    │                            │ 4. Build + Push Image      │                 
    │                            │ <───────────────────────   │                 
    │                            │    (Workflow → Registry)   │                 
    │                            │                            │                 
    │                            │ 5. Update Manifests        │                 
    │                            │ ────────────────────────>  │                 
    │                            │    (Git commit)            │                 
    │                            │                            │                 
    │                            │                            │ 6. Detect Changes
    │                            │                            │ ──────────────>
    │                            │                            │ (ArgoCD Sync)  
    │                            │                            │                 
    │                            │                            │ 7. Canary Deploy
    │                            │                            │ ──────────────>
    │                            │                            │ (Argo Rollouts)
    │                            │                            │                 
    │                            │                            │ 8. Promote Stages
    │                            │                            │ ──────────────>
    │                            │                            │ (Kargo: dev→staging→prod)
    │                            │                            │                 
    │                            │ 9. Monitor & Observe       │                 
    │ <────────────────────────────────────────────────────────────────────   
    │    (Prometheus + Grafana)                                               

```

---

## 🔄 Flujo Detallado por Fases

### **FASE 1: Developer Commit** 👨‍💻

**Responsable:** Developer

**Acciones:**
1. Developer modifica código en `~/gitops-repos/sourcecode-apps/demo-app/`
2. Commit: `git commit -m "feat: nuevo endpoint /api/v2/users"`
3. Push: `git push origin main`

**Herramientas:**
- Git
- Gitea (repositorio local)

**Outputs:**
- Código fuente en Gitea
- Event de push registrado

---

### **FASE 2: Event Detection** 📡

**Responsable:** Argo Events

**Acciones:**
1. **EventSource** detecta webhook de Gitea
2. Extrae metadata:
   - Commit SHA
   - Branch (main/dev)
   - Author
   - Timestamp
3. **Sensor** evalúa condiciones:
   - ¿Branch = main? → trigger pipeline
   - ¿Branch = dev? → skip o pipeline de dev

**Manifests:**
```yaml
# EventSource: Gitea webhook listener
apiVersion: argoproj.io/v1alpha1
kind: EventSource
metadata:
  name: gitea-eventsource
  namespace: argo-events
spec:
  eventBusName: default
  webhook:
    demo-app:
      port: "12000"
      endpoint: /push
      method: POST

---
# Sensor: Trigger Argo Workflow on push
apiVersion: argoproj.io/v1alpha1
kind: Sensor
metadata:
  name: gitea-workflow-trigger
  namespace: argo-events
spec:
  dependencies:
    - name: gitea-dep
      eventSourceName: gitea-eventsource
      eventName: demo-app
  triggers:
    - template:
        name: trigger-ci-pipeline
        argoWorkflow:
          group: argoproj.io
          version: v1alpha1
          resource: workflows
          operation: submit
          source:
            resource:
              apiVersion: argoproj.io/v1alpha1
              kind: Workflow
              metadata:
                generateName: demo-app-ci-
                namespace: argo-workflows
              spec:
                # ... workflow template
```

**Outputs:**
- Argo Workflow triggered con metadata del commit

---

### **FASE 3: CI/CD Pipeline** ⚡

**Responsable:** Argo Workflows

**Acciones:**
1. **Clone repo**: Checkout código desde Gitea
2. **Build image**: Docker build con multi-stage
3. **Tag image**: `demo-app:${COMMIT_SHA}`
4. **Push registry**: Upload a `localhost:30087`
5. **Update manifests**: Modificar `image:` en YAMLs
6. **Git commit**: Push cambios a `gitops-custom-apps`

**Workflow YAML:**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: demo-app-ci-
  namespace: argo-workflows
spec:
  entrypoint: ci-pipeline
  
  volumes:
    - name: docker-sock
      hostPath:
        path: /var/run/docker.sock
        type: Socket
    - name: gitea-credentials
      secret:
        secretName: gitea-token
  
  templates:
    - name: ci-pipeline
      steps:
        - - name: checkout
            template: git-clone
        
        - - name: build-image
            template: docker-build
        
        - - name: push-image
            template: docker-push
        
        - - name: update-manifests
            template: update-k8s-manifests
    
    - name: git-clone
      container:
        image: alpine/git:latest
        command: [sh, -c]
        args:
          - |
            git clone http://gitea.gitea:3000/gitops/demo-app.git /workspace
            cd /workspace
            echo "Cloned commit: $(git rev-parse HEAD)"
        volumeMounts:
          - name: workspace
            mountPath: /workspace
    
    - name: docker-build
      container:
        image: gcr.io/kaniko-project/executor:latest
        command: ["/kaniko/executor"]
        args:
          - --dockerfile=/workspace/Dockerfile
          - --context=/workspace
          - --destination=localhost:30087/demo-app:{{workflow.parameters.commitSha}}
          - --insecure
          - --skip-tls-verify
        volumeMounts:
          - name: workspace
            mountPath: /workspace
          - name: docker-sock
            mountPath: /var/run/docker.sock
    
    - name: docker-push
      container:
        image: docker:latest
        command: [sh, -c]
        args:
          - |
            docker push localhost:30087/demo-app:{{workflow.parameters.commitSha}}
        volumeMounts:
          - name: docker-sock
            mountPath: /var/run/docker.sock
    
    - name: update-k8s-manifests
      container:
        image: alpine/git:latest
        command: [sh, -c]
        args:
          - |
            # Clone manifests repo
            git clone http://gitea.gitea:3000/gitops/custom-apps.git /manifests
            cd /manifests/demo-app
            
            # Update image tag
            sed -i "s|image: localhost:30087/demo-app:.*|image: localhost:30087/demo-app:{{workflow.parameters.commitSha}}|" deployment.yaml
            
            # Commit and push
            git config user.name "Argo Workflows"
            git config user.email "workflows@argocd.local"
            git add deployment.yaml
            git commit -m "chore: update image to {{workflow.parameters.commitSha}}"
            git push
        volumeMounts:
          - name: gitea-credentials
            mountPath: /root/.git-credentials
          - name: workspace
            mountPath: /workspace
  
  arguments:
    parameters:
      - name: commitSha
        value: "{{workflow.parameters.commitSha}}"
      - name: branch
        value: "main"
```

**Outputs:**
- Docker image en registry: `localhost:30087/demo-app:abc123def`
- Manifests actualizados en Gitea repo `custom-apps`

---

### **FASE 4: Image Detection** 🔍

**Responsable:** Argo Image Updater (opcional)

**Acciones:**
1. Monitorea registry cada 2 minutos
2. Detecta nueva imagen `demo-app:abc123def`
3. Si configurado: auto-update manifests
4. Write-back a Git (alternativa al Workflow)

**Annotations en Application:**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: demo-app
  namespace: argocd
  annotations:
    argocd-image-updater.argoproj.io/image-list: demo-app=localhost:30087/demo-app
    argocd-image-updater.argoproj.io/demo-app.update-strategy: digest
    argocd-image-updater.argoproj.io/write-back-method: git
    argocd-image-updater.argoproj.io/git-branch: main
spec:
  # ...
```

**Outputs:**
- Git commit automático con nueva imagen (si habilitado)

---

### **FASE 5: GitOps Sync** 🔄

**Responsable:** ArgoCD

**Acciones:**
1. Detecta cambios en `gitops-custom-apps` repo
2. Compara estado deseado (Git) vs actual (cluster)
3. Calcula diff de recursos
4. Aplica cambios con `kubectl apply`

**Application YAML:**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: demo-app-dev
  namespace: argocd
spec:
  project: applications
  source:
    repoURL: http://gitea.gitea:3000/gitops/custom-apps.git
    targetRevision: HEAD
    path: demo-app/overlays/dev
  destination:
    server: https://kubernetes.default.svc
    namespace: demo-app-dev
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

**Outputs:**
- Nuevos recursos K8s aplicados
- Rollout iniciado (si usa Argo Rollouts)

---

### **FASE 6: Progressive Delivery** 🎲

**Responsable:** Argo Rollouts

**Acciones:**
1. Detecta nuevo ReplicaSet
2. **Canary Strategy:**
   - **Step 1:** 20% traffic → nueva versión (wait 2min)
   - **Step 2:** 50% traffic → nueva versión (wait 5min)
   - **Step 3:** 100% traffic → nueva versión
3. **Analysis:** Query Prometheus cada step:
   - Error rate < 5%
   - Latency p95 < 500ms
4. **Auto-rollback:** Si falla analysis → rollback automático

**Rollout YAML:**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: demo-app
  namespace: demo-app-dev
spec:
  replicas: 5
  strategy:
    canary:
      steps:
        - setWeight: 20
        - pause: {duration: 2m}
        - analysis:
            templates:
              - templateName: success-rate-check
        
        - setWeight: 50
        - pause: {duration: 5m}
        - analysis:
            templates:
              - templateName: success-rate-check
              - templateName: latency-check
        
        - setWeight: 100
      
      trafficRouting:
        nginx:
          stableService: demo-app-stable
          canaryService: demo-app-canary
  
  selector:
    matchLabels:
      app: demo-app
  
  template:
    metadata:
      labels:
        app: demo-app
    spec:
      containers:
        - name: demo-app
          image: localhost:30087/demo-app:abc123def
          ports:
            - containerPort: 3000
          livenessProbe:
            httpGet:
              path: /health
              port: 3000
          readinessProbe:
            httpGet:
              path: /health
              port: 3000

---
# Analysis Template: Success Rate
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: success-rate-check
  namespace: demo-app-dev
spec:
  metrics:
    - name: success-rate
      interval: 30s
      successCondition: result[0] >= 0.95
      failureLimit: 3
      provider:
        prometheus:
          address: http://prometheus.prometheus:9090
          query: |
            sum(rate(
              http_requests_total{
                app="demo-app",
                status!~"5.."
              }[2m]
            )) /
            sum(rate(
              http_requests_total{
                app="demo-app"
              }[2m]
            ))

---
# Analysis Template: Latency
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: latency-check
  namespace: demo-app-dev
spec:
  metrics:
    - name: latency-p95
      interval: 30s
      successCondition: result[0] <= 500
      failureLimit: 3
      provider:
        prometheus:
          address: http://prometheus.prometheus:9090
          query: |
            histogram_quantile(0.95,
              sum(rate(
                http_request_duration_milliseconds_bucket{
                  app="demo-app"
                }[2m]
              )) by (le)
            )
```

**Outputs:**
- Rollout gradual con validación automática
- Rollback si falla analysis

---

### **FASE 7: Multi-Stage Promotion** 🚦

**Responsable:** Kargo

**Acciones:**
1. **Stage: DEV**
   - Auto-promote on Healthy
   - Freight: `demo-app:abc123def`
2. **Stage: STAGING**
   - Manual approval required
   - Integration tests validation
3. **Stage: PRODUCTION**
   - Manual approval (2 approvers)
   - Canary deployment
   - Smoke tests post-deploy

**Kargo Project:**
```yaml
apiVersion: kargo.akuity.io/v1alpha1
kind: Project
metadata:
  name: demo-app
spec:
  promotionPolicies:
    - stage: dev
      autoPromotionEnabled: true
    - stage: staging
      autoPromotionEnabled: false
    - stage: prod
      autoPromotionEnabled: false

---
# Stage: DEV
apiVersion: kargo.akuity.io/v1alpha1
kind: Stage
metadata:
  name: dev
  namespace: demo-app
spec:
  subscriptions:
    warehouse: demo-app-images
  promotionMechanisms:
    gitRepoUpdates:
      - repoURL: http://gitea.gitea:3000/gitops/custom-apps.git
        writeBranch: main
        kustomize:
          images:
            - image: localhost:30087/demo-app
              path: demo-app/overlays/dev

---
# Stage: STAGING
apiVersion: kargo.akuity.io/v1alpha1
kind: Stage
metadata:
  name: staging
  namespace: demo-app
spec:
  subscriptions:
    upstreamStages:
      - name: dev
  promotionMechanisms:
    gitRepoUpdates:
      - repoURL: http://gitea.gitea:3000/gitops/custom-apps.git
        writeBranch: main
        kustomize:
          images:
            - image: localhost:30087/demo-app
              path: demo-app/overlays/staging
  verification:
    analysisTemplates:
      - name: integration-tests

---
# Stage: PRODUCTION
apiVersion: kargo.akuity.io/v1alpha1
kind: Stage
metadata:
  name: prod
  namespace: demo-app
spec:
  subscriptions:
    upstreamStages:
      - name: staging
  promotionMechanisms:
    gitRepoUpdates:
      - repoURL: http://gitea.gitea:3000/gitops/custom-apps.git
        writeBranch: main
        kustomize:
          images:
            - image: localhost:30087/demo-app
              path: demo-app/overlays/prod
  verification:
    analysisTemplates:
      - name: smoke-tests
      - name: performance-tests
```

**Outputs:**
- Promoción controlada entre environments
- Audit trail de aprobaciones

---

### **FASE 8: Observability** 📊

**Responsable:** Prometheus + Grafana

**Acciones:**
1. **Prometheus** scrapes `/metrics`:
   - Request rate (QPS)
   - Error rate (%)
   - Latency (p50, p95, p99)
   - Custom business metrics
2. **Grafana** visualiza:
   - Deployment history timeline
   - Rollout progress (canary %)
   - Resource usage (CPU, memory)
   - Application-specific dashboards

**ServiceMonitor:**
```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: demo-app
  namespace: demo-app-dev
spec:
  selector:
    matchLabels:
      app: demo-app
  endpoints:
    - port: metrics
      path: /metrics
      interval: 30s
```

**Grafana Dashboard (JSON snippet):**
```json
{
  "dashboard": {
    "title": "Demo App - GitOps Metrics",
    "panels": [
      {
        "title": "Request Rate (QPS)",
        "targets": [{
          "expr": "rate(http_requests_total{app=\"demo-app\"}[5m])"
        }]
      },
      {
        "title": "Error Rate (%)",
        "targets": [{
          "expr": "sum(rate(http_requests_total{app=\"demo-app\",status=~\"5..\"}[5m])) / sum(rate(http_requests_total{app=\"demo-app\"}[5m])) * 100"
        }]
      },
      {
        "title": "Latency (p95)",
        "targets": [{
          "expr": "histogram_quantile(0.95, sum(rate(http_request_duration_milliseconds_bucket{app=\"demo-app\"}[5m])) by (le))"
        }]
      },
      {
        "title": "Deployment Timeline",
        "targets": [{
          "expr": "kube_deployment_status_replicas_updated{deployment=\"demo-app\"}"
        }]
      }
    ]
  }
}
```

**Outputs:**
- Real-time metrics dashboards
- Alerting on thresholds
- Historical data for analysis

---

## 🎯 Responsabilidades por Herramienta

| Herramienta | Fase | Responsabilidad |
|-------------|------|-----------------|
| **Gitea** | 1 | Repositorio Git local, webhook events |
| **Argo Events** | 2 | Event detection, webhook listener, trigger workflows |
| **Argo Workflows** | 3 | CI/CD pipeline, build, test, update manifests |
| **Docker Registry** | 3 | Almacenamiento de imágenes Docker |
| **Argo Image Updater** | 4 | Auto-detect nuevas imágenes, write-back to Git |
| **ArgoCD** | 5 | GitOps sync, declarative deployments |
| **Argo Rollouts** | 6 | Progressive delivery, canary, blue-green, analysis |
| **Kargo** | 7 | Multi-stage promotion, freight tracking, approvals |
| **Prometheus** | 8 | Metrics collection, scraping, alerting |
| **Grafana** | 8 | Visualization, dashboards, monitoring |
| **Sealed Secrets** | All | Encrypted secrets management |
| **Kubernetes Dashboard** | All | Cluster visibility, debugging |

---

## 🔐 Seguridad y Secrets

### Sealed Secrets Flow
```
Developer → Create Secret → Seal with kubeseal → Commit SealedSecret → ArgoCD deploys → Controller decrypts → Pod uses Secret
```

### Gestión de Credenciales
- ✅ Gitea: Token en SealedSecret
- ✅ Registry: Insecure (localhost only)
- ✅ Kargo: Admin credentials en SealedSecret
- ✅ Grafana: Admin password en SealedSecret (anonymous access enabled)

---

## 📝 Guía de Uso para Developers

### Hacer un cambio y desplegarlo

```bash
# 1. Navega a la app
cd ~/gitops-repos/sourcecode-apps/demo-app

# 2. Haz cambios en el código
vim server.js

# 3. Commit y push
git add .
git commit -m "feat: nuevo endpoint /api/v2/users"
git push origin main

# 4. Verifica el pipeline en Argo Workflows UI
open http://localhost:30089

# 5. Monitorea el rollout en Argo Rollouts Dashboard
open http://localhost:30084

# 6. Verifica deployment en ArgoCD
open http://localhost:30080

# 7. Monitorea métricas en Grafana
open http://localhost:30082
```

### Promover a staging (Kargo)

```bash
# 1. Accede a Kargo UI
open http://localhost:30085

# 2. Login con admin/admin123

# 3. Navega a Project "demo-app"

# 4. Click en Stage "staging"

# 5. Click "Promote" en el Freight desde dev

# 6. Aprobar promoción (manual)

# 7. Monitorea deployment en ArgoCD
```

### Rollback manual

```bash
# Opción 1: Via ArgoCD UI
# History → Select previous revision → Rollback

# Opción 2: Via kubectl
kubectl argo rollouts undo rollout/demo-app -n demo-app-dev

# Opción 3: Via Git
cd ~/gitops-repos/gitops-custom-apps/demo-app
git revert HEAD
git push origin main
```

---

## 🚨 Troubleshooting

### Pipeline no se triggerea

**Síntomas:** Push a Git pero no hay Workflow ejecutándose

**Debug:**
```bash
# 1. Verificar EventSource está Running
kubectl get pods -n argo-events -l eventsource-name=gitea-eventsource

# 2. Ver logs del EventSource
kubectl logs -n argo-events -l eventsource-name=gitea-eventsource

# 3. Verificar Sensor está Running
kubectl get pods -n argo-events -l sensor-name=gitea-workflow-trigger

# 4. Ver logs del Sensor
kubectl logs -n argo-events -l sensor-name=gitea-workflow-trigger

# 5. Verificar webhook en Gitea
curl http://localhost:30083/gitops/demo-app/settings/hooks
```

**Soluciones:**
- Verificar webhook URL apunta a `http://argo-events-webhook.argo-events:12000/push`
- Verificar secret token del webhook
- Re-trigger manualmente el webhook desde Gitea UI

---

### Rollout stuck

**Síntomas:** Canary deployment no progresa

**Debug:**
```bash
# 1. Ver estado del Rollout
kubectl argo rollouts get rollout demo-app -n demo-app-dev

# 2. Ver Analysis Run
kubectl get analysisrun -n demo-app-dev

# 3. Ver logs de análisis
kubectl logs -n demo-app-dev analysisrun/demo-app-xxx

# 4. Query Prometheus directamente
curl -G http://localhost:30081/api/v1/query \
  --data-urlencode 'query=rate(http_requests_total{app="demo-app"}[2m])'
```

**Soluciones:**
- Verificar que Prometheus está scraping la app
- Verificar que la app expone `/metrics`
- Ajustar thresholds en AnalysisTemplate si son muy estrictos

---

### ArgoCD no syncroniza

**Síntomas:** Cambios en Git pero ArgoCD no aplica

**Debug:**
```bash
# 1. Ver estado de Application
kubectl get application demo-app-dev -n argocd -o yaml

# 2. Ver eventos
kubectl get events -n argocd --sort-by='.lastTimestamp'

# 3. Verificar conectividad a Gitea
kubectl exec -n argocd argocd-server-xxx -- \
  curl http://gitea.gitea:3000/gitops/custom-apps.git
```

**Soluciones:**
- Hard refresh: `kubectl patch app demo-app-dev -n argocd -p '{"operation":{"sync":{}}}' --type merge`
- Verificar credentials del repo en ArgoCD
- Verificar que el path existe en el repo

---

## 📚 Recursos y Documentación

- [Argo CD Docs](https://argo-cd.readthedocs.io/)
- [Argo Workflows Docs](https://argo-workflows.readthedocs.io/)
- [Argo Events Docs](https://argoproj.github.io/argo-events/)
- [Argo Rollouts Docs](https://argo-rollouts.readthedocs.io/)
- [Kargo Docs](https://docs.kargo.io/)
- [Sealed Secrets Docs](https://sealed-secrets.netlify.app/)
- [Prometheus Docs](https://prometheus.io/docs/)
- [Grafana Docs](https://grafana.com/docs/)

---

## ✨ Best Practices

1. **Trunk-based development**: Trabajar en `main` branch con feature flags
2. **Immutable tags**: Usar commit SHA como image tag
3. **Progressive rollouts**: Siempre usar canary con analysis
4. **Manual approvals**: Staging y Prod requieren aprobación humana
5. **Monitoring first**: Configurar metrics antes de deploy
6. **Rollback plan**: Siempre tener strategy de rollback documentada
7. **GitOps principles**: Git es single source of truth
8. **Sealed secrets**: Nunca commitear secrets en texto plano
9. **Audit trail**: Todos los cambios tracked en Git
10. **Automation**: Minimize manual intervention en dev/staging

---

**Última actualización:** 2025-10-08  
**Versión:** 1.0  
**Autor:** GitOps Master Setup Team
