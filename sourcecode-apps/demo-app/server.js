const express = require('express');
const promClient = require('prom-client');
const winston = require('winston');

// ============================================================================
// LOGGING CONFIGURATION
// ============================================================================
const logger = winston.createLogger({
  level: process.env.LOG_LEVEL || 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.json()
  ),
  transports: [
    new winston.transports.Console({
      format: winston.format.combine(
        winston.format.colorize(),
        winston.format.simple()
      )
    })
  ]
});

// ============================================================================
// PROMETHEUS METRICS
// ============================================================================
const register = new promClient.Registry();

// Default metrics (CPU, memory, etc.)
promClient.collectDefaultMetrics({ register });

// Custom metrics
const httpRequestDuration = new promClient.Histogram({
  name: 'http_request_duration_milliseconds',
  help: 'Duration of HTTP requests in milliseconds',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [10, 50, 100, 200, 500, 1000, 2000, 5000]
});

const httpRequestTotal = new promClient.Counter({
  name: 'http_requests_total',
  help: 'Total number of HTTP requests',
  labelNames: ['method', 'route', 'status_code']
});

const httpRequestsInFlight = new promClient.Gauge({
  name: 'http_requests_in_flight',
  help: 'Number of HTTP requests currently being processed'
});

const appVersion = new promClient.Gauge({
  name: 'app_version_info',
  help: 'Application version information',
  labelNames: ['version', 'commit']
});

// Register custom metrics
register.registerMetric(httpRequestDuration);
register.registerMetric(httpRequestTotal);
register.registerMetric(httpRequestsInFlight);
register.registerMetric(appVersion);

// Set version info
appVersion.set(
  { 
    version: process.env.APP_VERSION || '1.0.0',
    commit: process.env.GIT_COMMIT || 'unknown'
  },
  1
);

// ============================================================================
// EXPRESS APP SETUP
// ============================================================================
const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Request logging middleware
app.use((req, res, next) => {
  const start = Date.now();
  
  httpRequestsInFlight.inc();
  
  res.on('finish', () => {
    const duration = Date.now() - start;
    
    httpRequestDuration.observe(
      {
        method: req.method,
        route: req.route?.path || req.path,
        status_code: res.statusCode
      },
      duration
    );
    
    httpRequestTotal.inc({
      method: req.method,
      route: req.route?.path || req.path,
      status_code: res.statusCode
    });
    
    httpRequestsInFlight.dec();
    
    logger.info({
      method: req.method,
      path: req.path,
      status: res.statusCode,
      duration: `${duration}ms`,
      userAgent: req.get('user-agent')
    });
  });
  
  next();
});

// ============================================================================
// ROUTES
// ============================================================================

// Root endpoint
app.get('/', (req, res) => {
  res.json({
    service: 'demo-app',
    version: process.env.APP_VERSION || '1.0.0',
    commit: process.env.GIT_COMMIT || 'unknown',
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    message: 'Demo app for GitOps workflows - Welcome! 🚀'
  });
});

// Health check endpoint (Kubernetes liveness/readiness probe)
app.get('/health', (req, res) => {
  const healthcheck = {
    status: 'healthy',
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    checks: {
      memory: checkMemory(),
      cpu: checkCpu()
    }
  };
  
  // Return 503 if any check fails
  const isHealthy = Object.values(healthcheck.checks).every(check => check.status === 'ok');
  
  if (isHealthy) {
    res.status(200).json(healthcheck);
  } else {
    res.status(503).json(healthcheck);
  }
});

// Readiness probe (specific to Kubernetes)
app.get('/ready', (req, res) => {
  // Check if app is ready to serve traffic
  // For this demo, we're always ready after startup
  res.status(200).json({
    status: 'ready',
    timestamp: new Date().toISOString()
  });
});

// Metrics endpoint (Prometheus scraping)
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

// API v1 endpoints
app.get('/api/v1/users', (req, res) => {
  // Simulate database query
  setTimeout(() => {
    res.json({
      users: [
        { id: 1, name: 'Alice', email: 'alice@example.com' },
        { id: 2, name: 'Bob', email: 'bob@example.com' },
        { id: 3, name: 'Charlie', email: 'charlie@example.com' }
      ],
      total: 3,
      page: 1
    });
  }, Math.random() * 100); // Simulate variable latency
});

app.get('/api/v1/users/:id', (req, res) => {
  const userId = parseInt(req.params.id);
  
  // Simulate random errors (5% error rate)
  if (Math.random() < 0.05) {
    logger.error({ message: 'Database error', userId });
    return res.status(500).json({ error: 'Internal server error' });
  }
  
  // Simulate not found
  if (userId > 10) {
    return res.status(404).json({ error: 'User not found' });
  }
  
  res.json({
    id: userId,
    name: `User ${userId}`,
    email: `user${userId}@example.com`,
    createdAt: new Date().toISOString()
  });
});

app.post('/api/v1/users', (req, res) => {
  const { name, email } = req.body;
  
  if (!name || !email) {
    return res.status(400).json({ error: 'Name and email are required' });
  }
  
  res.status(201).json({
    id: Math.floor(Math.random() * 1000),
    name,
    email,
    createdAt: new Date().toISOString()
  });
});

// Simulate a slow endpoint (for testing rollout analysis)
app.get('/api/v1/slow', (req, res) => {
  const delay = Math.random() * 3000; // 0-3 seconds
  setTimeout(() => {
    res.json({
      message: 'Slow endpoint response',
      delay: `${delay.toFixed(0)}ms`
    });
  }, delay);
});

// Error simulation endpoint (for testing monitoring)
app.get('/api/v1/error', (req, res) => {
  logger.error({ message: 'Simulated error endpoint triggered' });
  res.status(500).json({ error: 'Simulated server error' });
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({
    error: 'Not found',
    path: req.path,
    method: req.method
  });
});

// Error handler
app.use((err, req, res, next) => {
  logger.error({
    error: err.message,
    stack: err.stack,
    path: req.path,
    method: req.method
  });
  
  res.status(500).json({
    error: 'Internal server error',
    message: process.env.NODE_ENV === 'development' ? err.message : undefined
  });
});

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

function checkMemory() {
  const usage = process.memoryUsage();
  const limit = 512 * 1024 * 1024; // 512MB
  
  return {
    status: usage.heapUsed < limit ? 'ok' : 'warning',
    heapUsed: `${(usage.heapUsed / 1024 / 1024).toFixed(2)} MB`,
    heapTotal: `${(usage.heapTotal / 1024 / 1024).toFixed(2)} MB`,
    external: `${(usage.external / 1024 / 1024).toFixed(2)} MB`
  };
}

function checkCpu() {
  const usage = process.cpuUsage();
  
  return {
    status: 'ok',
    user: `${(usage.user / 1000).toFixed(2)} ms`,
    system: `${(usage.system / 1000).toFixed(2)} ms`
  };
}

// ============================================================================
// SERVER STARTUP
// ============================================================================

const server = app.listen(PORT, '0.0.0.0', () => {
  logger.info({
    message: '🚀 Demo app started',
    port: PORT,
    version: process.env.APP_VERSION || '1.0.0',
    commit: process.env.GIT_COMMIT || 'unknown',
    nodeVersion: process.version,
    env: process.env.NODE_ENV || 'production'
  });
});

// Graceful shutdown
process.on('SIGTERM', () => {
  logger.info('SIGTERM signal received: closing HTTP server');
  server.close(() => {
    logger.info('HTTP server closed');
    process.exit(0);
  });
});

process.on('SIGINT', () => {
  logger.info('SIGINT signal received: closing HTTP server');
  server.close(() => {
    logger.info('HTTP server closed');
    process.exit(0);
  });
});

module.exports = app;
