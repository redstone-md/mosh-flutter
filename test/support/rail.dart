import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/state/gateway_provider.dart';

import 'gateway_snapshots.dart';
import 'pump.dart';
import 'scriptable_bridge.dart';
import 'scriptable_gateway.dart';

/// Mounts the app at the chat list on a [size] window, with one channel
/// per name in [channels] so the rail has rows.
Future<GoRouter> pumpRail(
  WidgetTester tester, {
  Size size = const Size(1200, 850),
  List<String> channels = const ['general'],
  List<Override> overrides = const [],
}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final gateway = ScriptableGateway();
  final bridge = ScriptableBridge(conversations: gateway.conversations)
    ..seedChannels(
        [for (final name in channels) cannedChannelSnapshot(name: name)]);
  return pumpRoute(tester, AppRoutes.sessions, overrides: [
    gatewayProvider.overrideWithValue(gateway),
    bridgeFacadeProvider.overrideWithValue(bridge),
    ...overrides,
  ]);
}
