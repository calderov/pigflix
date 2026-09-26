const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const db = require('./db');
const { MOVIES_DIR, METADATA_DIR, TRANSCODED_DIR, VIDEO_EXTENSIONS, ENCODE_LIBRARY } = require('./config');
const { parseTitleAndYear } = require('./titleParser');
const { fetchAndSaveMetadata } = require('./metadataService');
const { ensureTranscoded } = require('./transcodeManager');

function walk(dir) {
  let results = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      results = results.concat(walk(full));
    } else if (VIDEO_EXTENSIONS.includes(path.extname(entry.name).toLowerCase())) {
      results.push(full);
    }
  }
  return results;
}

function pruneMissingMovies(filesOnDisk) {
  const onDiskSet = new Set(filesOnDisk.map((f) => path.relative(MOVIES_DIR, f)));
  const existing = db.prepare('SELECT id, filepath FROM movies').all();

  for (const row of existing) {
    if (!onDiskSet.has(row.filepath)) {
      console.log(`[scan] Removing missing movie from library: ${row.filepath}`);
      db.prepare('DELETE FROM movies WHERE id = ?').run(row.id);
      fs.rm(path.join(METADATA_DIR, row.id), { recursive: true, force: true }, () => {});
      fs.rm(path.join(TRANSCODED_DIR, `${row.id}.mp4`), { force: true }, () => {});
    }
  }
}

async function scanAndRegister() {
  // MOVIES_DIR is guaranteed to already exist by this point.
  // index.js validates it at startup before this ever runs.
  const files = walk(MOVIES_DIR);

  pruneMissingMovies(files);

  const newMovies = [];
  for (const fullPath of files) {
    const filepath = path.relative(MOVIES_DIR, fullPath);
    const existing = db.prepare('SELECT id FROM movies WHERE filepath = ?').get(filepath);
    if (existing) continue;

    const filename = path.basename(fullPath);
    const { title, year } = parseTitleAndYear(filename);
    const stat = fs.statSync(fullPath);
    const id = crypto.randomUUID();

    db.prepare(
      `INSERT INTO movies (id, filename, filepath, file_size, title, year, metadata_status, transcode_status)
       VALUES (?, ?, ?, ?, ?, ?, 'pending', 'not_started')`
    ).run(id, filename, filepath, stat.size, title, year);

    console.log(`[scan] Found new movie: ${filename} -> "${title}" ${year || ''}`);
    newMovies.push({ id, filename, filepath, title, year });
  }

  if (newMovies.length === 0) {
    console.log('[scan] No new movies found.');
  } else {
    // Fetch metadata sequentially (be polite to the TMDb API) and kick off
    // transcoding for each in parallel (the transcode queue itself is serial).
    for (const movie of newMovies) {
      await fetchAndSaveMetadata(movie);
      if (ENCODE_LIBRARY) {
        ensureTranscoded(movie).catch(() => {}); // errors are logged/recorded by the manager
      }
    }
  }

  const { count } = db.prepare('SELECT COUNT(*) AS count FROM movies').get();
  console.log(`[scan] ${count} movie${count === 1 ? '' : 's'} in library.`);
}

module.exports = { scanAndRegister };
