/// Metadata about whichever movie the web frontend is currently showing on
/// its detail (or player) screen, so the companion app's detail layout can
/// mirror it. Fields the current screen doesn't send (e.g. the player
/// screen only ever sends [title]) are simply null/empty.
class MovieInfo {
  final String? title;
  final String? backdropUrl;
  final String? posterUrl;
  final int? year;
  final int? runtimeMinutes;
  final double? rating;
  final List<String> genres;
  final String? overview;

  const MovieInfo({
    this.title,
    this.backdropUrl,
    this.posterUrl,
    this.year,
    this.runtimeMinutes,
    this.rating,
    this.genres = const [],
    this.overview,
  });

  /// e.g. "1h 43m", "45m", "2h" — matches the frontend's own formatting
  /// (see `_formattedRuntime` in movie_detail_screen.dart).
  String? get formattedRuntime {
    final minutes = runtimeMinutes;
    if (minutes == null || minutes <= 0) return null;
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (hours == 0) return '${mins}m';
    if (mins == 0) return '${hours}h';
    return '${hours}h ${mins}m';
  }
}
