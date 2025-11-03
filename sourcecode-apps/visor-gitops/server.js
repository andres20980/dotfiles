const express = require('express');
const app = express();
const PORT = process.env.PORT || 3000;

// simple static landing showing version/commit/links
app.get('/', (req, res) => {
  const version = process.env.APP_VERSION || 'dev';
  const commit = process.env.GIT_COMMIT || 'unknown';
  const image = process.env.IMAGE || 'docker-registry.registry.svc.cluster.local:5000/visor-gitops:latest';
  const tools = {
    argocd: process.env.ARGOCD_URL || 'http://localhost:30080',
    workflows: process.env.WORKFLOWS_URL || 'http://localhost:30091',
    registry: process.env.REGISTRY_UI_URL || 'http://localhost:30096',
    kargo: process.env.KARGO_URL || 'http://localhost:30085'
  };
  res.send(`
    <html>
      <head>
        <meta charset="utf-8" />
        <title>Visor GitOps</title>
        <style>
          body { font-family: system-ui, sans-serif; margin: 2rem; color: #222; }
          h1 { font-size: 2.2rem; margin-bottom: .5rem; }
          .meta { margin: .5rem 0 1.5rem; color: #555; }
          .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 1rem; }
          .card { border: 1px solid #ddd; border-radius: 8px; padding: 1rem; }
          a { color: #0a66c2; text-decoration: none; }
          a:hover { text-decoration: underline; }
          code { background: #f6f8fa; padding: .2rem .4rem; border-radius: 4px; }
        </style>
      </head>
      <body>
        <h1>Visor GitOps</h1>
        <div class="meta">
          <div>Versión: <code>${version}</code></div>
          <div>Commit: <code>${commit}</code></div>
          <div>Imagen: <code>${image}</code></div>
        </div>
        <div class="grid">
          <div class="card"><strong>Argo CD</strong><br/><a href="${tools.argocd}" target="_blank">${tools.argocd}</a></div>
          <div class="card"><strong>Argo Workflows</strong><br/><a href="${tools.workflows}" target="_blank">${tools.workflows}</a></div>
          <div class="card"><strong>Registry UI</strong><br/><a href="${tools.registry}" target="_blank">${tools.registry}</a></div>
          <div class="card"><strong>Kargo</strong><br/><a href="${tools.kargo}" target="_blank">${tools.kargo}</a></div>
        </div>
      </body>
    </html>
  `);
});

app.get('/health', (req, res) => res.json({ status: 'healthy' }));
app.get('/ready', (req, res) => res.json({ status: 'ready' }));

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Visor GitOps listening on http://0.0.0.0:${PORT}`);
});
