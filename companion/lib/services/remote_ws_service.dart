import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum ConnectionStatus { disconnected, connecting, awaitingCode, paired }

/// The companion app's single WebSocket connection to the Pigflix backend's
/// `/ws?role=remote` relay endpoint. Mirrors the shape of the web
/// frontend's `RemoteControlService` (see `frontend/lib/services/
/// remote_control_service.dart`), extended with richer status since this
/// app's entire UI *is* the pairing/remote flow, rather than a side dialog.
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

  /// Connects to `<backendWsUrl>/ws?role=remote` and only advances to
  /// [ConnectionStatus.awaitingCode] once the socket is actually open —
  /// [WebSocketChannel.connect] itself returns immediately and connects
  /// lazily, so without awaiting [WebSocketChannel.ready] here, *any* host
  /// (reachable or not) would appear to "connect" instantly.
  Future<void> connect(String backendWsUrl) async {
    status.value = ConnectionStatus.connecting;
    connectError.value = null;
    pairError.value = null;

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
    status.value = ConnectionStatus.awaitingCode;
  }

  void _handleDisconnect() {
    _channel = null;
    currentScreen.value = null;
    nowPlayingTitle.value = null;
    status.value = ConnectionStatus.disconnected;
  }

  /// Closes the current connection, e.g. when the user wants to point the
  /// app at a different backend host.
  void disconnect() {
    _channel?.sink.close();
    _handleDisconnect();
  }

  void _handleMessage(dynamic raw) {
    final Map<String, dynamic> msg = jsonDecode(raw as String);
    switch (msg['type']) {
      case 'pair_success':
        pairError.value = null;
        status.value = ConnectionStatus.paired;
      case 'pair_failure':
        pairError.value = msg['reason'] as String?;
      case 'screen':
        currentScreen.value = msg['screen'] as String?;
        nowPlayingTitle.value = msg['movieTitle'] as String?;
      case 'unpaired':
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
}
