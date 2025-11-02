# GitOps Tools - Access Credentials

Generated: November 2, 2025

## 🔓 No Login Required (Anonymous/Skip Available)

| Tool | URL | Notes |
|------|-----|-------|
| **Argo Workflows** | http://localhost:30091 | `--auth-mode=server` (no login) |
| **Kubernetes Dashboard** | http://localhost:30090 | Click "Skip" button on login page |
| **Grafana** | http://localhost:30082 | Anonymous access enabled |
| **Prometheus** | http://localhost:30081 | Direct access, no auth |
| **Argo Rollouts Dashboard** | http://localhost:30084 | Direct access, no auth |
| **Registry UI** | http://localhost:30096 | Proxy mode, no auth |
| **Redis Commander** | http://localhost:30097 | Direct access, no auth |

## 🔐 Login Required

### Kargo
- **URL**: http://localhost:30085
- **Username**: `admin`
- **Password**: `gitops`
- **Notes**: Authentication is required per Kargo best practices. Password set to a fixed local value for learning; stored via SealedSecret.

### ArgoCD
- **URL**: http://localhost:30080
- **Username**: `admin`
- **Password**: Retrieved via:
  ```bash
  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
  ```

### Gitea
- **URL**: http://localhost:30083
- **Username**: `gitops`
- **Password**: Retrieved via:
  ```bash
  cat ~/.gitops-credentials/gitea-user.txt
  ```

---

## 📝 Best Practices Notes

### For Learning/Local Environment
- ✅ Most tools configured without login for easy exploration
- ✅ Kargo maintains auth as recommended by official documentation
- ✅ Credentials stored securely using SealedSecrets
- ✅ All UIs accessible via NodePorts

### For Production
- 🔒 Enable TLS/HTTPS (Ingress + cert-manager)
- 🔒 Configure SSO/OIDC for all tools
- 🔒 Use NetworkPolicies to restrict traffic
- 🔒 Implement proper RBAC with ServiceAccounts
- 🔒 Replace NodePort with LoadBalancer or Ingress
- 🔒 Enable audit logging
- 🔒 Use persistent storage (PVCs) for stateful tools

---

## 🔄 Credential Rotation

To rotate Kargo password:
```bash
# 1. Generate new sealed secret with new password
cd ~/dotfiles
./install.sh  # Will regenerate if missing

# 2. Check new credentials
cat ~/.gitops-credentials/kargo-admin.txt
```

To rotate ArgoCD password:
```bash
argocd account update-password --account admin --new-password <new-password>
```
