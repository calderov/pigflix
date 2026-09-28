import 'dart:async';

import 'package:flutter/material.dart';

import 'screens/paired_transition_screen.dart';
import 'screens/pairing_screen.dart';
import 'screens/remote_screen.dart';
import 'services/remote_ws_service.dart';

void main() {
  runApp(const PigflixRemoteApp());
}

class PigflixRemoteApp extends StatelessWidget {
  const PigflixRemoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pigflix Link',
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.blueAccent,
        useMaterial3: true,
      ),
      home: const _RootScreen(),
    );
  }
}

/// Single navigation point switching between the pairing flow and the
/// remote-control screen, driven by [RemoteWsService.instance.status].
///
/// Also watches app lifecycle: Android tends to suspend a backgrounded
/// app's socket as soon as the screen turns off, so the connection is
/// usually already dead by the time the screen turns back on. Reconnecting
/// right on resume (rather than waiting for whatever retry delay happens
/// to be pending) makes that feel instant.
class _RootScreen extends StatefulWidget {
  const _RootScreen();

  @override
  State<_RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<_RootScreen> with WidgetsBindingObserver {
  bool _showLinkedTransition = false;
  Timer? _transitionTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    RemoteWsService.instance.freshPairTick.addListener(_onFreshPair);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    RemoteWsService.instance.freshPairTick.removeListener(_onFreshPair);
    _transitionTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      RemoteWsService.instance.reconnectNow();
    }
  }

  /// Briefly shows [PairedTransitionScreen] instead of jumping straight to
  /// [RemoteScreen] — but only for a fresh pairing (see [RemoteWsService
  /// .freshPairTick]), not a silent session-resume, e.g. after the app was
  /// backgrounded and its socket dropped, then reconnected automatically.
  void _onFreshPair() {
    _transitionTimer?.cancel();
    setState(() => _showLinkedTransition = true);
    _transitionTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showLinkedTransition = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_showLinkedTransition) return const PairedTransitionScreen();
    return ValueListenableBuilder<ConnectionStatus>(
      valueListenable: RemoteWsService.instance.status,
      builder: (context, status, _) {
        return status == ConnectionStatus.paired
            ? const RemoteScreen()
            : const PairingScreen();
      },
    );
  }
}
