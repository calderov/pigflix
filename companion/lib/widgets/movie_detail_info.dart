import 'package:flutter/material.dart';

import '../models/movie_info.dart';
import '../services/remote_ws_service.dart';

/// Poster, title, year/runtime/rating, genre chips, and overview for
/// whichever movie is on the web frontend's detail screen — mirrors that
/// screen's own layout (see `frontend/lib/screens/movie_detail_screen.dart`
/// `_DetailsColumn`) so the companion app resembles it.
class MovieDetailInfo extends StatelessWidget {
  const MovieDetailInfo({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MovieInfo?>(
      valueListenable: RemoteWsService.instance.movieInfo,
      builder: (context, info, _) {
        if (info == null) return const SizedBox.shrink();
        final theme = Theme.of(context);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (info.posterUrl != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 160,
                  child: AspectRatio(
                    aspectRatio: 2 / 3,
                    child: Image.network(
                      info.posterUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (info.title != null)
              Text(
                info.title!,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge,
              ),
            if (info.year != null ||
                info.formattedRuntime != null ||
                info.rating != null) ...[
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (info.year != null) Text('${info.year}'),
                  if (info.formattedRuntime != null)
                    Text(info.formattedRuntime!),
                  if (info.rating != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star, color: Colors.amber, size: 16),
                        const SizedBox(width: 4),
                        Text(info.rating!.toStringAsFixed(1)),
                      ],
                    ),
                ],
              ),
            ],
            if (info.genres.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: info.genres
                    .map(
                      (genre) => Chip(
                        label: Text(genre),
                        visualDensity: VisualDensity.compact,
                      ),
                    )
                    .toList(),
              ),
            ],
            if (info.overview?.isNotEmpty == true) ...[
              const SizedBox(height: 16),
              Text(info.overview!, style: theme.textTheme.bodyMedium),
            ],
          ],
        );
      },
    );
  }
}
