import 'package:flutter/material.dart';

/// Small Pigflix wordmark shown in the top-left corner of the connection,
/// pairing, and d-pad (grid) screens — omitted on the detail/player
/// screens, which are already dominated by the movie's own backdrop art.
class PigflixLogo extends StatelessWidget {
  const PigflixLogo({super.key});

  @override
  Widget build(BuildContext context) {
    return Image.asset('assets/images/logo.png', height: 28);
  }
}
