const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');
const db = require('./db');
const { TRANSCODED_DIR, MOVIES_DIR } = require('./config');
const { probeMedia, isBrowserCompatible } = require('./ffprobe');

const inFlight = new Map(); // movie id -> Promise
let queue = Promise.resolve(); // serializes ffmpeg jobs so only one runs at a time

function parseOutTimeSeconds(chunk) {
  // ffmpeg -progress output includes lines like "out_time_us=12345678"
  const match = /out_time_us=(\d+)/.exec(chunk);
  if (!match) return null;
  return parseInt(match[1], 10) / 1_000_000;
}

function runFfmpeg(inputPath, outputPath, { copyStreams, durationSec, onProgress }) {
  return new Promise((resolve, reject) => {
    fs.mkdirSync(path.dirname(outputPath), { recursive: true });
    const tmpOutput = `${outputPath}.tmp.mp4`;

    const codecArgs = copyStreams
      ? ['-c:v', 'copy', '-c:a', 'copy']
      : ['-c:v', 'libx264', '-preset', 'veryfast', '-crf', '20', '-c:a', 'aac', '-b:a', '192k'];

    const args = [
      '-y',
      '-i', inputPath,
      '-map', '0:v:0',
      '-map', '0:a:0?',
      ...codecArgs,
      '-movflags', '+faststart',
      '-progress', 'pipe:1',
      '-nostats',
      tmpOutput,
    ];

    const proc = spawn('ffmpeg', args);
    let stderr = '';
    let buffer = '';

    proc.stdout.on('data', (chunk) => {
      buffer += chunk.toString();
      const seconds = parseOutTimeSeconds(buffer);
      if (seconds !== null && durationSec > 0 && onProgress) {
        onProgress(Math.min(99, (seconds / durationSec) * 100));
      }
      // Keep the buffer from growing unbounded; we only need the latest line.
      if (buffer.length > 4096) buffer = buffer.slice(-1024);
    });
    proc.stderr.on('data', (chunk) => {
      stderr += chunk.toString();
    });
    proc.on('error', reject);
    proc.on('close', (code) => {
      if (code === 0) {
        fs.renameSync(tmpOutput, outputPath);
        resolve();
      } else {
        fs.rm(tmpOutput, { force: true }, () => {});
        reject(new Error(`ffmpeg exited with code ${code}: ${stderr.slice(-1000)}`));
      }
    });
  });
}

function enqueueTranscode(movie) {
  const outputPath = path.join(TRANSCODED_DIR, `${movie.id}.mp4`);
  const inputPath = path.join(MOVIES_DIR, movie.filepath);

  const job = queue.then(async () => {
    db.prepare(
      `UPDATE movies SET transcode_status = 'processing', transcode_progress = 0 WHERE id = ?`
    ).run(movie.id);

    let info;
    try {
      info = probeMedia(inputPath);
    } catch (err) {
      db.prepare(`UPDATE movies SET transcode_status = 'error' WHERE id = ?`).run(movie.id);
      console.error(`[transcode] Probe failed for "${movie.filename}":`, err.message);
      throw err;
    }

    const copyStreams = isBrowserCompatible(info);
    console.log(
      `[transcode] Starting "${movie.filename}" (${info.videoCodec}/${info.audioCodec} -> ${
        copyStreams ? 'remux (stream copy)' : 're-encode'
      })`
    );

    let lastWrite = 0;
    const onProgress = (percent) => {
      const now = Date.now();
      if (now - lastWrite < 1000) return; // throttle DB writes to ~1/sec
      lastWrite = now;
      db.prepare(`UPDATE movies SET transcode_progress = ? WHERE id = ?`).run(percent, movie.id);
    };

    try {
      await runFfmpeg(inputPath, outputPath, { copyStreams, durationSec: info.durationSec, onProgress });
      db.prepare(
        `UPDATE movies SET transcode_status = 'done', transcode_progress = 100, transcoded_path = ? WHERE id = ?`
      ).run(path.relative(TRANSCODED_DIR, outputPath), movie.id);
      console.log(`[transcode] Finished "${movie.filename}"`);
    } catch (err) {
      db.prepare(`UPDATE movies SET transcode_status = 'error' WHERE id = ?`).run(movie.id);
      console.error(`[transcode] Failed "${movie.filename}":`, err.message);
      throw err;
    }
  });

  // Keep the queue alive even if this job fails.
  queue = job.catch(() => {});
  return job;
}

/**
 * Ensures movie.id has a cached playable MP4, transcoding (or fast-remuxing)
 * on demand if needed. Concurrent calls for the same movie share one
 * in-flight job.
 */
function ensureTranscoded(movie) {
  if (movie.transcode_status === 'done' && movie.transcoded_path) {
    const fullPath = path.join(TRANSCODED_DIR, movie.transcoded_path);
    if (fs.existsSync(fullPath)) return Promise.resolve(fullPath);
  }

  if (inFlight.has(movie.id)) return inFlight.get(movie.id);

  const promise = enqueueTranscode(movie)
    .then(() => path.join(TRANSCODED_DIR, `${movie.id}.mp4`))
    .finally(() => inFlight.delete(movie.id));

  inFlight.set(movie.id, promise);
  return promise;
}

module.exports = { ensureTranscoded };
