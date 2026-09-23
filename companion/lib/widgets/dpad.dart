import 'package:flutter/material.dart';

/// A 5-button directional pad (up/down/left/right around a center Select),
/// used on the grid screen's remote layout.
class DPad extends StatelessWidget {
  final void Function(String action) onCommand;

  const DPad({super.key, required this.onCommand});

  @override
  Widget build(BuildContext context) {
    Widget button(IconData icon, String action, {double size = 64}) {
      return SizedBox(
        width: size,
        height: size,
        child: FilledButton(
          style: FilledButton.styleFrom(shape: const CircleBorder()),
          onPressed: () => onCommand(action),
          child: Icon(icon, size: size * 0.4),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        button(Icons.keyboard_arrow_up, 'move_up'),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            button(Icons.keyboard_arrow_left, 'move_left'),
            const SizedBox(width: 8),
            button(Icons.circle, 'select', size: 72),
            const SizedBox(width: 8),
            button(Icons.keyboard_arrow_right, 'move_right'),
          ],
        ),
        const SizedBox(height: 8),
        button(Icons.keyboard_arrow_down, 'move_down'),
      ],
    );
  }
}
