// Opens a start menu step the way a person does: the chat pane's start
// menu at /chat, then a tap on the step's card.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:mosh/src/gateway/bridge_facade.dart' show BridgeFacade;
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/state/gateway_provider.dart';

import 'pump.dart';
import 'scriptable_gateway.dart';

/// Pumps the app at the start menu on a desktop window and opens the step
/// whose card reads [title]. Pass [bridge] (and a [gateway] sharing its
/// conversations when the test follows a created conversation), or a
/// [container] that already overrides them.
Future<GoRouter> pumpStartStep(
  WidgetTester tester,
  String title, {
  BridgeFacade? bridge,
  ScriptableGateway? gateway,
  ProviderContainer? container,
}) async {
  tester.view
    ..physicalSize = const Size(1280, 900)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = await pumpRoute(
    tester,
    AppRoutes.chat,
    container: container,
    overrides: [
      if (bridge != null) bridgeFacadeProvider.overrideWithValue(bridge),
      gatewayProvider.overrideWithValue(gateway ?? ScriptableGateway()),
    ],
  );
  await tester.ensureVisible(find.text(title));
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
  return router;
}
