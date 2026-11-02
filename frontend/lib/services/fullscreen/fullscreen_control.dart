// Platform-agnostic fullscreen control for the player screen.
//
// `dart.library.js_interop` is the Dart-team-recommended condition for
// telling a web compile target apart from a native one (the older
// `dart.library.html` check is wrong under dart2wasm) — see the
// `package:web` migration docs.
export 'fullscreen_control_desktop.dart'
    if (dart.library.js_interop) 'fullscreen_control_web.dart';
