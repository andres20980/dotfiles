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

# Gestión de secretos de Grafana

Importante: la contraseña de administrador se gestiona con SealedSecrets (nunca en claro en Git).

## ¿Cómo se genera?

Durante la instalación, `install.sh` ejecuta `generate_initial_sealed_secrets()` que:
- Obtiene la clave pública del controlador de Sealed Secrets
- Genera `gitops-tools/grafana/sealed-secret.yaml` con la contraseña admin
- Realiza commit/push al repo `gitops-manifests` en Gitea

## Campos del SealedSecret

- `GF_SECURITY_ADMIN_PASSWORD`: contraseña (para demo: "gitops")

## Acceso a Grafana

Tras la instalación:
```bash
http://localhost:<nodeport-grafana>
```

## Ventajas de SealedSecrets

- No hay contraseñas en texto plano en Git
- Se puede versionar de forma segura
- Compatible con GitOps puro
