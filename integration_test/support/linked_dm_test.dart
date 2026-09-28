import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:mosh/main.dart' show LifecycleGate;
import 'package:mosh/src/platform/app_data_dir.dart';
import 'package:mosh/src/platform/mobile_dek.dart';
import 'package:mosh/src/rust/api/private_dm.dart' as setup;
import 'package:mosh/src/rust/frb_generated.dart';

import 'linked_dm_control.dart';
import 'linked_dm_scenario.dart';

void linkedDmTest({required bool android}) {
  testWidgets('linked DM survives process restart and retires the phone',
      (tester) async {
    tester.platformDispatcher.localeTestValue = const Locale('en');
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
    final control = LinkedDmControl(tester);
    addTearDown(control.close);
    await initRuntime(tester, android: android);
    try {
      final state = await control.ask('state');
      final flow = LinkedDmScenario(tester, control, state['session'] as String,
          state['fingerprint'] as String);
      if (state['phase'] == 'pair') {
        await flow.pair();
        await flow.live();
      } else {
        await flow.restore(state['phone'] as Map<String, dynamic>);
      }
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      RustLib.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 12)));
}

/// Keep physical startup on the app's foreground and Keystore boundaries.
Future<void> initRuntime(WidgetTester tester, {required bool android}) async {
  if (android) {
    expect(Platform.isAndroid, isTrue);
    await tester.runAsync(() async {
      await RustLib.init();
      await setAppDataDirBridge();
    });
    await tester.pumpWidget(const SizedBox.shrink());
    final gate = LifecycleGate();
    try {
      await tester.runAsync(() async {
        await gate.waitUntilResumed();
        await initMobileDek();
      });
    } finally {
      tester.binding.removeObserver(gate);
    }
    return;
  }
  const path = String.fromEnvironment('MOSH_TEST_DESKTOP_DIR');
  expect(path, isNotEmpty);
  final library = Platform.isWindows
      ? 'mosh_core.dll'
      : Platform.isMacOS
          ? 'libmosh_core.dylib'
          : 'libmosh_core.so';
  await tester.runAsync(() async {
    await RustLib.init(
        externalLibrary:
            ExternalLibrary.open('mosh-core/target/debug/$library'));
    await setup.setAppDataDir(path: path);
    // Test-only desktop counterpart of the real Android Keystore path.
    await setup.setHistoryDek(dek: List.filled(32, 93));
  });
}
