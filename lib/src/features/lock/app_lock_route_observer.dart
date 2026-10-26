import 'dart:async';
import 'package:flutter/material.dart';

final appLockRouteObserver = AppLockRouteObserver();
const callAccessRoute = 'mosh/call-controls';

/// Protected popups cannot remain above the locked chat shell. Call controls can.
class AppLockRouteObserver extends NavigatorObserver {
  final _routes = <Route<Object?>>[];
  bool _locked = false;

  void setLocked(bool locked) {
    _locked = locked;
    if (locked) _discardProtectedPopups();
  }

  void _discardProtectedPopups() {
    for (final route in List.of(_routes).reversed) {
      if (route is PopupRoute &&
          route.settings.name != callAccessRoute &&
          route.isActive) {
        navigator?.removeRoute(route);
      }
    }
  }

  @override
  void didPush(Route<Object?> route, Route<Object?>? previousRoute) {
    _routes.add(route);
    if (_locked &&
        route is PopupRoute &&
        route.settings.name != callAccessRoute) {
      // Navigator is locked during didPush; discard before a rendered frame.
      scheduleMicrotask(() {
        if (_locked) _discardProtectedPopups();
      });
    }
  }

  @override
  void didPop(Route<Object?> route, Route<Object?>? previousRoute) =>
      _routes.remove(route);
  @override
  void didRemove(Route<Object?> route, Route<Object?>? previousRoute) =>
      _routes.remove(route);
  @override
  void didReplace({Route<Object?>? newRoute, Route<Object?>? oldRoute}) {
    _routes.remove(oldRoute);
    if (newRoute != null) _routes.add(newRoute);
  }
}
