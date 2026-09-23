import 'package:flutter/material.dart';

import '../services/remote_ws_service.dart';
import '../widgets/dpad.dart';
import '../widgets/playback_controls.dart';

/// The remote-control screen shown once paired. Its button layout adapts to
/// whichever screen the web frontend is currently showing, per the
/// `currentScreen` state broadcast over the socket.
class RemoteScreen extends StatelessWidget {
  const RemoteScreen({super.key});

  void _sendCommand(String action, {int? deltaSeconds}) {
    RemoteWsService.instance.sendCommand(action, deltaSeconds: deltaSeconds);
  }

  void _openSearchSheet(BuildContext context) {
    final controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Search movies',
                border: OutlineInputBorder(),
              ),
              onChanged: RemoteWsService.instance.sendSearchQuery,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _backButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => _sendCommand('back'),
        icon: const Icon(Icons.arrow_back),
        label: const Text('Back'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: ValueListenableBuilder<String?>(
                valueListenable: RemoteWsService.instance.currentScreen,
                builder: (context, screen, _) {
                  switch (screen) {
                    case 'grid':
                      // No Back button here: the grid is the root screen on
                      // Pigflix, so there's nowhere for "back" to go — the
                      // display's own command handler treats it as a no-op.
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          DPad(onCommand: _sendCommand),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () => _openSearchSheet(context),
                              icon: const Icon(Icons.search),
                              label: const Text('Search'),
                            ),
                          ),
                        ],
                      );
                    case 'detail':
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: () => _sendCommand('select'),
                              icon: const Icon(Icons.play_arrow),
                              label: const Text('Play'),
                            ),
                          ),
                          const SizedBox(height: 12),
                          _backButton(),
                        ],
                      );
                    case 'player':
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ValueListenableBuilder<String?>(
                            valueListenable:
                                RemoteWsService.instance.nowPlayingTitle,
                            builder: (context, title, _) => title == null
                                ? const SizedBox.shrink()
                                : Padding(
                                    padding: const EdgeInsets.only(bottom: 24),
                                    child: Text(
                                      'Now playing: $title',
                                      textAlign: TextAlign.center,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                  ),
                          ),
                          PlaybackControls(onCommand: _sendCommand),
                          const SizedBox(height: 24),
                          _backButton(),
                        ],
                      );
                    default:
                      return const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Connected — waiting for Pigflix…'),
                        ],
                      );
                  }
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
