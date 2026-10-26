import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/lock/android_app_access.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  test('a stale read cannot uncover a newer expired access state', () async {
    final read = Completer<Object?>();
    messenger.setMockMethodCallHandler(
        AndroidAppAccess.channel, (_) => read.future);
    final access = AndroidAppAccess();
    final initialization = access.initialize();
    await _event(_state(phase: 'locked', revision: 5));
    read.complete(_state(phase: 'interactive', revision: 1));
    await initialization;
    expect(access.covered, true);
    access.dispose();
  });

  test('a call-only frame retains grace; only visible chats end the absence',
      () async {
    var storedPhase = 'grace';
    var revision = 0;
    messenger.setMockMethodCallHandler(AndroidAppAccess.channel, (call) async {
      if (call.method == 'saveAccessState') {
        storedPhase = (call.arguments as Map)['state'] as String;
      }
      return _state(phase: storedPhase, revision: ++revision);
    });
    final access = AndroidAppAccess();
    await access.initialize();
    await access.protectedFrameReady();
    expect(storedPhase, 'grace');
    await _event(_state(phase: 'grace', revision: ++revision));
    await access.protectedFrameReady();
    expect(storedPhase, 'grace',
        reason: 'a background event is no chat interaction');
    access.setChatVisible(true);
    await access.protectedFrameReady();
    expect(storedPhase, 'interactive');
    access.dispose();
  });

  test('native call-only entry covers valid grace and acknowledges no chats',
      () async {
    final acknowledgements = <Map<Object?, Object?>>[];
    var writes = 0;
    messenger.setMockMethodCallHandler(AndroidAppAccess.channel, (call) async {
      if (call.method == 'protectedFrameReady') {
        acknowledgements.add(call.arguments as Map<Object?, Object?>);
        return null;
      }
      if (call.method == 'saveAccessState') writes++;
      return {..._state(phase: 'grace', revision: 1), 'callOnly': true};
    });
    final access = AndroidAppAccess();
    addTearDown(access.dispose);
    await access.initialize();
    access.setChatVisible(true);
    expect(access.covered, true);
    expect(access.chatsInteractive, false);
    await access.protectedFrameReady();
    expect(acknowledgements.single['chatsVisible'], false);
    expect(writes, 0);
    expect(access.state!.state, 'grace');
    expect(access.state!.deadlineElapsedMs, 61000);
  });

  test('unreadable state and refused writes keep access covered', () async {
    messenger.setMockMethodCallHandler(AndroidAppAccess.channel,
        (_) async => throw PlatformException(code: 'ACCESS_STATE_UNAVAILABLE'));
    final access = AndroidAppAccess();
    await access.initialize();
    expect(access.covered, true);
    expect(access.failed, true);
    messenger.setMockMethodCallHandler(AndroidAppAccess.channel,
        (_) async => _state(phase: 'interactive', revision: 1));
    await access.refresh();
    expect(access.covered, false);
    messenger.setMockMethodCallHandler(AndroidAppAccess.channel,
        (_) async => throw PlatformException(code: 'ACCESS_STATE_UNAVAILABLE'));
    await expectLater(access.setDelay(300), throwsA(isA<PlatformException>()));
    expect(access.covered, true);
    access.dispose();
  });

  test('returning to chats cannot undo an in-flight lock-delay change',
      () async {
    final firstSave = Completer<void>();
    var delay = 60;
    var phase = 'grace';
    var revision = 0;
    var saves = 0;
    messenger.setMockMethodCallHandler(AndroidAppAccess.channel, (call) async {
      if (call.method == 'protectedFrameReady') return null;
      if (call.method == 'saveAccessState') {
        final value = call.arguments as Map;
        delay = value['delaySeconds'] as int;
        phase = value['state'] as String;
      }
      final response = {
        ..._state(phase: phase, revision: ++revision),
        'delaySeconds': delay,
      };
      if (call.method == 'saveAccessState' && ++saves == 1) {
        await firstSave.future;
      }
      return response;
    });
    final access = AndroidAppAccess();
    addTearDown(access.dispose);
    await access.initialize();
    access.setChatVisible(true);
    final change = access.setDelay(300);
    await Future<void>.delayed(Duration.zero);
    final visibleFrame = access.protectedFrameReady();
    await Future<void>.delayed(Duration.zero);
    firstSave.complete();
    await Future.wait([change, visibleFrame]);
    await access.refresh();
    expect(access.delaySeconds, 300);
    expect(access.state!.state, 'interactive');
  });

  tearDown(
      () => messenger.setMockMethodCallHandler(AndroidAppAccess.channel, null));
}

Map<String, Object?> _state({required String phase, required int revision}) => {
      'version': 1,
      'delaySeconds': 60,
      'bootCount': 5,
      'deadlineElapsedMs': phase == 'grace' ? 61000 : null,
      'state': phase,
      'elapsedRealtimeMs': 1000,
      'allowed': phase != 'locked',
      'revision': revision,
      'shieldGeneration': 1,
      'deviceInteractive': true,
    };

Future<void> _event(Map<String, Object?> state) async {
  final reply = Completer<ByteData?>();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
          AndroidAppAccess.channel.name,
          const StandardMethodCodec()
              .encodeMethodCall(MethodCall('accessStateChanged', state)),
          reply.complete);
  await reply.future;
}
