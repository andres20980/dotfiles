const express = require('express');
const app = express();
const PORT = process.env.PORT || 3000;

app.get('/', (_req, res) => {
  res.send(`
  <html>
    <head>
      <meta charset="utf-8" />
      <title>Reloj</title>
      <style>
        html, body { height: 100%; margin: 0; }
        body { display:flex; align-items:center; justify-content:center; background:#0b1021; color:#fff; }
        .clock { font: 700 12vw/1.1 system-ui, -apple-system, Segoe UI, Roboto, Ubuntu, Cantarell, Noto Sans, Arial, sans-serif; letter-spacing: .05em; }
        .sub { font: 500 2vw/1 system-ui, sans-serif; color:#8aa0ff; text-align:center; margin-top:1rem; }
      </style>
    </head>
    <body>
      <div>
        <div class="clock" id="clock">--:--:--</div>
        <div class="sub">Hora local</div>
      </div>
      <script>
        function pad(n){return n<10?'0'+n:n}
        function tick(){
          const d = new Date();
          const t = pad(d.getHours())+':'+pad(d.getMinutes())+':'+pad(d.getSeconds());
          document.getElementById('clock').textContent = t;
        }
        setInterval(tick, 250); tick();
      </script>
    </body>
  </html>
  `);
});

app.get('/health', (_req, res) => res.json({ status: 'healthy' }));
app.get('/ready', (_req, res) => res.json({ status: 'ready' }));

app.listen(PORT, '0.0.0.0', () => console.log(`app-reloj on :${PORT}`));
