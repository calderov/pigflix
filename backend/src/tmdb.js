const fs = require('fs');
const path = require('path');
const { pipeline } = require('stream/promises');
const { Readable } = require('stream');
const { TMDB_API_KEY } = require('./config');

const TMDB_BASE = 'https://api.themoviedb.org/3';
const POSTER_BASE = 'https://image.tmdb.org/t/p/w500';
const BACKDROP_BASE = 'https://image.tmdb.org/t/p/w1280';

function assertApiKey() {
  if (!TMDB_API_KEY) {
    throw new Error('TMDB_API_KEY is not set. Copy .env.example to .env and add your key.');
  }
}

async function searchMovie(title, year) {
  assertApiKey();
  const url = new URL(`${TMDB_BASE}/search/movie`);
  url.searchParams.set('api_key', TMDB_API_KEY);
  url.searchParams.set('query', title);
  if (year) url.searchParams.set('year', String(year));

  const res = await fetch(url);
  if (!res.ok) throw new Error(`TMDb search failed (${res.status}): ${await res.text()}`);
  const data = await res.json();
  return data.results && data.results.length > 0 ? data.results[0] : null;
}

async function getMovieDetails(tmdbId) {
  assertApiKey();
  const url = new URL(`${TMDB_BASE}/movie/${tmdbId}`);
  url.searchParams.set('api_key', TMDB_API_KEY);
  const res = await fetch(url);
  if (!res.ok) throw new Error(`TMDb details failed (${res.status}): ${await res.text()}`);
  return res.json();
}

async function downloadImage(tmdbImagePath, base, destPath) {
  if (!tmdbImagePath) return false;
  const res = await fetch(base + tmdbImagePath);
  if (!res.ok || !res.body) return false;
  fs.mkdirSync(path.dirname(destPath), { recursive: true });
  await pipeline(Readable.fromWeb(res.body), fs.createWriteStream(destPath));
  return true;
}

module.exports = {
  searchMovie,
  getMovieDetails,
  downloadPoster: (imagePath, dest) => downloadImage(imagePath, POSTER_BASE, dest),
  downloadBackdrop: (imagePath, dest) => downloadImage(imagePath, BACKDROP_BASE, dest),
};
