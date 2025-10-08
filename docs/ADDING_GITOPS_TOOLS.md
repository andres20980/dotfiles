# Añadir Nuevas GitOps Tools

Este documento explica cómo extender tu entorno GitOps añadiendo nuevas herramientas.

## 🎯 Arquitectura de Auto-Discovery

El sistema está diseñado para **detectar automáticamente** nuevas herramientas que añadas, sin necesidad de modificar el script de instalación.

### Cómo funciona

1. **Escaneo dinámico de directorios**: Durante la instalación, el script escanea:
   - `manifests/gitops-tools/*/` - Para herramientas de infraestructura
   - `manifests/custom-apps/*/` - Para aplicaciones custom

2. **Pre-creación de namespaces**: Cada directorio encontrado se convierte en un namespace

3. **ApplicationSets de ArgoCD**: ArgoCD descubre automáticamente las aplicaciones basándose en la estructura de directorios

## 📝 Guía Paso a Paso

### Opción A: Desarrollo Local (Recomendado para POC)

```bash
# 1. Navega al repositorio local de infrastructure
cd ~/gitops-repos/gitops-infrastructure

# 2. Crea una carpeta para tu nueva tool
mkdir -p my-new-tool
cd my-new-tool

# 3. Crea los manifests de Kubernetes
cat > deployment.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-new-tool
  namespace: my-new-tool
  labels:
    app: my-new-tool
spec:
  replicas: 1
  selector:
    matchLabels:
      app: my-new-tool
  template:
    metadata:
      labels:
        app: my-new-tool
    spec:
      containers:
      - name: my-new-tool
        image: my-registry/my-new-tool:v1.0.0
        ports:
        - containerPort: 8080
          name: http
        env:
        - name: LOG_LEVEL
          value: "info"
EOF

cat > service.yaml <<EOF
apiVersion: v1
kind: Service
metadata:
  name: my-new-tool
  namespace: my-new-tool
spec:
  type: NodePort
  selector:
    app: my-new-tool
  ports:
  - port: 8080
    targetPort: 8080
    nodePort: 30100  # Puerto entre 30000-32767
    name: http
EOF

# 4. Commit y push a Gitea
git add my-new-tool/
git commit -m "feat: añadir my-new-tool"
git push gitea-infrastructure main

# 5. (Opcional) Backup a GitHub
git push origin main

# 6. Crea el namespace manualmente (o espera a la próxima instalación)
kubectl create namespace my-new-tool

# 7. ArgoCD detectará automáticamente la nueva aplicación
# Verifica en: http://localhost:30080
```

### Opción B: Desde el Repositorio Dotfiles

```bash
# 1. Navega al repositorio dotfiles
cd /home/asanchez/Code/dotfiles

# 2. Crea la estructura en manifests/gitops-tools/
mkdir -p manifests/gitops-tools/my-new-tool
cd manifests/gitops-tools/my-new-tool

# 3. Crea tus manifests (deployment.yaml, service.yaml, etc.)
# ... (igual que Opción A)

# 4. Commit a GitHub
git add manifests/gitops-tools/my-new-tool/
git commit -m "feat: añadir my-new-tool a gitops-tools"
git push origin main

# 5. Sincroniza con Gitea
cd /home/asanchez/Code/dotfiles
./scripts/sync-to-gitea.sh

# 6. La próxima vez que ejecutes install.sh, el namespace se creará automáticamente
./install.sh --unattended
```

## 🔐 Gestión de Secrets con Sealed Secrets

Si tu herramienta requiere credenciales sensibles:

### 1. Crea el Secret en formato YAML

```bash
# ⚠️ Usa un password real generado con: openssl rand -base64 32
kubectl create secret generic my-tool-credentials \
  --namespace=my-new-tool \
  --from-literal=username=admin \
  --from-literal=password='YOUR_SECURE_PASSWORD_HERE' \
  --dry-run=client -o yaml > secret.yaml
```

### 2. Cifra con kubeseal

```bash
kubeseal -o yaml < secret.yaml > sealed-secret.yaml
```

### 3. Añade el SealedSecret al repositorio

```bash
# En gitops-infrastructure
mv sealed-secret.yaml ~/gitops-repos/gitops-infrastructure/my-new-tool/
cd ~/gitops-repos/gitops-infrastructure
git add my-new-tool/sealed-secret.yaml
git commit -m "feat: añadir sealed secret para my-new-tool"
git push gitea-infrastructure main

# Borra el secret temporal
rm secret.yaml
```

### 4. Referencia el Secret en tu Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-new-tool
spec:
  template:
    spec:
      containers:
      - name: my-new-tool
        image: my-registry/my-new-tool:latest
        env:
        - name: USERNAME
          valueFrom:
            secretKeyRef:
              name: my-tool-credentials
              key: username
        - name: PASSWORD
          valueFrom:
            secretKeyRef:
              name: my-tool-credentials
              key: password
```

## 🎨 Estructura de Directorios Recomendada

```
my-new-tool/
├── README.md              # Documentación de la herramienta
├── namespace.yaml         # (Opcional) Configuración del namespace
├── deployment.yaml        # Deployment principal
├── service.yaml           # Servicio (NodePort para acceso local)
├── configmap.yaml         # (Opcional) Configuración
├── sealed-secret.yaml     # (Opcional) Credenciales cifradas
└── ingress.yaml           # (Opcional) Si usas Ingress Controller
```

## 📦 Ejemplos de Herramientas Comunes

### Jenkins

```bash
cd ~/gitops-repos/gitops-infrastructure
mkdir -p jenkins

cat > jenkins/deployment.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: jenkins
  namespace: jenkins
spec:
  replicas: 1
  selector:
    matchLabels:
      app: jenkins
  template:
    metadata:
      labels:
        app: jenkins
    spec:
      containers:
      - name: jenkins
        image: jenkins/jenkins:lts
        ports:
        - containerPort: 8080
        - containerPort: 50000
        volumeMounts:
        - name: jenkins-data
          mountPath: /var/jenkins_home
      volumes:
      - name: jenkins-data
        emptyDir: {}
EOF

cat > jenkins/service.yaml <<EOF
apiVersion: v1
kind: Service
metadata:
  name: jenkins
  namespace: jenkins
spec:
  type: NodePort
  selector:
    app: jenkins
  ports:
  - port: 8080
    targetPort: 8080
    nodePort: 30101
    name: http
  - port: 50000
    targetPort: 50000
    nodePort: 30102
    name: agent
EOF

git add jenkins/
git commit -m "feat: añadir Jenkins"
git push gitea-infrastructure main
```

### Vault (HashiCorp)

```bash
cd ~/gitops-repos/gitops-infrastructure
mkdir -p vault

cat > vault/deployment.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vault
  namespace: vault
spec:
  replicas: 1
  selector:
    matchLabels:
      app: vault
  template:
    metadata:
      labels:
        app: vault
    spec:
      containers:
      - name: vault
        image: hashicorp/vault:latest
        args:
        - server
        - -dev
        - -dev-root-token-id=root
        ports:
        - containerPort: 8200
        env:
        - name: VAULT_ADDR
          value: "http://127.0.0.1:8200"
EOF

cat > vault/service.yaml <<EOF
apiVersion: v1
kind: Service
metadata:
  name: vault
  namespace: vault
spec:
  type: NodePort
  selector:
    app: vault
  ports:
  - port: 8200
    targetPort: 8200
    nodePort: 30103
    name: http
EOF

git add vault/
git commit -m "feat: añadir Vault"
git push gitea-infrastructure main
```

## 🔍 Verificación y Debug

### Ver aplicaciones detectadas por ArgoCD

```bash
kubectl get applications -n argocd
```

### Ver el estado de tu nueva aplicación

```bash
kubectl get application my-new-tool -n argocd -o yaml
```

### Ver pods de tu herramienta

```bash
kubectl get pods -n my-new-tool
```

### Ver logs

```bash
kubectl logs -n my-new-tool -l app=my-new-tool --tail=100 -f
```

### Forzar sincronización de ArgoCD

```bash
kubectl patch app my-new-tool -n argocd \
  -p '{"operation":{"sync":{}}}' \
  --type merge
```

## 🚨 Troubleshooting

### La aplicación no aparece en ArgoCD

1. Verifica que el directorio existe en Gitea:
   ```bash
   curl http://localhost:30083/gitops/gitops-infrastructure/src/branch/main/my-new-tool
   ```

2. Verifica el ApplicationSet:
   ```bash
   kubectl get applicationset -n argocd gitops-tools -o yaml
   ```

3. Fuerza refresh del ApplicationSet:
   ```bash
   kubectl annotate applicationset gitops-tools -n argocd \
     argocd.argoproj.io/refresh=normal --overwrite
   ```

### El namespace no existe

Si el namespace no fue creado automáticamente:

```bash
kubectl create namespace my-new-tool
```

O espera a la próxima ejecución de `install.sh` (detectará automáticamente el nuevo directorio).

### El SealedSecret no se descifra

1. Verifica que el Sealed Secrets Controller está corriendo:
   ```bash
   kubectl get pods -n kube-system -l name=sealed-secrets-controller
   ```

2. Verifica que usaste la clave correcta del cluster:
   ```bash
   kubeseal --fetch-cert
   ```

3. Regenera el SealedSecret con la clave correcta:
   ```bash
   kubectl create secret generic my-credentials \
     --dry-run=client -o yaml \
     --from-literal=password=newsecret | \
   kubeseal -o yaml > sealed-secret.yaml
   ```

## 📖 Recursos Adicionales

- [ArgoCD ApplicationSets](https://argo-cd.readthedocs.io/en/stable/user-guide/application-set/)
- [Sealed Secrets Documentation](https://sealed-secrets.netlify.app/)
- [Kubernetes NodePort Services](https://kubernetes.io/docs/concepts/services-networking/service/#type-nodeport)
- [GitOps Principles](https://www.gitops.tech/)

## ✨ Tips y Best Practices

1. **Usa SealedSecrets**: Nunca hagas commit de Secrets en texto plano
2. **Documenta tus tools**: Añade un README.md en cada directorio
3. **Versiona las imágenes**: Usa tags específicos (`:v1.0.0`) en vez de `:latest`
4. **NodePort range**: Los puertos deben estar entre 30000-32767
5. **Labels consistentes**: Usa `app: nombre-tool` para facilitar búsquedas
6. **Namespaces dedicados**: Una herramienta = un namespace
7. **Backup a GitHub**: Siempre push a `origin main` después de `gitea-*`
