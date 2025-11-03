# Grafana Secrets Management

**⚠️ IMPORTANT**: Admin password is managed via SealedSecrets (not hardcoded).

## SealedSecret Generation

The Grafana admin password is generated dynamically during installation using **SealedSecrets**.

- **Function**: `create_grafana_secret()` in `install.sh`
- **Generated file**: `sealed-secret.yaml` (created during installation)
- **Credentials location**: `~/.gitops-credentials/grafana-admin.txt`

## Configuration

Grafana is configured for easy POC access:
- **Anonymous access**: Enabled (no login required for viewing)
- **Admin account**: Still available with secure password
- **User signup**: Disabled
- **Auto-assign role**: Admin for all users

## Secret Fields

The SealedSecret contains:
- `GF_SECURITY_ADMIN_PASSWORD`: Random 16-char password

## Accessing Grafana

After installation completes:
```bash
# View credentials (only needed for admin tasks)
cat ~/.gitops-credentials/grafana-admin.txt

# Access (no login required for viewing)
http://localhost:30003
```

## Why SealedSecrets?

- ✅ No hardcoded passwords in deployment.yaml
- ✅ Safe to commit `sealed-secret.yaml` to Git
- ✅ Admin password still available when needed
- ✅ Follows GitOps best practices
