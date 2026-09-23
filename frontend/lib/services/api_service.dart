import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../models/movie.dart';

/// Base URL of the pigflix backend. Override at build/run time with
/// --dart-define=BACKEND_URL=http://your-server:4000 if it's not running
/// on localhost:4000.
const String backendUrl = String.fromEnvironment(
  'BACKEND_URL',
  defaultValue: 'http://localhost:4000',
);

/// The same backend, as a WebSocket URL (`http`→`ws`, `https`→`wss`), for
/// [RemoteControlService]'s connection to the `/ws` relay endpoint.
String get backendWsUrl => backendUrl.replaceFirst('http', 'ws');

class ApiService {
  Future<List<Movie>> fetchMovies() async {
    final res = await http.get(Uri.parse('$backendUrl/api/movies'));
    if (res.statusCode != 200) {
      throw Exception('Failed to load movies (${res.statusCode})');
    }
    final List<dynamic> data = jsonDecode(res.body) as List<dynamic>;
    return data
        .map((json) => Movie.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Polls a single movie's metadata/transcode status. Hitting this also
  /// kicks off transcoding on the backend if it hasn't started yet.
  Future<Movie> fetchMovieStatus(String id) async {
    final res = await http.get(Uri.parse('$backendUrl/api/movies/$id/status'));
    if (res.statusCode != 200) {
      throw Exception('Failed to load movie status (${res.statusCode})');
    }
    return Movie.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Fetches the raw .srt content for a subtitle track. [url] is one of the
  /// already-resolved [SubtitleTrack.url] values from a [Movie].
  Future<String> fetchSubtitle(String url) async {
    final res = await http.get(Uri.parse(url));
    if (res.statusCode != 200) {
      throw Exception('Failed to load subtitle (${res.statusCode})');
    }
    return res.body;
  }

  /// Re-runs the TMDb search for a movie with a user-supplied title/year,
  /// for fixing unrecognized or mislabeled entries.
  Future<Movie> retryMetadata(
    String id, {
    required String title,
    int? year,
  }) async {
    final res = await http.post(
      Uri.parse('$backendUrl/api/movies/$id/retry-metadata'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'title': title, 'year': ?year}),
    );
    if (res.statusCode != 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>?;
      throw Exception(
        body?['error'] as String? ?? 'Search failed (${res.statusCode})',
      );
    }
    return Movie.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Checks the given password against the backend's ADMIN_PASSWORD. Only
  /// its SHA-256 hash is sent over the wire, never the password itself.
  /// Returns true/false for a correct/incorrect password; throws if admin
  /// mode isn't configured on the backend or the request otherwise fails.
  Future<bool> checkAdminPassword(String password) async {
    final passwordHash = sha256.convert(utf8.encode(password)).toString();
    final res = await http.post(
      Uri.parse('$backendUrl/api/admin/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'passwordHash': passwordHash}),
    );
    if (res.statusCode == 200) return true;
    if (res.statusCode == 401) return false;
    final body = jsonDecode(res.body) as Map<String, dynamic>?;
    throw Exception(
      body?['error'] as String? ?? 'Admin login failed (${res.statusCode})',
    );
  }
}
