import 'package:flutter/material.dart';

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
      title: 'Pigflix Remote',
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.redAccent,
        useMaterial3: true,
      ),
      home: const _RootScreen(),
    );
  }
}

/// Single navigation point switching between the pairing flow and the
/// remote-control screen, driven by [RemoteWsService.instance.status].
class _RootScreen extends StatelessWidget {
  const _RootScreen();

  @override
  Widget build(BuildContext context) {
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
