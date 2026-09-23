import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum ConnectionStatus { disconnected, connecting, awaitingCode, paired }

const _sessionTokenPrefsKey = 'remote_session_token';

/// The companion app's single WebSocket connection to the Pigflix backend's
/// `/ws?role=remote` relay endpoint. Mirrors the shape of the web
/// frontend's `RemoteControlService` (see `frontend/lib/services/
/// remote_control_service.dart`), extended with richer status since this
/// app's entire UI *is* the pairing/remote flow, rather than a side dialog.
///
/// Also handles reconnecting on its own: Android suspends a backgrounded
/// app's socket fairly aggressively (e.g. as soon as the screen turns off
/// mid-movie), so a dropped connection is the common case, not an edge
/// case. A successful pairing is given a [sessionToken] by the backend
/// (persisted locally) that lets a fresh socket silently resume the same
/// pairing — see `resume_session` below — without walking back through
/// pairing-code entry every time the screen wakes up.
class RemoteWsService {
  RemoteWsService._();

  static final RemoteWsService instance = RemoteWsService._();

  final ValueNotifier<ConnectionStatus> status = ValueNotifier(
    ConnectionStatus.disconnected,
  );
  final ValueNotifier<String?> currentScreen = ValueNotifier(null);
  final ValueNotifier<String?> nowPlayingTitle = ValueNotifier(null);
  final ValueNotifier<String?> pairError = ValueNotifier(null);

  /// Set when [connect] fails or times out, so the pairing screen can show
  /// *why* — otherwise a wrong/unreachable host looks identical to a
  /// working one until something is sent.
  final ValueNotifier<String?> connectError = ValueNotifier(null);

  WebSocketChannel? _channel;
  Timer? _searchDebounce;
  Timer? _reconnectTimer;
  String? _backendWsUrl;
  String? _sessionToken;
  bool _explicitDisconnect = false;

  /// Connects to `<backendWsUrl>/ws?role=remote` and only advances past
  /// [ConnectionStatus.connecting] once the socket is actually open —
  /// [WebSocketChannel.connect] itself returns immediately and connects
  /// lazily, so without awaiting [WebSocketChannel.ready] here, *any* host
  /// (reachable or not) would appear to "connect" instantly.
  ///
  /// If a session token was saved from a previous successful pairing, it's
  /// sent immediately as a `resume_session` attempt instead of waiting on
  /// the pairing-code screen — this is what makes reconnecting after a
  /// screen-off drop seamless rather than requiring a fresh code every
  /// time.
  Future<void> connect(String backendWsUrl) async {
    _explicitDisconnect = false;
    _reconnectTimer?.cancel();
    _backendWsUrl = backendWsUrl;
    status.value = ConnectionStatus.connecting;
    connectError.value = null;
    pairError.value = null;

    _sessionToken ??= await _loadStoredToken();

    final channel = WebSocketChannel.connect(
      Uri.parse('$backendWsUrl/ws?role=remote'),
    );
    _channel = channel;

    try {
      await channel.ready.timeout(const Duration(seconds: 8));
    } catch (e) {
      if (_channel != channel) return; // superseded by a newer connect()
      _channel = null;
      status.value = ConnectionStatus.disconnected;
      connectError.value = e is TimeoutException
          ? 'Could not reach $backendWsUrl (timed out)'
          : 'Could not connect to $backendWsUrl';
      return;
    }

    if (_channel != channel) return; // superseded while we were waiting
    channel.stream.listen(
      _handleMessage,
      onDone: _handleDisconnect,
      onError: (_) => _handleDisconnect(),
    );

    final token = _sessionToken;
    if (token != null) {
      _send({'type': 'resume_session', 'token': token});
      // Stays `connecting` until resume_success/resume_failure arrives.
    } else {
      status.value = ConnectionStatus.awaitingCode;
    }
  }

  /// Attempts to reconnect right now, bypassing [_scheduleReconnect]'s
  /// delay — called when the app comes back to the foreground (e.g. the
  /// screen turns back on) so recovery feels instant rather than waiting
  /// out whatever fixed delay is already pending.
  void reconnectNow() {
    if (_explicitDisconnect) return;
    if (status.value == ConnectionStatus.paired ||
        status.value == ConnectionStatus.connecting) {
      return;
    }
    final host = _backendWsUrl;
    if (host == null) return;
    _reconnectTimer?.cancel();
    connect(host);
  }

  void _scheduleReconnect() {
    if (_explicitDisconnect) return;
    final host = _backendWsUrl;
    if (host == null) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () => connect(host));
  }

  void _handleDisconnect() {
    _channel = null;
    currentScreen.value = null;
    nowPlayingTitle.value = null;
    status.value = ConnectionStatus.disconnected;
    _scheduleReconnect();
  }

  /// Closes the current connection, e.g. when the user wants to point the
  /// app at a different backend host — unlike an unexpected drop, this
  /// does not auto-reconnect, and forgets the saved session since it no
  /// longer applies to whatever host comes next.
  void disconnect() {
    _explicitDisconnect = true;
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _handleDisconnect();
    _clearStoredToken();
  }

  void _handleMessage(dynamic raw) {
    final Map<String, dynamic> msg = jsonDecode(raw as String);
    switch (msg['type']) {
      case 'pair_success':
        pairError.value = null;
        status.value = ConnectionStatus.paired;
        final token = msg['sessionToken'] as String?;
        if (token != null) _saveToken(token);
      case 'pair_failure':
        pairError.value = msg['reason'] as String?;
      case 'resume_success':
        pairError.value = null;
        status.value = ConnectionStatus.paired;
      case 'resume_failure':
        _clearStoredToken();
        pairError.value = 'session_ended';
        status.value = ConnectionStatus.awaitingCode;
      case 'screen':
        currentScreen.value = msg['screen'] as String?;
        nowPlayingTitle.value = msg['movieTitle'] as String?;
      case 'unpaired':
        _clearStoredToken();
        currentScreen.value = null;
        nowPlayingTitle.value = null;
        status.value = ConnectionStatus.awaitingCode;
    }
  }

  void _send(Map<String, dynamic> message) {
    _channel?.sink.add(jsonEncode(message));
  }

  void submitPairingCode(String code) {
    pairError.value = null;
    _send({'type': 'pair_attempt', 'code': code});
  }

  void sendCommand(String action, {int? deltaSeconds}) {
    _send({'type': 'command', 'action': action, 'deltaSeconds': ?deltaSeconds});
  }

  void sendSearchQuery(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      _send({'type': 'search_query', 'query': query});
    });
  }

  Future<String?> _loadStoredToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_sessionTokenPrefsKey);
  }

  Future<void> _saveToken(String token) async {
    _sessionToken = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionTokenPrefsKey, token);
  }

  Future<void> _clearStoredToken() async {
    _sessionToken = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionTokenPrefsKey);
  }
}
