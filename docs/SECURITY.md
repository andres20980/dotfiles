# 🔐 GitOps Security Guide

## 🚨 VULNERABILIDAD CORREGIDA

**Problema detectado por GitGuardian:** Credenciales hardcodeadas en el código fuente expuestas públicamente.

**Solución implementada:** Sistema de credenciales seguras con generación aleatoria y variables de entorno.

## 🔒 Nuevo Flujo Seguro

### 1. Configurar Credenciales Seguras

```bash
# Generar credenciales aleatorias (RECOMENDADO)
./scripts/set-credentials.sh

# Opción 1: Passwords aleatorios generados automáticamente
# Opción 2: Introducir passwords manualmente  
# Opción 3: Cargar desde archivo .env
```

### 2. Ejecutar GitOps Bootstrap

```bash
# Las credenciales ya están en el entorno
./gitops/bootstrap/install-gitops.sh
```

### 3. Acceder a los Servicios

Las credenciales se muestran al generar/configurar, **no** están en el código fuente.

## 🛡️ Medidas de Seguridad Implementadas

### ✅ Variables de Entorno
- **Antes:** `password=gitops123` (hardcoded)
- **Ahora:** `password=${GITEA_ADMIN_PASSWORD}` (variable)

### ✅ Generación Aleatoria
- Passwords de 20 caracteres aleatorios
- OpenSSL para generación criptográficamente segura
- No repetición de credenciales

### ✅ .gitignore Mejorado
```gitignore
# Credenciales y secrets
.env
.env.*
*credentials*
*secrets*
*.key
/tmp/.gitops-*
*-secret.yaml
!sealed-*-secret.yaml
```

### ✅ Validación Previa
```bash
if [[ -z "$GITEA_ADMIN_PASSWORD" ]]; then
    echo "❌ ERROR: Variable GITEA_ADMIN_PASSWORD no definida"
    exit 1
fi
```

## 🔐 Sealed Secrets (Próximo)

### Generador de Sealed Secrets
```bash
# Generar sealed secrets para Kubernetes
./scripts/generate-secure-credentials.sh
```

### Flujo Sealed Secrets
1. **Generar:** Credenciales → Secrets temporales
2. **Encriptar:** `kubeseal` → Sealed Secrets
3. **Commitear:** Solo sealed secrets (encriptados) 
4. **Desplegar:** Sealed Secrets Controller → Secrets reales

## 📋 Checklist de Seguridad

- [x] **Eliminar credenciales hardcodeadas** del código fuente
- [x] **Implementar variables de entorno** para credenciales  
- [x] **Generar passwords aleatorios** por defecto
- [x] **Mejorar .gitignore** para prevenir leaks
- [x] **Validar credenciales** antes de ejecutar
- [ ] **Implementar Sealed Secrets** para Kubernetes
- [ ] **Rotar credenciales** existentes comprometidas
- [ ] **Audit completo** del historial de Git

## 🚨 Acciones Urgentes Post-Corrección

### 1. Rotación de Credenciales
```bash
# TODO: Cambiar credenciales en todos los servicios desplegados
kubectl delete secret gitea-admin-credentials -n gitea
kubectl delete secret argocd-admin-credentials -n argocd
```

### 2. Historial de Git
```bash
# TODO: Verificar que la corrección elimina la exposición
git log --oneline -p | grep -i "gitops123"
```

### 3. Servicios Externos
- [ ] Verificar que `gitops123` no se use en otros sistemas
- [ ] Cambiar credenciales en servicios que las conocían
- [ ] Notificar a equipos sobre la rotación

## 💡 Mejores Prácticas Implementadas

1. **Nunca** credenciales en código fuente
2. **Siempre** usar variables de entorno
3. **Generar** passwords aleatorios largos
4. **Validar** presencia de credenciales antes de usar
5. **Encriptar** secrets para almacenamiento en Git (Sealed Secrets)
6. **Auditar** regularmente el código para credenciales
7. **Rotar** credenciales periódicamente