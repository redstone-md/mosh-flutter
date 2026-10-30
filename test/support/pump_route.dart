// Mount the real app routes; screen-only tests need not load this graph.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/shared/toasts/toast_host.dart';
import 'package:mosh/src/routing/app_router.dart';

import 'pump_scope.dart';

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
  TransitionBuilder? builder,
}) async {
  final router = GoRouter(
    initialLocation: location,
    routes: appRouter.configuration.routes,
  );
  await pumpScopedApp(
    tester,
    MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
      builder: (context, child) =>
          ToastHost(child: builder?.call(context, child) ?? child!),
    ),
    overrides: overrides,
    container: container,
    settle: settle,
  );
  return router;
}
