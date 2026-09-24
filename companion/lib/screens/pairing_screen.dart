import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/remote_ws_service.dart';
import '../utils/haptics.dart';
import '../widgets/pigflix_logo.dart';

const _hostPrefsKey = 'backend_host';

Map<String, String> _pairErrorMessages = const {
  'invalid_code': 'Incorrect code',
  'expired': 'Code expired, generate a new one on Pigflix',
  'already_paired': 'A remote is already connected',
  'session_ended': 'Previous session ended — enter a new code',
};

class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key});

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final _hostController = TextEditingController();
  final _codeController = TextEditingController();
  bool _loadingStoredHost = true;

  @override
  void initState() {
    super.initState();
    _loadStoredHost();
  }

  Future<void> _loadStoredHost() async {
    final prefs = await SharedPreferences.getInstance();
    final host = prefs.getString(_hostPrefsKey);
    if (!mounted) return;
    setState(() => _loadingStoredHost = false);
    if (host != null && host.isNotEmpty) {
      _hostController.text = host;
      _connect(host);
    }
  }

  Future<void> _connect(String host) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_hostPrefsKey, host);
    RemoteWsService.instance.connect('ws://$host');
  }

  void _changeServer() {
    tapHaptic();
    RemoteWsService.instance.disconnect();
  }

  @override
  void dispose() {
    _hostController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingStoredHost) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: Stack(
        children: [
          const SafeArea(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Align(alignment: Alignment.topLeft, child: PigflixLogo()),
            ),
          ),
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: ValueListenableBuilder<ConnectionStatus>(
                    valueListenable: RemoteWsService.instance.status,
                    builder: (context, status, _) {
                      switch (status) {
                        case ConnectionStatus.disconnected:
                          return _HostForm(
                            controller: _hostController,
                            onConnect: () {
                              tapHaptic();
                              final host = _hostController.text.trim();
                              if (host.isNotEmpty) _connect(host);
                            },
                          );
                        case ConnectionStatus.connecting:
                          return const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 16),
                              Text('Connecting…'),
                            ],
                          );
                        case ConnectionStatus.awaitingCode:
                          return _CodeForm(
                            controller: _codeController,
                            onSubmit: () {
                              tapHaptic();
                              final code = _codeController.text.trim();
                              // The actual expected length is a
                              // backend-configured value
                              // (PAIRING_CODE_LENGTH), not something this
                              // app should assume — an incorrect code is
                              // already surfaced via pair_failure below.
                              if (code.isNotEmpty) {
                                RemoteWsService.instance.submitPairingCode(
                                  code,
                                );
                              }
                            },
                            onChangeServer: _changeServer,
                          );
                        case ConnectionStatus.paired:
                          return const SizedBox.shrink();
                      }
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HostForm extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onConnect;

  const _HostForm({required this.controller, required this.onConnect});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.settings_remote, size: 48),
        const SizedBox(height: 16),
        Text(
          'Pigflix Remote',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 24),
        TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Pigflix server',
            hintText: '192.168.1.50:4000',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => onConnect(),
        ),
        ValueListenableBuilder<String?>(
          valueListenable: RemoteWsService.instance.connectError,
          builder: (context, error, _) {
            if (error == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                error,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.redAccent),
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: onConnect,
            child: const Text('Connect'),
          ),
        ),
      ],
    );
  }
}

class _CodeForm extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSubmit;
  final VoidCallback onChangeServer;

  const _CodeForm({
    required this.controller,
    required this.onSubmit,
    required this.onChangeServer,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Enter code', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text(
          'Shown in the "Pair remote control" dialog on Pigflix',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        TextField(
          controller: controller,
          autofocus: true,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 32, letterSpacing: 8),
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          onSubmitted: (_) => onSubmit(),
        ),
        ValueListenableBuilder<String?>(
          valueListenable: RemoteWsService.instance.pairError,
          builder: (context, reason, _) {
            if (reason == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _pairErrorMessages[reason] ?? 'Pairing failed',
                style: const TextStyle(color: Colors.redAccent),
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: onSubmit,
            child: const Text('Connect'),
          ),
        ),
        TextButton(
          onPressed: onChangeServer,
          child: const Text('Change server'),
        ),
      ],
    );
  }
}
