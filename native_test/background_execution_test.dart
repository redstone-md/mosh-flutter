import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:mosh/src/features/background/android_waiting_owner.dart';
import 'package:mosh/src/features/background/background_commands.dart';
import 'package:mosh/src/platform/android_waiting_platform.dart';
import 'package:mosh/src/rust/api/background/types.dart';
import 'package:mosh/src/rust/api/private_dm.dart' as setup;
import 'package:mosh/src/rust/frb_generated.dart';

Future<void> until(bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('Native background observation timed out');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  const channel = MethodChannel('app.mosh.mosh/waiting');
  setUpAll(() async {
    directory =
        await Directory.systemTemp.createTemp('mosh-background-bridge-');
    const overrideLibrary = String.fromEnvironment('MOSH_CORE_TEST_LIBRARY');
    final local = Platform.isWindows
        ? 'mosh_core.dll'
        : Platform.isMacOS
            ? 'libmosh_core.dylib'
            : 'libmosh_core.so';
    await RustLib.init(
        externalLibrary: ExternalLibrary.open(overrideLibrary.isEmpty
            ? 'mosh-core/target/debug/$local'
            : overrideLibrary));
    await setup.setAppDataDir(path: directory.path);
    await setup.setHistoryDek(dek: List.filled(32, 77));
  });
  tearDownAll(() async {
    RustLib.dispose();
    if (!Platform.isWindows) await directory.delete(recursive: true);
  });

  // Ordered tracer phases share one real installation/native singleton.
  test(
      'real bridge replaces/coalesces its hint subscriber and honors Android service loss',
      () async {
    final commands = BackgroundCommands();
    await commands.setExecution(interactive: true, waitingEnabled: false);
    final oldEvents = <BigInt>[], newEvents = <BigInt>[];
    final oldClosed = Completer<void>();
    final old =
        commands.changes().listen(oldEvents.add, onDone: oldClosed.complete);
    await until(() => oldEvents.isNotEmpty);
    final current = commands.changes().listen(newEvents.add);
    await oldClosed.future.timeout(const Duration(seconds: 20));
    await until(() => newEvents.isNotEmpty);
    for (var change = 0; change < 8; change++) {
      await commands.setExecution(interactive: true, waitingEnabled: false);
    }
    expect(newEvents, hasLength(1),
        reason: 'one outstanding hint, no unbounded event backlog');
    await commands.status();
    await commands.setExecution(interactive: false, waitingEnabled: false);
    await until(() => newEvents.length == 2);
    await old.cancel();
    final currentClosing = current.cancel();

    var revision = 1, intentRevision = 1;
    var interactive = true, enabled = false;
    final work = <Map<Object?, Object?>>[];
    Map<String, Object?> state() => {
          'revision': revision,
          'intentRevision': intentRevision,
          'interactive': interactive,
          'waitingEnabled': enabled,
          'serviceRunning': false,
          'setupComplete': true,
          'notificationsAllowed': true,
          'batteryExempt': false,
          'restriction': null,
        };
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      if (call.method == 'takeCallActions') return <Object?>[];
      if (call.method == 'setUserWork') {
        work.add(call.arguments as Map<Object?, Object?>);
      }
      return {...state(), 'revision': ++revision};
    });
    final platform = AndroidWaitingPlatform();
    final owner = AndroidWaitingOwner(platform, commands);
    addTearDown(() async {
      owner.dispose();
      platform.dispose();
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    });
    await owner.attach();
    await currentClosing;
    expect(owner.status!.actualMode, BackgroundMode.active);
    final unchanged = work.length;
    await owner.refresh();
    expect(work, hasLength(unchanged),
        reason: 'mirrored facts do not create a feedback loop');

    interactive = false;
    enabled = true; // Saved user choice survives a missing/destroyed service.
    intentRevision++;
    revision++;
    await binding.defaultBinaryMessenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec()
            .encodeMethodCall(MethodCall('waitingStateChanged', state())),
        (_) {});
    await owner.refresh();
    expect(platform.state!.waitingEnabled, true);
    expect(platform.state!.serviceRunning, false);
    expect(owner.status!.actualMode, BackgroundMode.offline);
    expect(work.last['intentRevision'], intentRevision);
    expect(work.last['actualMode'], 'offline');
    expect(owner.failure, isNull);
  });
}
