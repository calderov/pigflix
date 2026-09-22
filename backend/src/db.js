const fs = require('fs');
const Database = require('better-sqlite3');
const { DB_PATH, DATA_DIR } = require('./config');

fs.mkdirSync(DATA_DIR, { recursive: true });

const db = new Database(DB_PATH);
db.pragma('journal_mode = WAL');

db.exec(`
  CREATE TABLE IF NOT EXISTS movies (
    id TEXT PRIMARY KEY,
    filename TEXT NOT NULL,
    filepath TEXT NOT NULL UNIQUE,
    file_size INTEGER,
    title TEXT NOT NULL,
    year INTEGER,
    overview TEXT,
    tmdb_id INTEGER,
    genres TEXT,
    runtime INTEGER,
    rating REAL,
    poster_path TEXT,
    backdrop_path TEXT,
    metadata_status TEXT NOT NULL DEFAULT 'pending',
    transcode_status TEXT NOT NULL DEFAULT 'not_started',
    transcoded_path TEXT,
    added_at TEXT NOT NULL DEFAULT (datetime('now'))
  )
`);

// Lightweight migration for columns added after the initial release.
try {
  db.exec('ALTER TABLE movies ADD COLUMN transcode_progress REAL NOT NULL DEFAULT 0');
} catch (err) {
  if (!/duplicate column name/i.test(err.message)) throw err;
}

module.exports = db;
