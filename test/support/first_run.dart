import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/main.dart';
import 'package:mosh/src/features/device_link/device_link_provider.dart';
import 'package:mosh/src/features/onboarding/first_run_profile.dart';
import 'package:mosh/src/features/onboarding/first_run_provider.dart';
import 'package:mosh/src/platform/desktop_app_relauncher.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/state/gateway_provider.dart';

import 'scriptable_bridge.dart';
import 'scriptable_device_link.dart';
import 'scriptable_gateway.dart';

class MemoryFirstRunStore extends FirstRunStore {
  MemoryFirstRunStore([this.profile]) : super(null);
  FirstRunProfile? profile;
  Object? readError;
  Object? writeError;

  @override
  Future<FirstRunProfile?> read() async {
    if (readError != null) throw readError!;
    return profile;
  }

  @override
  Future<void> write(FirstRunProfile profile) async {
    if (writeError != null) throw writeError!;
    this.profile = profile;
  }
}

/// The real app and enabled gate, with only disk and native seams replaced.
class FirstRunHarness {
  FirstRunHarness(
      {FirstRunProfile? profile,
      ScriptableBridge? bridge,
      ScriptableDeviceLink? link})
      : store = MemoryFirstRunStore(profile),
        bridge = bridge ?? ScriptableBridge(),
        link = link ?? ScriptableDeviceLink();

  final MemoryFirstRunStore store;
  final ScriptableBridge bridge;
  ScriptableDeviceLink link;
  late ProviderContainer container;

  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(1200, 850),
    double scale = 1,
    DesktopAppRelauncher? relauncher,
    bool settle = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    container = ProviderContainer(retry: (_, __) => null, overrides: [
      firstRunEnabledProvider.overrideWithValue(true),
      firstRunStoreProvider.overrideWithValue(store),
      bridgeFacadeProvider.overrideWithValue(bridge),
      gatewayProvider.overrideWithValue(
          ScriptableGateway(conversations: bridge.conversations)),
      deviceLinkProvider.overrideWith(() {
        link = ScriptableDeviceLink(snapshot: link.current)
          ..buildError = link.buildError
          ..actionError = link.actionError
          ..snapshotAfterCancel = link.snapshotAfterCancel;
        return link;
      }),
    ]);
    addTearDown(container.dispose);
    appRouter.go(AppRoutes.sessions);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: RepaintBoundary(
            key: const ValueKey('setup-preview'),
            child: MoshApp(relauncher: relauncher))));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }
}

Future<void> tapSetup(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}
