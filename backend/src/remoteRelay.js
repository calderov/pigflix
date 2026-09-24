const crypto = require('crypto');
const { PAIRING_CODE_TTL_MINUTES, PAIRING_CODE_LENGTH, SESSION_RESUME_TTL_MINUTES } = require('./config');

// All state here is in-memory and per-process: pairing codes and the
// display/remote link are short-lived by nature (a single evening's remote
// session), so there's no need to persist them in SQLite alongside the
// movies table, and nothing here needs to survive a backend restart.
let displaySocket = null;
let remoteSocket = null;
let pendingCode = null; // { code, expiresAt }
let lastScreenState = null; // { screen, movieTitle }
let lastPlaybackState = null; // { isPlaying }

// Lets a remote reconnect (e.g. after a phone's screen-off suspends its
// socket) without walking through the pairing-code flow again. Set once a
// remote successfully pairs; stays valid — even while `remoteSocket` is
// briefly null between the old connection dropping and a new one resuming
// it — until either it's used to resume, `sessionResumeTimer` fires, or the
// display itself disconnects.
let sessionToken = null;
let sessionResumeTimer = null;

function generatePairingCode() {
  const max = 10 ** PAIRING_CODE_LENGTH;
  return crypto.randomInt(0, max).toString().padStart(PAIRING_CODE_LENGTH, '0');
}

function send(ws, message) {
  if (ws && ws.readyState === ws.OPEN) {
    ws.send(JSON.stringify(message));
  }
}

function clearSession() {
  clearTimeout(sessionResumeTimer);
  sessionResumeTimer = null;
  sessionToken = null;
}

// Called when the remote's socket closes. Doesn't tear down the session
// immediately — just stops routing to the dead socket and starts a grace
// window during which a `resume_session` with the matching token can
// silently reattach a new socket. Only once that window elapses without a
// resume does the pairing actually end (and the display get told).
function handleRemoteDisconnect() {
  remoteSocket = null;
  clearTimeout(sessionResumeTimer);
  sessionResumeTimer = setTimeout(() => {
    clearSession();
    send(displaySocket, { type: 'unpaired', reason: 'remote_disconnected' });
  }, SESSION_RESUME_TTL_MINUTES * 60 * 1000);
}

function unpairDisplay() {
  send(remoteSocket, { type: 'unpaired', reason: 'display_disconnected' });
  displaySocket = null;
  lastScreenState = null;
  remoteSocket = null;
  clearSession();
}

function handleDisplayMessage(ws, msg) {
  if (msg.type === 'request_pairing_code') {
    pendingCode = { code: generatePairingCode(), expiresAt: Date.now() + PAIRING_CODE_TTL_MINUTES * 60 * 1000 };
    send(ws, { type: 'pairing_code', code: pendingCode.code, expiresAt: pendingCode.expiresAt });
    return;
  }
  if (msg.type === 'screen') {
    lastScreenState = {
      screen: msg.screen,
      movieTitle: msg.movieTitle,
      backdropUrl: msg.backdropUrl,
      posterUrl: msg.posterUrl,
      year: msg.year,
      runtimeMinutes: msg.runtimeMinutes,
      rating: msg.rating,
      genres: msg.genres,
      overview: msg.overview,
      searchQuery: msg.searchQuery,
      subtitles: msg.subtitles,
      activeSubtitleLang: msg.activeSubtitleLang,
    };
    // Stale outside the player screen — cleared so a remote that (re)pairs
    // after the user's navigated away doesn't get handed a leftover
    // play/pause state for a screen that has no playback controls anyway.
    if (msg.screen !== 'player') lastPlaybackState = null;
    send(remoteSocket, { type: 'screen', ...lastScreenState });
    return;
  }
  if (msg.type === 'playback_state') {
    lastPlaybackState = { isPlaying: msg.isPlaying };
    send(remoteSocket, { type: 'playback_state', ...lastPlaybackState });
  }
}

function handleRemoteMessage(ws, msg) {
  if (msg.type === 'resume_session') {
    if (!sessionToken || msg.token !== sessionToken || !displaySocket) {
      send(ws, { type: 'resume_failure', reason: 'session_ended' });
      return;
    }
    clearTimeout(sessionResumeTimer);
    sessionResumeTimer = null;
    remoteSocket = ws;
    send(ws, { type: 'resume_success' });
    if (lastScreenState) {
      send(ws, { type: 'screen', ...lastScreenState });
    }
    if (lastPlaybackState) {
      send(ws, { type: 'playback_state', ...lastPlaybackState });
    }
    return;
  }

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

    clearTimeout(sessionResumeTimer);
    sessionResumeTimer = null;
    remoteSocket = ws;
    pendingCode = null;
    sessionToken = crypto.randomBytes(16).toString('hex');
    send(ws, { type: 'pair_success', sessionToken });
    if (lastScreenState) {
      send(ws, { type: 'screen', ...lastScreenState });
    }
    if (lastPlaybackState) {
      send(ws, { type: 'playback_state', ...lastPlaybackState });
    }
    send(displaySocket, { type: 'pair_success' });
    return;
  }

  if (ws !== remoteSocket) return; // not (yet, or no longer) the paired remote

  if (msg.type === 'command') {
    send(displaySocket, { type: 'command', action: msg.action, deltaSeconds: msg.deltaSeconds, lang: msg.lang });
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
          unpairDisplay();
        }
      });
    } else if (role === 'remote') {
      ws.on('close', () => {
        if (ws === remoteSocket) {
          handleRemoteDisconnect();
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
