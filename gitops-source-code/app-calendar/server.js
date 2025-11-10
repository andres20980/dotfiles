const express = require('express');
const app = express();
const PORT = process.env.PORT || 4000;

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', app: 'calendar', version: '1.0.0' });
});

// Get current date
app.get('/date', (req, res) => {
  const now = new Date();
  res.json({
    date: now.toISOString().split('T')[0],
    time: now.toTimeString().split(' ')[0],
    timestamp: now.getTime()
  });
});

// Root
app.get('/', (req, res) => {
  res.json({
    app: 'app-calendar',
    version: '2.1.2',  // TESTING BOOTSTRAP v3
    endpoints: ['/health', '/date'],
    commitTs: process.env.COMMIT_TS || null
  });
});

app.listen(PORT, () => {
  console.log(`Calendar app running on port ${PORT}`);
});
// commit: kaniko securityContext removed for permissions, CI 2025-11-09T12:10Z
// commit: manifests fresh dir fix 12:14Z
// commit: trigger workflow to validate update-manifests fresh dir strategy 12:24Z
