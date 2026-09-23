import 'package:flutter/material.dart';

import 'screens/movie_grid_screen.dart';
import 'services/remote_control_service.dart';
import 'services/route_observer.dart';

void main() {
  RemoteControlService.instance.connect();
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
      navigatorObservers: [routeObserver],
      home: const MovieGridScreen(),
    );
  }
}
