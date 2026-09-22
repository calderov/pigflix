import '../services/api_service.dart';

/// Backend responses use paths relative to the API (e.g. "/api/movies/x/poster").
/// Resolve them against [backendUrl] so Image.network / video_player don't
/// resolve them relative to the Flutter app's own origin instead.
String? _resolve(String? path) {
  if (path == null) return null;
  if (path.startsWith('http://') || path.startsWith('https://')) return path;
  return '$backendUrl$path';
}

/// One subtitle file available for a movie. [lang] is the language code
/// parsed from the filename suffix (e.g. "en" from "Movie.en.srt"), or null
/// for a subtitle file with no language suffix ("Movie.srt").
class SubtitleTrack {
  final String? lang;
  final String url;

  SubtitleTrack({required this.lang, required this.url});

  factory SubtitleTrack.fromJson(Map<String, dynamic> json) {
    return SubtitleTrack(
      lang: json['lang'] as String?,
      url: _resolve(json['url'] as String)!,
    );
  }
}

class Movie {
  final String id;
  final String title;
  final int? year;
  final String? overview;
  final List<String> genres;
  final int? runtime;
  final double? rating;
  final String? posterUrl;
  final String? backdropUrl;
  final String streamUrl;
  final List<SubtitleTrack> subtitles;
  final String metadataStatus;
  final String transcodeStatus;
  final double transcodeProgress;

  Movie({
    required this.id,
    required this.title,
    required this.year,
    required this.overview,
    required this.genres,
    required this.runtime,
    required this.rating,
    required this.posterUrl,
    required this.backdropUrl,
    required this.streamUrl,
    required this.subtitles,
    required this.metadataStatus,
    required this.transcodeStatus,
    required this.transcodeProgress,
  });

  factory Movie.fromJson(Map<String, dynamic> json) {
    return Movie(
      id: json['id'] as String,
      title: json['title'] as String,
      year: json['year'] as int?,
      overview: json['overview'] as String?,
      genres: (json['genres'] as List<dynamic>? ?? []).cast<String>(),
      runtime: json['runtime'] as int?,
      rating: (json['rating'] as num?)?.toDouble(),
      posterUrl: _resolve(json['posterUrl'] as String?),
      backdropUrl: _resolve(json['backdropUrl'] as String?),
      streamUrl: _resolve(json['streamUrl'] as String)!,
      subtitles: (json['subtitles'] as List<dynamic>? ?? [])
          .map((t) => SubtitleTrack.fromJson(t as Map<String, dynamic>))
          .toList(),
      metadataStatus: json['metadataStatus'] as String? ?? 'pending',
      transcodeStatus: json['transcodeStatus'] as String? ?? 'not_started',
      transcodeProgress: (json['transcodeProgress'] as num?)?.toDouble() ?? 0,
    );
  }
}
