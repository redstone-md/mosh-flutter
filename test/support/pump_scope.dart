import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

/// Shared scope and frame completion for direct screens and routed apps.
Future<void> pumpScopedApp(
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
