import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'api_service.dart';

/// App-wide connection to the backend's `/ws?role=display` relay endpoint,
/// used to pair with a companion "Pigflix Remote" app and receive the
/// commands it sends. Follows the same static-singleton pattern as
/// [AdminSession] (see `admin_session.dart`), extended to own a socket.
class RemoteControlService {
  RemoteControlService._();

  static final RemoteControlService instance = RemoteControlService._();

  final ValueNotifier<bool> isPaired = ValueNotifier(false);
  final ValueNotifier<String?> pairingCode = ValueNotifier(null);

  final StreamController<Map<String, dynamic>> _commandController =
      StreamController.broadcast();

  /// Incoming `command`/`search_query` messages from the paired remote.
  /// Screens subscribe and filter by `msg['type']`/`msg['action']`
  /// themselves rather than the service pre-splitting streams, keeping
  /// this one contract simple.
  Stream<Map<String, dynamic>> get commandStream => _commandController.stream;

  WebSocketChannel? _channel;
  bool _connecting = false;

  void connect() {
    if (_connecting || _channel != null) return;
    _connecting = true;

    try {
      _channel = WebSocketChannel.connect(
        Uri.parse('$backendWsUrl/ws?role=display'),
      );
      _channel!.stream.listen(
        _handleMessage,
        onDone: _handleDisconnect,
        onError: (_) => _handleDisconnect(),
      );
    } catch (_) {
      _handleDisconnect();
    } finally {
      _connecting = false;
    }
  }

  void _handleDisconnect() {
    _channel = null;
    isPaired.value = false;
    pairingCode.value = null;
    // Simple fixed-delay retry — this is a LAN app expected to run
    // continuously, so a full backoff strategy isn't needed for v1.
    Future.delayed(const Duration(seconds: 3), connect);
  }

  void _handleMessage(dynamic raw) {
    final Map<String, dynamic> msg = jsonDecode(raw as String);
    switch (msg['type']) {
      case 'pairing_code':
        pairingCode.value = msg['code'] as String?;
      case 'pair_success':
        isPaired.value = true;
      case 'unpaired':
        isPaired.value = false;
        pairingCode.value = null;
      case 'command':
      case 'search_query':
        _commandController.add(msg);
    }
  }

  void _send(Map<String, dynamic> message) {
    _channel?.sink.add(jsonEncode(message));
  }

  void requestPairingCode() {
    pairingCode.value = null;
    _send({'type': 'request_pairing_code'});
  }

  void sendScreenState(
    String screen, {
    String? movieTitle,
    String? backdropUrl,
    String? posterUrl,
    int? year,
    int? runtimeMinutes,
    double? rating,
    List<String>? genres,
    String? overview,
    String? searchQuery,
  }) {
    _send({
      'type': 'screen',
      'screen': screen,
      'movieTitle': ?movieTitle,
      'backdropUrl': ?backdropUrl,
      'posterUrl': ?posterUrl,
      'year': ?year,
      'runtimeMinutes': ?runtimeMinutes,
      'rating': ?rating,
      'genres': ?genres,
      'overview': ?overview,
      'searchQuery': ?searchQuery,
    });
  }

  void sendPlaybackState(bool isPlaying) {
    _send({'type': 'playback_state', 'isPlaying': isPlaying});
  }
}
