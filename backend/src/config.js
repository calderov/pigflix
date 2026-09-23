const path = require('path');
const crypto = require('crypto');
require('dotenv').config();

const ROOT = path.join(__dirname, '..');

const adminPassword = process.env.ADMIN_PASSWORD || '';

module.exports = {
  PORT: parseInt(process.env.PORT, 10) || 4000,
  TMDB_API_KEY: process.env.TMDB_API_KEY || '',
  // Only the hash is kept around (and the only thing ever compared against
  // — the frontend hashes the password client-side too, so the plaintext
  // never goes over the wire).
  ADMIN_PASSWORD_HASH: adminPassword
    ? crypto.createHash('sha256').update(adminPassword, 'utf8').digest('hex')
    : '',
  MOVIES_DIR: path.join(ROOT, 'movies'),
  METADATA_DIR: path.join(ROOT, 'metadata'),
  TRANSCODED_DIR: path.join(ROOT, 'transcoded'),
  DATA_DIR: path.join(ROOT, 'data'),
  DB_PATH: path.join(ROOT, 'data', 'pigflix.db'),
  VIDEO_EXTENSIONS: ['.mp4', '.mkv', '.avi', '.mov', '.m4v', '.wmv'],
  // When false, skip remuxing/transcoding entirely and stream source files
  // as-is. Anything other than the literal string 'false' is treated as
  // enabled, so it's on by default.
  ENCODE_LIBRARY: (process.env.ENCODE_LIBRARY || 'true').trim().toLowerCase() !== 'false',
  PAIRING_CODE_TTL_MINUTES: parseInt(process.env.PAIRING_CODE_TTL_MINUTES, 10) || 5,
  PAIRING_CODE_LENGTH: parseInt(process.env.PAIRING_CODE_LENGTH, 10) || 6,
  // How long a paired remote's session stays resumable after its connection
  // drops (e.g. the phone's screen turning off suspends its socket) before
  // the pairing is torn down and a fresh pairing code is required. Default:
  // 10 minutes — long enough to survive a phone screen timeout mid-movie.
  SESSION_RESUME_TTL_MINUTES: parseInt(process.env.SESSION_RESUME_TTL_MINUTES, 10) || 180,
};
