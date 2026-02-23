const http = require('http');
const port = process.env.PORT || 8080;
const version = process.env.APP_VERSION || '1.0.0';

http.createServer((req, res) => {
  const now = new Date();
  const hora = now.toLocaleTimeString('es-ES', { timeZone: 'Europe/Madrid' });
  const fecha = now.toLocaleDateString('es-ES', { timeZone: 'Europe/Madrid' });

  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', version, uptime: process.uptime() }));
    return;
  }

  if (req.url === '/api/time') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ hora, fecha, timestamp: now.toISOString(), version }));
    return;
  }

  // Página principal con reloj visual
  res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
  res.end(`<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <title>App Reloj - GitOps Lab</title>
  <style>
    body { background: #1a1a2e; color: #e0e0e0; font-family: 'Segoe UI', sans-serif;
           display: flex; flex-direction: column; align-items: center; justify-content: center;
           min-height: 100vh; margin: 0; }
    .clock { font-size: 5rem; font-weight: 300; color: #00d4ff; text-shadow: 0 0 20px #00d4ff40; }
    .date { font-size: 1.4rem; color: #888; margin-top: 0.5rem; }
    .badge { margin-top: 2rem; padding: 0.4rem 1rem; border-radius: 1rem;
             background: #16213e; color: #00d4ff; font-size: 0.85rem; }
    .footer { position: fixed; bottom: 1rem; color: #555; font-size: 0.8rem; }
  </style>
</head>
<body>
  <div class="clock" id="clock">${hora}</div>
  <div class="date" id="date">${fecha}</div>
  <div class="badge">v${version} · GitOps Lab</div>
  <div class="footer">Desplegado con ArgoCD · Fuente: Gitea</div>
  <script>
    setInterval(() => {
      const n = new Date();
      document.getElementById('clock').textContent =
        n.toLocaleTimeString('es-ES', { timeZone: 'Europe/Madrid' });
      document.getElementById('date').textContent =
        n.toLocaleDateString('es-ES', { timeZone: 'Europe/Madrid' });
    }, 1000);
  </script>
</body>
</html>`);
}).listen(port, () => {
  console.log(`app-reloj v${version} running on port ${port}`);
});
