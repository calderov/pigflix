const express = require('express');
const cors = require('cors');
const fs = require('fs');
const path = require('path');
const moviesRouter = require('./routes/movies');
const adminRouter = require('./routes/admin');

const FRONTEND_BUILD_DIR = path.join(__dirname, '..', '..', 'frontend', 'build', 'web');

function createServer() {
  const app = express();
  app.use(cors());
  app.use(express.json());

  app.get('/api/health', (req, res) => res.json({ status: 'ok' }));
  app.use('/api/movies', moviesRouter);
  app.use('/api/admin', adminRouter);

  if (fs.existsSync(FRONTEND_BUILD_DIR)) {
    app.use(express.static(FRONTEND_BUILD_DIR));
  } else {
    console.warn(
      `[server] Frontend build not found at ${FRONTEND_BUILD_DIR}. Run "flutter build web" in frontend/ to serve it here.`
    );
  }

  return app;
}

module.exports = { createServer };
