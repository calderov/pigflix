const fs = require('fs');
const { PORT, MOVIES_DIR, METADATA_DIR, TRANSCODED_DIR } = require('./src/config');
const { createServer } = require('./src/server');
const { scanAndRegister } = require('./src/scanner');

for (const dir of [MOVIES_DIR, METADATA_DIR, TRANSCODED_DIR]) {
  fs.mkdirSync(dir, { recursive: true });
}

const { server } = createServer();

server.listen(PORT, () => {
  console.log(`pigflix backend listening on http://localhost:${PORT}`);
  scanAndRegister().catch((err) => console.error('[scan] Failed:', err));
});
