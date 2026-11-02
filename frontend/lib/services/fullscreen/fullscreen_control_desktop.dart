import 'dart:io';

import 'package:window_manager/window_manager.dart';

bool get _isSupportedDesktop =>
    Platform.isLinux || Platform.isMacOS || Platform.isWindows;

void requestFullscreen() {
  if (!_isSupportedDesktop) return;
  windowManager.setFullScreen(true);
}

void toggleFullscreen() {
  if (!_isSupportedDesktop) return;
  windowManager.isFullScreen().then((active) {
    windowManager.setFullScreen(!active);
  });
}

void exitFullscreenIfActive() {
  if (!_isSupportedDesktop) return;
  windowManager.isFullScreen().then((active) {
    if (active) windowManager.setFullScreen(false);
  });
}
