# Para ver herramientas instaladas en ArgoCD, puedes crear aplicaciones así:

# 1. Para el Dashboard de Kubernetes:
kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kubernetes-dashboard
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/kubernetes/dashboard
    targetRevision: v2.7.0
    path: aio/deploy/recommended.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: kubernetes-dashboard
EOF

# 2. Para ArgoCD mismo:
kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: argocd-system
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/argoproj/argo-cd
    targetRevision: stable
    path: manifests
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
EOF
