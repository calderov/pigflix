const fs = require('fs');
const path = require('path');
const db = require('./db');
const tmdb = require('./tmdb');
const { METADATA_DIR } = require('./config');

async function fetchAndSaveMetadata(movie) {
  const movieMetaDir = path.join(METADATA_DIR, movie.id);

  try {
    // An explicit TMDb id (from the "id:<tmdb id>" retry syntax) skips the
    // title/year search and fetches that exact movie.
    let tmdbId = movie.tmdbId;
    if (!tmdbId) {
      const result = await tmdb.searchMovie(movie.title, movie.year);
      if (!result) {
        db.prepare(`UPDATE movies SET metadata_status = 'error' WHERE id = ?`).run(movie.id);
        console.warn(`[metadata] No TMDb match for "${movie.title}" (${movie.filename})`);
        return;
      }
      tmdbId = result.id;
    }

    const details = await tmdb.getMovieDetails(tmdbId);

    // Wipe any previously saved poster/backdrop/info.json now that a new
    // match was found, so a retried search (e.g. fixing a mislabeled movie)
    // doesn't leave stale art behind when the new match has less/no artwork.
    fs.rmSync(movieMetaDir, { recursive: true, force: true });
    fs.mkdirSync(movieMetaDir, { recursive: true });

    let posterRelPath = null;
    if (details.poster_path) {
      const dest = path.join(movieMetaDir, 'poster.jpg');
      if (await tmdb.downloadPoster(details.poster_path, dest)) {
        posterRelPath = path.relative(METADATA_DIR, dest);
      }
    }

    let backdropRelPath = null;
    if (details.backdrop_path) {
      const dest = path.join(movieMetaDir, 'backdrop.jpg');
      if (await tmdb.downloadBackdrop(details.backdrop_path, dest)) {
        backdropRelPath = path.relative(METADATA_DIR, dest);
      }
    }

    const genres = (details.genres || []).map((g) => g.name);

    fs.writeFileSync(
      path.join(movieMetaDir, 'info.json'),
      JSON.stringify(details, null, 2)
    );

    db.prepare(
      `UPDATE movies SET
        title = ?, year = ?, overview = ?, tmdb_id = ?, genres = ?, runtime = ?,
        rating = ?, poster_path = ?, backdrop_path = ?, metadata_status = 'ready'
       WHERE id = ?`
    ).run(
      details.title || movie.title,
      details.release_date ? parseInt(details.release_date.slice(0, 4), 10) : movie.year,
      details.overview || null,
      details.id,
      JSON.stringify(genres),
      details.runtime || null,
      details.vote_average || null,
      posterRelPath,
      backdropRelPath,
      movie.id
    );

    console.log(`[metadata] Registered "${details.title}" (${movie.filename})`);
  } catch (err) {
    db.prepare(`UPDATE movies SET metadata_status = 'error' WHERE id = ?`).run(movie.id);
    console.error(`[metadata] Failed for "${movie.filename}":`, err.message);
  }
}

module.exports = { fetchAndSaveMetadata };
