import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/state/rail_layout_provider.dart';
import 'package:mosh/src/state/gateway_provider.dart';

import 'gateway_snapshots.dart';
import 'pump.dart';
import 'scriptable_bridge.dart';
import 'scriptable_gateway.dart';

/// The chat list layout kept in memory instead of the app data directory.
class MemoryRailLayoutStore extends RailLayoutStore {
  MemoryRailLayoutStore([this.saved]) : super(null);

  RailLayout? saved;
  int writes = 0;

  @override
  RailLayout read() => saved ?? const RailLayout();

  @override
  Future<void> write(RailLayout layout) async {
    writes++;
    saved = layout;
  }
}

/// Mounts the app at the chat list on a [size] window, with one channel
/// per name in [channels] so the rail has rows. The layout lives in
/// [store], a fresh empty one by default; [seed] adds what else the
/// bridge should serve.
Future<GoRouter> pumpRail(
  WidgetTester tester, {
  Size size = const Size(1200, 850),
  List<String> channels = const ['general'],
  MemoryRailLayoutStore? store,
  void Function(ScriptableBridge bridge)? seed,
  List<Override> overrides = const [],
}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final gateway = ScriptableGateway();
  final bridge = ScriptableBridge(conversations: gateway.conversations)
    ..seedChannels(
        [for (final name in channels) cannedChannelSnapshot(name: name)]);
  seed?.call(bridge);
  return pumpRoute(tester, AppRoutes.sessions, overrides: [
    gatewayProvider.overrideWithValue(gateway),
    bridgeFacadeProvider.overrideWithValue(bridge),
    railLayoutStoreProvider.overrideWithValue(store ?? MemoryRailLayoutStore()),
    ...overrides,
  ]);
}
