# Demo App - GitOps Ready Node.js Application

A production-ready Node.js Express application designed for GitOps workflows with Kubernetes.

## 🚀 Features

- ✅ **RESTful API** with Express.js
- ✅ **Prometheus metrics** (`/metrics` endpoint)
- ✅ **Health checks** (`/health`, `/ready`)
- ✅ **Structured logging** with Winston
- ✅ **Graceful shutdown** (SIGTERM/SIGINT handling)
- ✅ **Multi-stage Docker build** (optimized for size)
- ✅ **Non-root container** (security best practices)
- ✅ **Kubernetes manifests** included

## 📋 API Endpoints

### Core Endpoints
- `GET /` - Service information
- `GET /health` - Liveness probe (Kubernetes)
- `GET /ready` - Readiness probe (Kubernetes)
- `GET /metrics` - Prometheus metrics

### API v1
- `GET /api/v1/users` - List all users
- `GET /api/v1/users/:id` - Get user by ID
- `POST /api/v1/users` - Create new user
- `GET /api/v1/slow` - Slow endpoint (for testing)
- `GET /api/v1/error` - Error endpoint (for testing monitoring)

## 🏗️ Local Development

### Prerequisites
- Node.js >= 18.0.0
- npm or yarn

### Install dependencies
```bash
npm install
```

### Run development server
```bash
npm run dev
```

### Run tests
```bash
npm test
```

### Build Docker image
```bash
docker build -t demo-app:latest .
```

### Run container
```bash
docker run -p 3000:3000 \
  -e APP_VERSION=1.0.0 \
  -e GIT_COMMIT=$(git rev-parse --short HEAD) \
  demo-app:latest
```

## 📊 Prometheus Metrics

The app exposes the following custom metrics:

- `http_requests_total` - Total HTTP requests (counter)
- `http_request_duration_milliseconds` - Request duration (histogram)
- `http_requests_in_flight` - Requests currently being processed (gauge)
- `app_version_info` - Application version information (gauge)

Plus standard Node.js metrics:
- `process_cpu_seconds_total`
- `nodejs_heap_size_total_bytes`
- `nodejs_heap_size_used_bytes`
- etc.

## 🔒 Security Features

- Non-root user (UID 1001)
- Minimal Alpine base image
- Production-only dependencies
- Health checks configured
- Graceful shutdown handling
- dumb-init for proper signal forwarding

## 🎯 GitOps Integration

This app is designed to work with:

- **ArgoCD** - GitOps deployment
- **Argo Rollouts** - Progressive delivery (canary, blue-green)
- **Prometheus** - Metrics collection
- **Grafana** - Visualization
- **Kargo** - Multi-stage promotion

## 📦 Kubernetes Deployment

See `k8s/` directory for:
- `deployment.yaml` - Deployment configuration
- `service.yaml` - Service definition
- `rollout.yaml` - Argo Rollout (canary strategy)
- `servicemonitor.yaml` - Prometheus scraping

## 🧪 Testing the App

### Health check
```bash
curl http://localhost:3000/health
```

### Get metrics
```bash
curl http://localhost:3000/metrics
```

### Test API
```bash
# List users
curl http://localhost:3000/api/v1/users

# Get user by ID
curl http://localhost:3000/api/v1/users/1

# Create user
curl -X POST http://localhost:3000/api/v1/users \
  -H "Content-Type: application/json" \
  -d '{"name":"Alice","email":"alice@example.com"}'

# Test slow endpoint
curl http://localhost:3000/api/v1/slow

# Test error endpoint (for monitoring)
curl http://localhost:3000/api/v1/error
```

## 🔄 CI/CD Pipeline

The app is designed to work with Argo Workflows:

1. **Build** - Docker build with commit SHA tag
2. **Push** - Push to local registry (localhost:30087)
3. **Update manifests** - Automatically update image tag in Git
4. **Deploy** - ArgoCD detects changes and syncs
5. **Rollout** - Argo Rollouts performs canary deployment
6. **Monitor** - Prometheus collects metrics, Grafana visualizes

## 📝 Environment Variables

- `PORT` - Server port (default: 3000)
- `NODE_ENV` - Environment (default: production)
- `LOG_LEVEL` - Log level (default: info)
- `APP_VERSION` - Application version (for metrics)
- `GIT_COMMIT` - Git commit SHA (for traceability)

## 🏷️ Versioning

This app follows semantic versioning:
- `MAJOR.MINOR.PATCH`
- Images tagged with commit SHA for immutability

## 📄 License

MIT

## 👥 Authors

GitOps Team
