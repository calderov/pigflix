const crypto = require('crypto');
const express = require('express');
const { ADMIN_PASSWORD_HASH } = require('../config');

const router = express.Router();

// Purely a UI gate for the frontend's admin mode (e.g. showing the "Fix
// match" button) — it does not restrict any other endpoint. The frontend
// sends a SHA-256 hash of the password rather than the password itself, so
// it never appears in plaintext on the wire.
router.post('/login', (req, res) => {
  if (!ADMIN_PASSWORD_HASH) {
    return res.status(500).json({
      error: 'Admin password not configured. Set ADMIN_PASSWORD in backend/.env.',
    });
  }

  const passwordHash = typeof req.body?.passwordHash === 'string' ? req.body.passwordHash : '';
  const provided = Buffer.from(passwordHash, 'hex');
  const expected = Buffer.from(ADMIN_PASSWORD_HASH, 'hex');
  const match = provided.length === expected.length && crypto.timingSafeEqual(provided, expected);

  if (!match) {
    return res.status(401).json({ error: 'Incorrect password' });
  }

  res.json({ ok: true });
});

module.exports = router;
