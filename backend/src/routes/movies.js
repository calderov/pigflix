const express = require('express');
const fs = require('fs');
const path = require('path');
const { isUtf8 } = require('buffer');
const db = require('../db');
const { METADATA_DIR, MOVIES_DIR, ENCODE_LIBRARY } = require('../config');
const { ensureTranscoded } = require('../transcodeManager');
const { serveFileWithRange } = require('../serveRange');
const { fetchAndSaveMetadata } = require('../metadataService');

const router = express.Router();

const CONTENT_TYPES = {
  '.mp4': 'video/mp4',
  '.m4v': 'video/x-m4v',
  '.mkv': 'video/x-matroska',
  '.avi': 'video/x-msvideo',
  '.mov': 'video/quicktime',
  '.wmv': 'video/x-ms-wmv',
};

// Subtitles are matched by convention: one or more .srt files living next to
// the movie file with the same base name, optionally followed by a language
// code (e.g. "Movie.mkv" pairs with "Movie.srt", or with "Movie.en.srt" and
// "Movie.spa.srt" for multiple languages). Checked on disk on demand rather
// than tracked in the DB, so dropping a .srt in later doesn't require a
// rescan. The no-language-code file (if any) sorts first, so it's the
// default track.
function findSubtitleFiles(filepath) {
  const { dir, name } = path.parse(path.join(MOVIES_DIR, filepath));

  let entries;
  try {
    entries = fs.readdirSync(dir);
  } catch {
    return [];
  }

  const prefix = `${name}.`;
  const tracks = [];
  for (const entry of entries) {
    if (path.extname(entry).toLowerCase() !== '.srt') continue;
    const base = entry.slice(0, entry.length - path.extname(entry).length);
    if (base === name) {
      tracks.push({ lang: null, path: path.join(dir, entry) });
    } else if (base.startsWith(prefix)) {
      tracks.push({ lang: base.slice(prefix.length), path: path.join(dir, entry) });
    }
  }

  tracks.sort((a, b) => {
    if (a.lang === b.lang) return 0;
    if (a.lang === null) return -1;
    if (b.lang === null) return 1;
    return a.lang.localeCompare(b.lang);
  });

  return tracks;
}

// Many .srt files (especially older non-English ones) are saved as
// ISO-8859-1/Windows-1252 rather than UTF-8, which would otherwise come out
// as mangled accented characters. Falls back to 'latin1' decoding when the
// bytes aren't valid UTF-8, which correctly recovers common Western
// European accents even though it isn't a byte-perfect Windows-1252 decode.
function readSubtitleAsUtf8(filePath) {
  const buf = fs.readFileSync(filePath);
  const text = isUtf8(buf) ? buf.toString('utf8') : buf.toString('latin1');
  return text.replace(/^\uFEFF/, ''); // strip a UTF-8 BOM if present
}

function toPublicMovie(row) {
  // With encoding disabled, files are served as-is with no processing step,
  // so there's nothing to wait on: report streaming as always ready.
  const transcodeStatus = ENCODE_LIBRARY ? row.transcode_status : 'done';
  const transcodeProgress = ENCODE_LIBRARY ? row.transcode_progress : 100;

  return {
    id: row.id,
    title: row.title,
    year: row.year,
    overview: row.overview,
    genres: row.genres ? JSON.parse(row.genres) : [],
    runtime: row.runtime,
    rating: row.rating,
    metadataStatus: row.metadata_status,
    transcodeStatus,
    transcodeProgress,
    posterUrl: row.poster_path ? `/api/movies/${row.id}/poster` : null,
    backdropUrl: row.backdrop_path ? `/api/movies/${row.id}/backdrop` : null,
    streamUrl: `/api/movies/${row.id}/stream`,
    subtitles: findSubtitleFiles(row.filepath).map((t) => ({
      lang: t.lang,
      url: `/api/movies/${row.id}/subtitle${t.lang ? `?lang=${encodeURIComponent(t.lang)}` : ''}`,
    })),
  };
}

router.get('/', (req, res) => {
  const q = (req.query.q || '').trim();
  const rows = q
    ? db.prepare('SELECT * FROM movies WHERE title LIKE ? ORDER BY title').all(`%${q}%`)
    : db.prepare('SELECT * FROM movies ORDER BY title').all();
  res.json(rows.map(toPublicMovie));
});

router.get('/:id', (req, res) => {
  const row = db.prepare('SELECT * FROM movies WHERE id = ?').get(req.params.id);
  if (!row) return res.status(404).json({ error: 'Movie not found' });
  res.json(toPublicMovie(row));
});

// Re-runs the TMDb search with a user-supplied title/year, for movies that
// were never matched (grey placeholder cover) or were matched to the wrong
// film. Overwrites any previously saved metadata/art for this movie.
// The title field also accepts "id:<tmdb id>" to fetch an exact TMDb movie
// directly instead of searching by name (year is ignored in that case).
router.post('/:id/retry-metadata', async (req, res) => {
  const row = db.prepare('SELECT * FROM movies WHERE id = ?').get(req.params.id);
  if (!row) return res.status(404).json({ error: 'Movie not found' });

  const rawTitle = typeof req.body?.title === 'string' ? req.body.title.trim() : '';
  if (!rawTitle) return res.status(400).json({ error: 'Title is required' });

  const idMatch = /^id:\s*(.*)$/i.exec(rawTitle);
  if (idMatch) {
    const tmdbId = parseInt(idMatch[1].trim(), 10);
    if (Number.isNaN(tmdbId)) {
      return res.status(400).json({ error: 'Invalid TMDb id — expected e.g. "id:550"' });
    }
    await fetchAndSaveMetadata({ id: row.id, filename: row.filename, tmdbId, title: row.title, year: row.year });
  } else {
    let year = null;
    const yearRaw = req.body?.year;
    if (yearRaw !== undefined && yearRaw !== null && String(yearRaw).trim() !== '') {
      year = parseInt(yearRaw, 10);
      if (Number.isNaN(year)) return res.status(400).json({ error: 'Year must be a number' });
    }
    await fetchAndSaveMetadata({ id: row.id, filename: row.filename, title: rawTitle, year });
  }

  const fresh = db.prepare('SELECT * FROM movies WHERE id = ?').get(req.params.id);
  res.json(toPublicMovie(fresh));
});

router.get('/:id/poster', (req, res) => {
  const row = db.prepare('SELECT poster_path FROM movies WHERE id = ?').get(req.params.id);
  if (!row || !row.poster_path) return res.status(404).end();
  const fullPath = path.join(METADATA_DIR, row.poster_path);
  if (!fs.existsSync(fullPath)) return res.status(404).end();
  res.sendFile(fullPath);
});

router.get('/:id/backdrop', (req, res) => {
  const row = db.prepare('SELECT backdrop_path FROM movies WHERE id = ?').get(req.params.id);
  if (!row || !row.backdrop_path) return res.status(404).end();
  const fullPath = path.join(METADATA_DIR, row.backdrop_path);
  if (!fs.existsSync(fullPath)) return res.status(404).end();
  res.sendFile(fullPath);
});

// ?lang=<code> selects a specific track; omitted picks the default (the
// no-language-code file if present, else the alphabetically-first language).
router.get('/:id/subtitle', (req, res) => {
  const row = db.prepare('SELECT filepath FROM movies WHERE id = ?').get(req.params.id);
  if (!row) return res.status(404).json({ error: 'Movie not found' });

  const tracks = findSubtitleFiles(row.filepath);
  if (tracks.length === 0) return res.status(404).json({ error: 'No subtitle file for this movie' });

  const lang = typeof req.query.lang === 'string' ? req.query.lang : null;
  const track = lang
    ? tracks.find((t) => t.lang && t.lang.toLowerCase() === lang.toLowerCase())
    : tracks[0];
  if (!track) return res.status(404).json({ error: 'No subtitle track for that language' });

  res.type('text/plain; charset=utf-8').send(readSubtitleAsUtf8(track.path));
});

// Kicks off transcoding if needed (without blocking) and reports current
// progress, so the frontend can show a "preparing video" state instead of
// hanging on a slow-to-respond /stream request.
router.get('/:id/status', (req, res) => {
  const row = db.prepare('SELECT * FROM movies WHERE id = ?').get(req.params.id);
  if (!row) return res.status(404).json({ error: 'Movie not found' });

  if (ENCODE_LIBRARY && (row.transcode_status === 'not_started' || row.transcode_status === 'error')) {
    ensureTranscoded(row).catch(() => {}); // errors are recorded on the row itself
  }

  const fresh = db.prepare('SELECT * FROM movies WHERE id = ?').get(req.params.id);
  res.json(toPublicMovie(fresh));
});

router.get('/:id/stream', async (req, res) => {
  const row = db.prepare('SELECT * FROM movies WHERE id = ?').get(req.params.id);
  if (!row) return res.status(404).json({ error: 'Movie not found' });

  if (!ENCODE_LIBRARY) {
    const filePath = path.join(MOVIES_DIR, row.filepath);
    if (!fs.existsSync(filePath)) return res.status(404).json({ error: 'File not found' });
    const contentType = CONTENT_TYPES[path.extname(filePath).toLowerCase()] || 'application/octet-stream';
    return serveFileWithRange(req, res, filePath, contentType);
  }

  try {
    const filePath = await ensureTranscoded(row);
    serveFileWithRange(req, res, filePath, 'video/mp4');
  } catch (err) {
    console.error(`[stream] Failed to serve "${row.filename}":`, err.message);
    res.status(500).json({ error: 'Transcoding failed' });
  }
});

module.exports = router;
