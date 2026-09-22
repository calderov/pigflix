const path = require('path');

/**
 * Turns a ripped DVD filename into a search-friendly title + year.
 * "The.Matrix.1999.DVDRip.mkv" -> { title: "The Matrix", year: 1999 }
 * "Amelie (2001).mp4"          -> { title: "Amelie", year: 2001 }
 */
function parseTitleAndYear(filename) {
  const base = path.parse(filename).name;
  let cleaned = base.replace(/[._]/g, ' ');

  let year = null;
  const yearMatch = cleaned.match(/\b(19\d{2}|20\d{2})\b/);
  if (yearMatch) {
    year = parseInt(yearMatch[1], 10);
    cleaned = cleaned.slice(0, yearMatch.index);
  }

  cleaned = cleaned
    .replace(/[[\](){}]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();

  return { title: cleaned || base, year };
}

module.exports = { parseTitleAndYear };
