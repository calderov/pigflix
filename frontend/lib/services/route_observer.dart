import 'package:flutter/material.dart';

/// Registered on [MaterialApp.navigatorObservers] so screens can use
/// [RouteAware] to notice when they become visible again after the route
/// pushed on top of them is popped — e.g. re-broadcasting screen state to
/// the paired remote when the user (or a remote "back" command) navigates
/// back to an existing screen instance, which doesn't re-run [State.
/// initState].
final RouteObserver<PageRoute<dynamic>> routeObserver =
    RouteObserver<PageRoute<dynamic>>();
