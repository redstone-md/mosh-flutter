// Mount a screen with the app's localization, toast host and provider scope.
// Route-based tests import pump_route.dart explicitly.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/shared/toasts/toast_host.dart';

import 'pump_scope.dart';

/// Mounts [home] as the app's home screen and settles.
///
/// Pass provider [overrides] to control what the screen reads. Pass a
/// [container] instead when the test also reads providers itself; the
/// container's own overrides apply and [overrides] is ignored. Set
/// [settle] to false to get a single frame instead: some screens open a
/// dialog from a post-frame callback, and the test wants to drive those
/// frames itself.
Future<void> pumpScreen(
  WidgetTester tester,
  Widget home, {
  List<Override> overrides = const [],
  ProviderContainer? container,
  bool settle = true,
  List<NavigatorObserver> observers = const [],
}) =>
    pumpScopedApp(
      tester,
      MaterialApp(
        navigatorObservers: observers,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => ToastHost(child: child!),
        home: home,
      ),
      overrides: overrides,
      container: container,
      settle: settle,
    );
