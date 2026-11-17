import 'dart:convert';
import 'dart:io' show Directory, File, Platform;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Disk cache for poster/backdrop images — Linux desktop client only (the
/// Settings/backend-URL-override feature this mirrors is Linux-only for the
/// same reason: web/companion don't need it). Everything here is a no-op
/// off-Linux, so callers can call it unconditionally and fall back to
/// plain network loading.
///
/// Poster/backdrop URLs are stable per movie (`/api/movies/:id/poster`,
/// see backend/src/routes/movies.js) — the only thing that ever changes
/// their *content* for an existing movie is the admin "Fix match" flow, so
/// a plain "cache forever, invalidate only on demand" design is correct
/// here, not just a simplification. See [invalidate].
class ImageDiskCache {
  ImageDiskCache._();

  static bool get _enabled => !kIsWeb && Platform.isLinux;

  // Dedupes concurrent cache-miss downloads of the same URL (e.g. a grid
  // tile and a just-opened detail screen both wanting the same poster at
  // once) so they share one request instead of firing two.
  static final Map<String, Future<String?>> _inFlight = {};

  static Future<Directory> _cacheDir() async {
    final base = await getApplicationCacheDirectory();
    final dir = Directory('${base.path}/image_cache');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<File> _fileFor(String url) async {
    final key = sha256.convert(utf8.encode(url)).toString();
    final dir = await _cacheDir();
    return File('${dir.path}/$key');
  }

  /// Returns the local path to [url]'s cached file, downloading and caching
  /// it first if necessary. Returns null off-Linux, or if the download
  /// fails for any reason (network error, non-200, ...) — callers should
  /// fall back to their existing network-image error handling in that case.
  static Future<String?> cachedFilePath(String url) {
    if (!_enabled) return Future.value(null);
    return _inFlight.putIfAbsent(url, () => _cachedFilePath(url));
  }

  static Future<String?> _cachedFilePath(String url) async {
    try {
      final file = await _fileFor(url);
      if (await file.exists()) return file.path;

      final res = await http.get(Uri.parse(url));
      if (res.statusCode != 200) return null;

      // Write to a temp file and rename into place, so a process killed
      // mid-download never leaves a half-written file behind.
      final tempFile = File('${file.path}.part');
      await tempFile.writeAsBytes(res.bodyBytes);
      await tempFile.rename(file.path);
      return file.path;
    } catch (_) {
      return null;
    } finally {
      _inFlight.remove(url);
    }
  }

  /// Deletes [url]'s cached file, if any — forcing the next
  /// [cachedFilePath] call to re-download it. Call after "Fix match"
  /// replaces a movie's poster/backdrop at its (unchanged) URL.
  static Future<void> invalidate(String url) async {
    if (!_enabled) return;
    try {
      final file = await _fileFor(url);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Best-effort — a stale cache entry isn't worth crashing over.
    }
  }
}
