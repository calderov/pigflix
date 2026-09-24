import 'package:flutter/services.dart';

/// Light haptic tap played on every button press across the companion
/// app, so it feels a bit like pressing a physical remote control.
void tapHaptic() => HapticFeedback.lightImpact();
