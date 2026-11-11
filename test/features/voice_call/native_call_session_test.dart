import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/voice_call/native_call_session.dart';
import 'package:mosh/src/rust/native_call/types.dart' as native;
import 'package:mosh/src/state/native_call_owner_provider.dart';
import '../../support/scriptable_bridge.dart';
import '../../support/native_call_fixture.dart';

void main() {
  test(
      'active native bind requests microphone before consent is reflected in inventory',
      () async {
    final bridge = ScriptableBridge();
    bridge.respondNext(BridgeMethod.nativeCallSnapshot,
        Future.value(nativeCallSnapshot(microphoneRequested: true)));
    var prompts = 0;
    final owner = NativeCallOwner(bridge, () async {
      prompts++;
      return true;
    });
    await owner.bind('dm', 'call', active: true);
    expect(prompts, 1);
    final choice = bridge.lastCall(BridgeMethod.nativeCallChoices)!;
    expect(choice.arg<bool>('microphone'), true);
    expect(choice.arg<bool>('microphoneAllowed'), true);
    await owner.bind('dm', 'call', active: true);
    expect(prompts, 1);
    owner.dispose();
  });

  test('preview does not request microphone; denied microphone keeps camera',
      () async {
    final bridge = ScriptableBridge();
    var prompts = 0;
    final session = _session(bridge, permission: () async {
      prompts++;
      return false;
    });
    await session.start(camera: true);
    expect(prompts, 0);
    expect(bridge.lastCall(BridgeMethod.nativeCallPrepare)!.arg<bool>('camera'),
        true);
    await session.confirm();
    expect(prompts, 1);
    final choices = bridge.lastCall(BridgeMethod.nativeCallChoices)!;
    expect(choices.arg<bool>('microphone'), false);
    expect(choices.arg<bool>('microphoneAllowed'), false);
    expect(choices.arg<bool>('camera'), true);
    session.stop();
    expect(bridge.countOf(BridgeMethod.callEnd), 0);
  });

  test(
      'explicit mute and camera survive selection alias and repeated confirmation',
      () async {
    final bridge = ScriptableBridge();
    var prompts = 0;
    final session = _session(bridge, permission: () async {
      prompts++;
      return true;
    });
    await session.start(camera: true);
    await session.toggleMicrophone();
    session.rebind('canonical');
    await session.confirm();
    await session.confirm();
    expect(prompts, 0);
    expect(session.muted, true);
    await session.selectOutput('speaker');
    expect(
        bridge.lastCall(BridgeMethod.nativeCallChoices)!.arg<String>('callId'),
        'canonical');
    expect(bridge.lastCall(BridgeMethod.nativeCallChoices)!.arg<bool>('camera'),
        true);
    session.stop();
  });

  test('closing during permission prompt prevents late capture command',
      () async {
    final bridge = ScriptableBridge();
    final permission = Completer<bool>();
    final session = _session(bridge, permission: () => permission.future);
    await session.start();
    final confirmation = session.confirm();
    await Future<void>.delayed(Duration.zero);
    session.stop();
    permission.complete(true);
    await confirmation;
    expect(bridge.countOf(BridgeMethod.nativeCallChoices), 0);
  });

  testWidgets('a late snapshot after canonical selection is discarded',
      (tester) async {
    final bridge = ScriptableBridge();
    final session = _session(bridge);
    await session.start();
    final waiting = Completer<native.Snapshot?>();
    bridge.respondNext(BridgeMethod.nativeCallSnapshot, waiting.future);
    await tester.pump(const Duration(milliseconds: 100));
    session.rebind('canonical');
    waiting.complete(nativeCallSnapshot());
    await tester.pump();
    expect(session.snapshot, isNull);
    session.stop();
  });

  test('failed obsolete bind retains current presentation session', () async {
    final bridge = ScriptableBridge();
    final owner = NativeCallOwner(bridge, () async => false);
    await owner.bind('dm', 'call');
    final current = owner.session;
    bridge.failNext(BridgeMethod.nativeCallPrepare);
    await expectLater(owner.bind('dm', 'obsolete'), throwsException);
    expect(owner.session, same(current));
    await owner.session!.toggleCamera();
    expect(
        bridge.lastCall(BridgeMethod.nativeCallChoices)!.arg<String>('callId'),
        'call');
    owner.dispose();
  });

  test('overlapping failed binds retain a working presentation client',
      () async {
    final bridge = ScriptableBridge();
    final owner = NativeCallOwner(bridge, () async => false);
    await owner.bind('dm', 'call');
    final current = owner.session;
    final first = Completer<void>();
    final second = Completer<void>();
    bridge.respondNext(BridgeMethod.nativeCallPrepare, first.future);
    final firstFailure =
        expectLater(owner.bind('dm', 'first'), throwsException);
    bridge.respondNext(BridgeMethod.nativeCallPrepare, second.future);
    final secondFailure =
        expectLater(owner.bind('dm', 'second'), throwsException);
    first.completeError(Exception('first failed'));
    await firstFailure;
    second.completeError(Exception('second failed'));
    await secondFailure;
    expect(owner.session, same(current));
    await owner.session!.toggleCamera();
    expect(bridge.countOf(BridgeMethod.nativeCallChoices), 1);
    expect(
        bridge.lastCall(BridgeMethod.nativeCallChoices)!.arg<String>('callId'),
        'call');
    owner.dispose();
  });

  test('late obsolete preparation cannot replace the working client', () async {
    final bridge = ScriptableBridge();
    final owner = NativeCallOwner(bridge, () async => false);
    await owner.bind('dm', 'call');
    final waiting = Completer<void>();
    bridge.respondNext(BridgeMethod.nativeCallPrepare, waiting.future);
    final obsolete = owner.bind('dm', 'obsolete');
    await owner.bind('dm', 'current');
    final current = owner.session;
    waiting.complete();
    await obsolete;
    expect(owner.session, same(current));
    await current!.toggleCamera();
    expect(
        bridge.lastCall(BridgeMethod.nativeCallChoices)!.arg<String>('callId'),
        'current');
    owner.dispose();
  });

  testWidgets('unbind during preparation prevents a late presentation client',
      (tester) async {
    mockCallVideoPlugin(tester);
    final bridge = ScriptableBridge();
    final owner = NativeCallOwner(bridge, () async => false);
    await owner.bind('dm', 'call');
    final waiting = Completer<void>();
    bridge.respondNext(BridgeMethod.nativeCallPrepare, waiting.future);
    final preparing = owner.bind('dm', 'replacement');
    owner.unbind('dm', 'replacement');
    waiting.complete();
    await preparing;
    await tester.pump(const Duration(milliseconds: 200));
    expect(owner.session, isNull);
    expect(
        bridge
            .callsTo(BridgeMethod.nativeCallSnapshot)
            .where((call) => call.arg<String>('callId') == 'replacement'),
        isEmpty);
    owner.dispose();
  });

  test(
      'owner preserves an alias, repeats camera choice once and ignores stale unbind',
      () async {
    final bridge = ScriptableBridge();
    final owner = NativeCallOwner(bridge, () async => true);
    await owner.bind('dm', 'call');
    final first = owner.session;
    await owner.bind('dm', 'canonical',
        superseded: 'call', video: true, active: true);
    await owner.bind('dm', 'canonical', video: true, active: true);
    expect(owner.session, same(first));
    expect(bridge.countOf(BridgeMethod.nativeCallPrepare), 1);
    expect(owner.session!.cameraRequested, true);
    owner.unbind('dm', 'call');
    expect(owner.session, same(first));
    await owner.session!.selectInput('mic');
    await owner.session!.selectCamera('camera');
    expect(
        bridge
            .lastCall(BridgeMethod.nativeCallChoices)!
            .arg<String>('cameraId'),
        'camera');
    owner.unbind('dm', 'canonical');
    expect(owner.session, isNull);
    owner.dispose();
  });

  testWidgets('snapshot polling survives a read error', (tester) async {
    final bridge = ScriptableBridge();
    final session = _session(bridge);
    await session.start();
    bridge.failNext(BridgeMethod.nativeCallSnapshot);
    await tester.pump(const Duration(milliseconds: 100));
    bridge.respondNext(BridgeMethod.nativeCallSnapshot,
        Future.value(nativeCallSnapshot(camera: true)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(session.snapshot?.camera, true);
    session.stop();
    await tester.pump(const Duration(seconds: 1));
  });

  test(
      'Android media authorization precedes capture and refuses late promotion',
      () async {
    final bridge = ScriptableBridge();
    final promotion = Completer<bool>();
    final owner = NativeCallOwner(bridge, () async => true,
        authorizeMedia: (microphone, camera) => promotion.future);
    await owner.bind('dm', 'call');
    final active = owner.bind('dm', 'call', active: true);
    await Future<void>.delayed(Duration.zero);
    expect(bridge.countOf(BridgeMethod.nativeCallChoices), 0);
    owner.unbind('dm', 'call');
    promotion.complete(true);
    await active;
    expect(bridge.countOf(BridgeMethod.nativeCallChoices), 0);
    owner.dispose();
  });

  test('Android refused camera service never opens native preview', () async {
    final bridge = ScriptableBridge();
    final owner = NativeCallOwner(bridge, () async => true,
        requestCamera: () async => true,
        authorizeMedia: (microphone, camera) async => false);
    await expectLater(owner.bind('dm', 'call', video: true), throwsStateError);
    expect(bridge.countOf(BridgeMethod.nativeCallPrepare), 0);
    expect(owner.session, isNull);
    owner.dispose();
  });

  test('a press shows on the button while native media still applies it',
      () async {
    final bridge = ScriptableBridge();
    final shown = Completer<void>();
    late final NativeCallSession session;
    session = _session(bridge, onState: () {
      if (session.muted && session.cameraRequested && !shown.isCompleted) {
        shown.complete();
      }
    });
    await session.start();
    await session.toggleMicrophone();
    final applying = Completer<void>();
    bridge.respondNext(BridgeMethod.nativeCallChoices, applying.future);
    final pressed = session.toggleCamera();
    await shown.future;
    applying.complete();
    await pressed;
    expect(session.muted, true);
    session.stop();
  });

  test('camera failure reconciles choice before immediate retry', () async {
    final bridge = ScriptableBridge();
    final session = _session(bridge);
    await session.start();
    bridge.respondNext(BridgeMethod.nativeCallSnapshot,
        Future.value(nativeCallSnapshot(cameraFailed: true)));
    await session.toggleCamera();
    expect(session.cameraRequested, false);
    await session.toggleCamera();
    expect(bridge.lastCall(BridgeMethod.nativeCallChoices)!.arg<bool>('camera'),
        true);
    session.stop();
  });
}

NativeCallSession _session(ScriptableBridge bridge,
        {Future<bool> Function()? permission, void Function()? onState}) =>
    NativeCallSession(
        sessionId: 'dm',
        callId: 'call',
        bridge: bridge,
        requestMicrophone: permission ?? () async => false,
        onState: onState ?? () {});
