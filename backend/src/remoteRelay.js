const crypto = require('crypto');
const { PAIRING_CODE_TTL_MS, PAIRING_CODE_LENGTH } = require('./config');

// All state here is in-memory and per-process: pairing codes and the
// display/remote link are short-lived by nature (a single evening's remote
// session), so there's no need to persist them in SQLite alongside the
// movies table, and nothing here needs to survive a backend restart.
let displaySocket = null;
let remoteSocket = null;
let pendingCode = null; // { code, expiresAt }
let lastScreenState = null; // { screen, movieTitle }

function generatePairingCode() {
  const max = 10 ** PAIRING_CODE_LENGTH;
  const code = crypto.randomInt(0, max).toString().padStart(PAIRING_CODE_LENGTH, '0');
  return code;
}

function send(ws, message) {
  if (ws && ws.readyState === ws.OPEN) {
    ws.send(JSON.stringify(message));
  }
}

function unpairRemote(reason) {
  send(displaySocket, { type: 'unpaired', reason });
  remoteSocket = null;
}

function unpairDisplay(reason) {
  send(remoteSocket, { type: 'unpaired', reason });
  displaySocket = null;
  lastScreenState = null;
}

function handleDisplayMessage(ws, msg) {
  if (msg.type === 'request_pairing_code') {
    pendingCode = { code: generatePairingCode(), expiresAt: Date.now() + PAIRING_CODE_TTL_MS };
    send(ws, { type: 'pairing_code', code: pendingCode.code, expiresAt: pendingCode.expiresAt });
    return;
  }
  if (msg.type === 'screen') {
    lastScreenState = { screen: msg.screen, movieTitle: msg.movieTitle };
    send(remoteSocket, { type: 'screen', ...lastScreenState });
  }
}

function handleRemoteMessage(ws, msg) {
  if (msg.type === 'pair_attempt') {
    if (ws !== remoteSocket && remoteSocket) {
      send(ws, { type: 'pair_failure', reason: 'already_paired' });
      return;
    }
    if (!pendingCode) {
      send(ws, { type: 'pair_failure', reason: 'invalid_code' });
      return;
    }
    if (Date.now() > pendingCode.expiresAt) {
      pendingCode = null;
      send(ws, { type: 'pair_failure', reason: 'expired' });
      return;
    }
    if (msg.code !== pendingCode.code) {
      send(ws, { type: 'pair_failure', reason: 'invalid_code' });
      return;
    }

    remoteSocket = ws;
    pendingCode = null;
    send(ws, { type: 'pair_success' });
    if (lastScreenState) {
      send(ws, { type: 'screen', ...lastScreenState });
    }
    send(displaySocket, { type: 'pair_success' });
    return;
  }

  if (ws !== remoteSocket) return; // not (yet, or no longer) the paired remote

  if (msg.type === 'command') {
    send(displaySocket, { type: 'command', action: msg.action, deltaSeconds: msg.deltaSeconds });
  } else if (msg.type === 'search_query') {
    send(displaySocket, { type: 'search_query', query: msg.query });
  }
}

function attachRemoteRelay(wss) {
  wss.on('connection', (ws, req) => {
    const url = new URL(req.url, 'http://localhost');
    const role = url.searchParams.get('role');

    if (role === 'display') {
      if (displaySocket && displaySocket.readyState === displaySocket.OPEN) {
        ws.close(4001, 'A display is already connected');
        return;
      }
      displaySocket = ws;
      ws.on('close', () => {
        if (ws === displaySocket) {
          unpairDisplay('display_disconnected');
        }
      });
    } else if (role === 'remote') {
      ws.on('close', () => {
        if (ws === remoteSocket) {
          unpairRemote('remote_disconnected');
        }
      });
    } else {
      ws.close(4000, 'Missing or invalid role');
      return;
    }

    ws.on('message', (raw) => {
      let msg;
      try {
        msg = JSON.parse(raw);
      } catch (err) {
        console.warn('[remoteRelay] Ignoring malformed message:', raw.toString());
        return;
      }

      if (role === 'display') {
        handleDisplayMessage(ws, msg);
      } else {
        handleRemoteMessage(ws, msg);
      }
    });
  });
}

module.exports = { attachRemoteRelay };
