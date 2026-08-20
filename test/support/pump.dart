// The frame every widget test mounts a screen in: a Riverpod scope, a
// MaterialApp that speaks the app's languages, and a settle so the async
// providers have resolved before the first expect.
//
// Two entry points, because a screen reaches the tester in two ways:
// `pumpScreen` puts a widget straight into `MaterialApp.home`, and
// `pumpRoute` starts the real app router at a location so `context.go`
// has somewhere to go.
//
// Anything one test needs on top -- a wrapper widget, a surface size, a
// helper that also types into a field -- stays in that test and calls one
// of these. This is the frame, not a framework.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/routing/app_router.dart';

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
}) =>
    _pump(
      tester,
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
      overrides: overrides,
      container: container,
      settle: settle,
    );

/// Mounts the app's routes at [location] and settles.
///
/// Use this when the screen navigates: the routes come from [appRouter],
/// so `context.go(...)` lands on the same screens the app ships. The
/// router is returned so a test can read where it ended up; it is a fresh
/// one per pump, so tests do not leak a location into each other.
Future<GoRouter> pumpRoute(
  WidgetTester tester,
  String location, {
  List<Override> overrides = const [],
  ProviderContainer? container,
  bool settle = true,
}) async {
  final router = GoRouter(
    initialLocation: location,
    routes: appRouter.configuration.routes,
  );
  await _pump(
    tester,
    MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
    overrides: overrides,
    container: container,
    settle: settle,
  );
  return router;
}

Future<void> _pump(
  WidgetTester tester,
  Widget app, {
  required List<Override> overrides,
  required ProviderContainer? container,
  required bool settle,
}) async {
  await tester.pumpWidget(
    container == null
        ? ProviderScope(overrides: overrides, child: app)
        : UncontrolledProviderScope(container: container, child: app),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}
