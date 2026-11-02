import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player_media_kit/video_player_media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'screens/movie_grid_screen.dart';
import 'services/api_service.dart';
import 'services/fullscreen/fullscreen_control.dart' as fullscreen;
import 'services/remote_control_service.dart';
import 'services/route_observer.dart';

/// Guards every desktop-only call below — `Platform.*` is never evaluated
/// on web thanks to `&&` short-circuiting, since `dart:io` only compiles
/// for web as a stub that throws if actually touched.
bool get _isDesktop =>
    !kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isWindows);

// Registered as a hardware-level handler (not a widget Shortcuts binding) so
// F11 toggles fullscreen regardless of which screen or widget has focus.
bool _handleGlobalKeyEvent(KeyEvent event) {
  if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.f11) {
    fullscreen.toggleFullscreen();
    return true;
  }
  return false;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (_isDesktop) {
    await windowManager.ensureInitialized();
    HardwareKeyboard.instance.addHandler(_handleGlobalKeyEvent);
  }
  VideoPlayerMediaKit.ensureInitialized(linux: true);
  RemoteControlService.instance.connect();
  loadConfig();
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
