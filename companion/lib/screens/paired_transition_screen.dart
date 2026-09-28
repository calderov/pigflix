import 'package:flutter/material.dart';

/// Shown for a couple of seconds right after the companion app links to a
/// Pigflix server, before handing off to `RemoteScreen` — without it, a
/// successful pairing (whether via QR or manual code entry) would jump
/// straight into the remote-control UI with nothing on screen confirming
/// it actually worked.
class PairedTransitionScreen extends StatelessWidget {
  const PairedTransitionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.check_circle,
              size: 72,
              color: Colors.greenAccent,
            ),
            const SizedBox(height: 20),
            Text('Linked!', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            const Text('Pigflix Link is now connected'),
          ],
        ),
      ),
    );
  }
}
