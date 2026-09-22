const { spawnSync } = require('child_process');

/**
 * Probes a media file for its primary video/audio codec and duration.
 * Used to decide whether a source file can be fast-remuxed (already
 * browser-compatible H.264/AAC) or needs a full re-encode.
 */
function probeMedia(inputPath) {
  const proc = spawnSync('ffprobe', [
    '-v', 'error',
    '-show_entries', 'format=duration:stream=codec_name,codec_type',
    '-of', 'json',
    inputPath,
  ]);

  if (proc.status !== 0) {
    throw new Error(`ffprobe failed: ${proc.stderr?.toString().slice(-500)}`);
  }

  const data = JSON.parse(proc.stdout.toString());
  const videoStream = (data.streams || []).find((s) => s.codec_type === 'video');
  const audioStream = (data.streams || []).find((s) => s.codec_type === 'audio');

  return {
    durationSec: parseFloat(data.format?.duration) || 0,
    videoCodec: videoStream?.codec_name || null,
    audioCodec: audioStream?.codec_name || null,
  };
}

const BROWSER_COMPATIBLE_VIDEO = new Set(['h264']);
const BROWSER_COMPATIBLE_AUDIO = new Set(['aac']);

function isBrowserCompatible({ videoCodec, audioCodec }) {
  return BROWSER_COMPATIBLE_VIDEO.has(videoCodec) && BROWSER_COMPATIBLE_AUDIO.has(audioCodec);
}

module.exports = { probeMedia, isBrowserCompatible };
