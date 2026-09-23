import 'package:flutter/material.dart';

import '../services/remote_ws_service.dart';

/// Play/pause + seek ±10s controls for the player screen's remote layout.
/// The play/pause button's icon reflects the frontend's actual playback
/// state (see `RemoteWsService.isPlaying`, updated from `playback_state`
/// messages), not just a fixed icon — it shows a pause icon while the
/// movie is playing and a play icon while paused.
class PlaybackControls extends StatelessWidget {
  final void Function(String action, {int? deltaSeconds}) onCommand;

  const PlaybackControls({super.key, required this.onCommand});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filled(
          iconSize: 32,
          onPressed: () => onCommand('seek', deltaSeconds: -10),
          icon: const Icon(Icons.replay_10),
        ),
        const SizedBox(width: 16),
        SizedBox(
          width: 80,
          height: 80,
          child: FilledButton(
            style: FilledButton.styleFrom(shape: const CircleBorder()),
            onPressed: () => onCommand('play_pause'),
            child: ValueListenableBuilder<bool>(
              valueListenable: RemoteWsService.instance.isPlaying,
              builder: (context, isPlaying, _) =>
                  Icon(isPlaying ? Icons.pause : Icons.play_arrow, size: 40),
            ),
          ),
        ),
        const SizedBox(width: 16),
        IconButton.filled(
          iconSize: 32,
          onPressed: () => onCommand('seek', deltaSeconds: 10),
          icon: const Icon(Icons.forward_10),
        ),
      ],
    );
  }
}
