import 'package:flutter/material.dart';

/// Play/pause + seek ±10s controls for the player screen's remote layout.
/// The play/pause button can't reflect true playing/paused state (the
/// protocol has no display→remote playback-state broadcast in v1), so it's
/// a stateless toggle — see the matching note in the frontend's
/// player_screen.dart.
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
            child: const Icon(Icons.play_arrow, size: 40),
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
