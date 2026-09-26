const fs = require('fs');
const { PORT, MOVIES_DIR, METADATA_DIR, TRANSCODED_DIR } = require('./src/config');
const { createServer } = require('./src/server');
const { scanAndRegister } = require('./src/scanner');

// MOVIES_DIR is never auto-created: it must be an existing folder the user
// explicitly configured via MOVIES_FOLDER, so a missing/mistyped path fails
// loudly here rather than silently scanning (or creating) an empty folder.
if (!MOVIES_DIR) {
  console.error('MOVIES_FOLDER is not set. Add it to backend/.env — see .env.example.');
  process.exit(1);
}
if (!fs.existsSync(MOVIES_DIR) || !fs.statSync(MOVIES_DIR).isDirectory()) {
  console.error(
    `MOVIES_FOLDER is set to "${MOVIES_DIR}", but that path doesn't exist or isn't a directory.`
  );
  process.exit(1);
}

for (const dir of [METADATA_DIR, TRANSCODED_DIR]) {
  fs.mkdirSync(dir, { recursive: true });
}

const { server } = createServer();

server.listen(PORT, () => {
  console.log(`pigflix backend listening on http://localhost:${PORT}`);
  scanAndRegister().catch((err) => console.error('[scan] Failed:', err));
});
