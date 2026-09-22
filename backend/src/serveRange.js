const fs = require('fs');

function serveFileWithRange(req, res, filePath, contentType) {
  const stat = fs.statSync(filePath);
  const fileSize = stat.size;
  const range = req.headers.range;

  res.setHeader('Accept-Ranges', 'bytes');
  res.setHeader('Content-Type', contentType);

  if (!range) {
    res.setHeader('Content-Length', fileSize);
    res.status(200);
    fs.createReadStream(filePath).pipe(res);
    return;
  }

  const match = /bytes=(\d*)-(\d*)/.exec(range);
  const start = match[1] ? parseInt(match[1], 10) : 0;
  const end = match[2] ? parseInt(match[2], 10) : fileSize - 1;

  if (Number.isNaN(start) || Number.isNaN(end) || start > end || start >= fileSize) {
    res.status(416).setHeader('Content-Range', `bytes */${fileSize}`).end();
    return;
  }

  const clampedEnd = Math.min(end, fileSize - 1);
  const chunkSize = clampedEnd - start + 1;

  res.status(206);
  res.setHeader('Content-Range', `bytes ${start}-${clampedEnd}/${fileSize}`);
  res.setHeader('Content-Length', chunkSize);
  fs.createReadStream(filePath, { start, end: clampedEnd }).pipe(res);
}

module.exports = { serveFileWithRange };
