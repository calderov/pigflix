import 'package:flutter/material.dart';

import 'screens/movie_grid_screen.dart';

void main() {
  runApp(const PigflixApp());
}

class PigflixApp extends StatelessWidget {
  const PigflixApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pigflix',
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.blueAccent,
        useMaterial3: true,
      ),
      home: const MovieGridScreen(),
    );
  }
}
