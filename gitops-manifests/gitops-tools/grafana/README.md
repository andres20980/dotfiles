# Gestión de Secretos de Grafana

**⚠️ IMPORTANTE**: La contraseña de administrador se gestiona con SealedSecrets (nunca en claro en Git).

## Generación del SealedSecret

La contraseña de administrador de Grafana se genera dinámicamente durante la instalación usando **SealedSecrets**.

- **Función**: `generate_initial_sealed_secrets()` en `install.sh`
- **Archivo generado**: `sealed-secret.yaml` (creado durante instalación)
- **Ubicación credenciales**: `~/.gitops-credentials/grafana-admin.txt`

## Configuración

Grafana está configurado para acceso fácil en POC:
- **Acceso anónimo**: Habilitado (no requiere login para visualizar)
- **Cuenta admin**: Disponible con contraseña segura
- **Registro usuarios**: Deshabilitado
- **Rol auto-asignado**: Admin para todos los usuarios

## Campos del SealedSecret

- `GF_SECURITY_ADMIN_PASSWORD`: contraseña (para demo: "gitops")

## Acceso a Grafana

Tras la instalación:
```bash
# Ver credenciales
cat ~/.gitops-credentials/grafana-admin.txt

# Acceder a la interfaz
http://localhost:30086
```

Usuario: `admin`  
Contraseña: Ver archivo de credenciales

## Ventajas de SealedSecrets

- ✅ Secretos encriptados con clave específica del cluster
- ✅ Seguro versionar `sealed-secret.yaml` en Git
- ✅ No hay credenciales hardcodeadas en el repositorio
- ✅ Sigue best practices de GitOps
