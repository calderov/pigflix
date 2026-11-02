import 'package:web/web.dart' as web;

void requestFullscreen() {
  web.document.documentElement?.requestFullscreen();
}

void toggleFullscreen() {
  if (web.document.fullscreenElement != null) {
    web.document.exitFullscreen();
  } else {
    web.document.documentElement?.requestFullscreen();
  }
}

void exitFullscreenIfActive() {
  if (web.document.fullscreenElement != null) {
    web.document.exitFullscreen();
  }
}
