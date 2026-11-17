import 'dart:io' show File;

import 'package:flutter/material.dart';

import '../services/image_disk_cache.dart';

/// Drop-in replacement for `Image.network(url, fit: fit, errorBuilder: ...)`
/// that goes through [ImageDiskCache] on Linux (where it's cached to disk
/// after the first load) and falls back to plain `Image.network` elsewhere
/// (web, or if the cache lookup itself fails) — see ImageDiskCache's own
/// doc comment for why a disk cache is safe here.
class CachedPosterImage extends StatefulWidget {
  final String url;
  final BoxFit? fit;
  final Widget Function(BuildContext, Object, StackTrace?)? errorBuilder;
  // Only used by the network fallback (web, or a Linux cache-lookup
  // failure) — Image.file has no equivalent, since a local disk read has
  // no meaningful chunked-progress concept the way a network fetch does.
  final ImageLoadingBuilder? loadingBuilder;

  const CachedPosterImage({
    super.key,
    required this.url,
    this.fit,
    this.errorBuilder,
    this.loadingBuilder,
  });

  @override
  State<CachedPosterImage> createState() => _CachedPosterImageState();
}

class _CachedPosterImageState extends State<CachedPosterImage> {
  late Future<String?> _pathFuture;

  @override
  void initState() {
    super.initState();
    _pathFuture = ImageDiskCache.cachedFilePath(widget.url);
  }

  @override
  void didUpdateWidget(CachedPosterImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _pathFuture = ImageDiskCache.cachedFilePath(widget.url);
    }
  }

  Widget _networkFallback() {
    return Image.network(
      widget.url,
      fit: widget.fit,
      errorBuilder: widget.errorBuilder,
      loadingBuilder: widget.loadingBuilder,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _pathFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        // Not Linux, or the disk cache couldn't produce a file — fall back
        // to loading straight from the network, same as before this cache
        // existed.
        if (snapshot.data == null) return _networkFallback();
        return Image.file(
          File(snapshot.data!),
          fit: widget.fit,
          errorBuilder: widget.errorBuilder,
        );
      },
    );
  }
}
