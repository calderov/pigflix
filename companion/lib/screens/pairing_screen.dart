import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/remote_ws_service.dart';
import '../utils/haptics.dart';
import '../widgets/pigflix_logo.dart';
import 'qr_scan_screen.dart';

const hostPrefsKey = 'backend_host';

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

enum _PairingMode { welcome, manual }

class _PairingScreenState extends State<PairingScreen> {
  final _hostController = TextEditingController();
  final _codeController = TextEditingController();
  bool _loadingStoredHost = true;
  _PairingMode _mode = _PairingMode.welcome;

  @override
  void initState() {
    super.initState();
    final notice = RemoteWsService.instance.disconnectNotice.value;
    if (notice != null) {
      // The display just intentionally ended this pairing — forget the
      // saved host (so there's nothing for a normal launch to silently
      // reconnect to) and show the welcome screen once the user
      // acknowledges why, rather than the usual "reconnect to last host"
      // flow below.
      RemoteWsService.instance.disconnectNotice.value = null;
      _loadingStoredHost = false;
      _forgetHostThenNotify(notice);
    } else {
      _loadStoredHost();
    }
  }

  Future<void> _forgetHostThenNotify(String message) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(hostPrefsKey);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disconnected'),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadStoredHost() async {
    final prefs = await SharedPreferences.getInstance();
    final host = prefs.getString(hostPrefsKey);
    if (!mounted) return;
    setState(() => _loadingStoredHost = false);
    if (host != null && host.isNotEmpty) {
      _hostController.text = host;
      _connect(host);
    }
  }

  Future<void> _connect(String host) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(hostPrefsKey, host);
    await RemoteWsService.instance.connect('ws://$host');
  }

  /// Completes both pairing steps from a single scanned QR code: connects
  /// to the scanned host, then — mirroring exactly what the manual
  /// "Connect" then "Enter code" flow does — submits the scanned code, but
  /// only once [RemoteWsService.connect] has actually finished opening the
  /// socket and is waiting on a code (not, say, still resuming a
  /// previously-saved session, or failed outright).
  Future<void> _connectAndSubmit(String host, String code) async {
    _hostController.text = host;
    await _connect(host);
    if (RemoteWsService.instance.status.value ==
        ConnectionStatus.awaitingCode) {
      _codeController.text = code;
      RemoteWsService.instance.submitPairingCode(code);
    }
  }

  Future<void> _scanQr() async {
    tapHaptic();
    final result = await Navigator.of(
      context,
    ).push<({String host, String code})>(
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    );
    if (result != null) _connectAndSubmit(result.host, result.code);
  }

  void _changeServer() {
    tapHaptic();
    RemoteWsService.instance.disconnect();
    setState(() => _mode = _PairingMode.welcome);
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
                          return switch (_mode) {
                            _PairingMode.welcome => _WelcomeForm(
                              onScan: _scanQr,
                              onManual: () => setState(
                                () => _mode = _PairingMode.manual,
                              ),
                            ),
                            _PairingMode.manual => _HostForm(
                              controller: _hostController,
                              onConnect: () {
                                tapHaptic();
                                final host = _hostController.text.trim();
                                if (host.isNotEmpty) _connect(host);
                              },
                              onBack: () => setState(
                                () => _mode = _PairingMode.welcome,
                              ),
                            ),
                          };
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

/// Landing view shown whenever the app isn't linked to a Pigflix server —
/// lets the user pick a pairing method up front, rather than defaulting
/// straight into the manual host-entry form.
class _WelcomeForm extends StatelessWidget {
  final VoidCallback onScan;
  final VoidCallback onManual;

  const _WelcomeForm({required this.onScan, required this.onManual});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.settings_remote, size: 48),
        const SizedBox(height: 16),
        Text(
          'Pigflix Link',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'How would you like to pair with Pigflix?',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onScan,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan QR code'),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: onManual,
            child: const Text('Enter manually'),
          ),
        ),
      ],
    );
  }
}

class _HostForm extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onConnect;
  final VoidCallback onBack;

  const _HostForm({
    required this.controller,
    required this.onConnect,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.settings_remote, size: 48),
        const SizedBox(height: 16),
        Text(
          'Pigflix Link',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 24),
        TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Pigflix server',
            hintText: '192.168.XX.XX:4000',
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
        TextButton(onPressed: onBack, child: const Text('Back')),
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
