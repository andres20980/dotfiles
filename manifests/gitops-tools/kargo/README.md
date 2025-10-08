# Kargo Secrets Management

**⚠️ IMPORTANT**: This directory does NOT contain plain secrets.

## SealedSecret Generation

The Kargo admin credentials are generated dynamically during installation using **SealedSecrets**.

- **Function**: `create_kargo_secret_workaround()` in `install.sh`
- **Generated file**: `sealed-secret.yaml` (created during installation)
- **Credentials location**: `~/.gitops-credentials/kargo-admin.txt`

## Secret Fields

The SealedSecret contains all 8 required fields:
1. `ADMIN_ACCOUNT_ENABLED`: "true"
2. `ADMIN_ACCOUNT_USERNAME`: "admin"
3. `ADMIN_ACCOUNT_PASSWORD`: Random 16-char password
4. `ADMIN_ACCOUNT_PASSWORD_HASH`: Bcrypt hash (cost 10)
5. `ADMIN_ACCOUNT_TOKEN_SIGNING_KEY`: Random 32-char key
6. `ADMIN_ACCOUNT_TOKEN_ISSUER`: "kargo-api"
7. `ADMIN_ACCOUNT_TOKEN_AUDIENCE`: "kargo-api"
8. `ADMIN_ACCOUNT_TOKEN_TTL`: "24h"

## Accessing Kargo

After installation completes:
```bash
cat ~/.gitops-credentials/kargo-admin.txt
```

Access: http://localhost:30094

## Why SealedSecrets?

- ✅ Secrets encrypted with cluster-specific key
- ✅ Safe to commit `sealed-secret.yaml` to Git
- ✅ No hardcoded credentials in repository
- ✅ Follows GitOps best practices
