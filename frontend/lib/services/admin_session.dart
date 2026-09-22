import 'package:flutter/foundation.dart';

/// App-wide admin-mode flag, toggled via the lock button on the movie grid
/// screen after a successful password check against the backend. This is
/// purely a client-side UI gate (e.g. showing the "Fix match" button) — it
/// does not restrict any backend endpoint.
class AdminSession {
  AdminSession._();

  static final ValueNotifier<bool> isAdmin = ValueNotifier(false);
}
