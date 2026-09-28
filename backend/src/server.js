const express = require('express');
const cors = require('cors');
const fs = require('fs');
const http = require('http');
const os = require('os');
const path = require('path');
const { WebSocketServer } = require('ws');
const moviesRouter = require('./routes/movies');
const adminRouter = require('./routes/admin');
const { attachRemoteRelay } = require('./remoteRelay');
const { PORT } = require('./config');

const FRONTEND_BUILD_DIR = path.join(__dirname, '..', '..', 'frontend', 'build', 'web');

// Interface name patterns that are never the LAN-facing adapter a phone on
// the same network would use to reach this server: container bridges, VPN
// tunnels, and virtual ethernet pairs. Skipping these matters because a
// machine can easily have one of these *and* a real LAN address active at
// once (e.g. Docker's docker0/br-* alongside eth0/wlan0), and — unlike the
// loopback/internal flag — `os.networkInterfaces()` has no way to tell them
// apart from a genuine adapter other than by name.
const VIRTUAL_INTERFACE_PATTERN =
  /^(docker|br-|veth|tailscale|wg|tun|utun|zt)/i;

// Best-effort address for other devices on the LAN to reach this server —
// used by the frontend's pairing dialog, since `localhost` (the frontend's
// own build-time default backend host) means nothing to a phone trying to
// pair with it. Picks the first non-internal IPv4 interface that doesn't
// look virtual; on a machine with several real candidates (e.g. Wi-Fi and
// Ethernet both up) this is still a guess, but far more useful than
// "localhost".
function getLanAddress() {
  const interfaces = os.networkInterfaces();
  for (const [name, addrs] of Object.entries(interfaces)) {
    if (VIRTUAL_INTERFACE_PATTERN.test(name)) continue;
    for (const addr of addrs || []) {
      if (addr.family === 'IPv4' && !addr.internal) return addr.address;
    }
  }
  return null;
}

function createServer() {
  const app = express();
  app.use(cors());
  app.use(express.json());

  app.get('/api/health', (req, res) => res.json({ status: 'ok' }));
  app.get('/api/config', (req, res) => {
    const lanIp = getLanAddress();
    res.json({ serverAddress: lanIp ? `${lanIp}:${PORT}` : null });
  });
  app.use('/api/movies', moviesRouter);
  app.use('/api/admin', adminRouter);

  if (fs.existsSync(FRONTEND_BUILD_DIR)) {
    app.use(express.static(FRONTEND_BUILD_DIR));
  } else {
    console.warn(
      `[server] Frontend build not found at ${FRONTEND_BUILD_DIR}. Run "flutter build web" in frontend/ to serve it here.`
    );
  }

  const server = http.createServer(app);
  const wss = new WebSocketServer({ server, path: '/ws' });
  attachRemoteRelay(wss);

  return { app, server };
}

module.exports = { createServer };
