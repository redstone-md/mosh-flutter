// Seeded call states for the Figma "calls" area: a DM with Maya Chen whose
// call is pending, ringing or active, shown the way production shows it,
// through the native call owner in the main window.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/conversation/conversation_call_binding.dart'
    show conversationCallBindingProvider;
import 'package:mosh/src/features/voice_call/voice_call_binding.dart'
    show voiceCallBinding;
import 'package:mosh/src/platform/desktop_window_controller.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/rust/api/diagnostics.dart' show NativeRuntimeStatus;
import 'package:mosh/src/rust/native_call/types.dart' as native;
import 'package:mosh/src/rust/persistence.dart' show PersistenceRuntimeStatus;
import 'package:mosh/src/rust/outbound_delivery.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/native_call_owner_provider.dart';

import '../../../test/features/routing/shell_harness.dart';
import '../../../test/support/gateway_snapshots.dart';
import '../../../test/support/message_builders.dart';
import '../../../test/support/native_call_fixture.dart';
import '../../../test/support/scriptable_bridge.dart';
import '../../../test/support/scriptable_gateway.dart';
import 'harness.dart';

const callSession = 'maya';
const callId = 'walk';
const _me = 'Alex';
const _peer = 'Maya Chen';
final _time = DateTime(2026, 10, 3, 9, 41);

/// The main window, without its platform channel: with it the app is framed
/// as on desktop (the title bar stays above the open call) and the call host
/// behaves as there (incoming calls ring in the mini view, the expanded call
/// offers full screen). Windows, as the harness renders desktop scenes.
class _Window extends DesktopWindowController {
  _Window() : super(platform: TargetPlatform.windows);

  @override
  Future<void> setFullScreen(bool fullScreen) async =>
      fullScreen ? onWindowEnterFullScreen() : onWindowLeaveFullScreen();
}

/// The desktop's window; what its title bar asks of the platform goes
/// unanswered.
_Window _framed(WidgetTester tester) {
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
      DesktopWindowController.channel, (_) async => null);
  final window = _Window();
  addTearDown(() {
    window.dispose();
    messenger.setMockMethodCallHandler(DesktopWindowController.channel, null);
  });
  return window;
}

/// An active call that started four minutes ago.
ActiveCall activeCall() => TestCalls.active(
    callId: callId,
    startedAtMs: BigInt.from(DateTime.now()
        .subtract(const Duration(minutes: 4, seconds: 12))
        .millisecondsSinceEpoch));

const _inputs = [
  native.Device(id: 'usb-mic', name: 'USB Microphone', stable: true),
  native.Device(id: 'built-in-mic', name: 'Built-in Microphone', stable: true),
];
const _outputs = [
  native.Device(id: 'headphones', name: 'Studio Headphones', stable: true),
  native.Device(id: 'speakers', name: 'Built-in Speakers', stable: true),
];
const _cameras = [
  native.Device(id: 'hd-webcam', name: 'HD Webcam', stable: true),
  native.Device(id: 'built-in-cam', name: 'Built-in Camera', stable: true),
];
const _none = native.Surface(width: 0, height: 0);
const _hd = native.Surface(width: 1280, height: 720);

/// What the native engine reports about the call's media.
native.Snapshot callMedia(
        {bool ready = true,
        bool microphone = true,
        bool microphoneAvailable = true,
        bool camera = false,
        bool cameraFailed = false,
        bool remoteCamera = false,
        bool remoteFrames = false,
        bool reconnecting = false}) =>
    native.Snapshot(
        sessionId: callSession,
        callId: callId,
        ready: ready,
        microphone: microphone && microphoneAvailable,
        microphoneRequested: microphone,
        microphoneAvailable: microphoneAvailable,
        camera: camera,
        cameraRequested: camera,
        cameraStarting: false,
        cameraFailed: cameraFailed,
        remoteCamera: remoteCamera,
        reconnecting: reconnecting,
        failed: false,
        encoder: camera ? 'libvpx' : null,
        codec: camera ? 'VP8' : null,
        videoWidth: camera ? 1280 : 0,
        videoHeight: camera ? 720 : 0,
        videoFps: camera ? 30 : 0,
        packetsDropped: BigInt.zero,
        inputs: _inputs,
        outputs: _outputs,
        cameras: _cameras,
        input: 'usb-mic',
        output: 'headphones',
        localVideo: camera ? _hd : _none,
        remoteVideo: remoteFrames ? _hd : _none);

ChatMessage _text(int minute, bool mine, String body) => TestMessages.dm(
    fromDevice: mine ? _me : _peer,
    body: body,
    messageId: 'm$minute',
    sentAtMs: BigInt.from(
        _time.add(Duration(minutes: minute)).millisecondsSinceEpoch),
    deliveryStatus: MessageDeliveryStatus.sent,
    read: mine);

ChatMessage _call(int minute, bool mine, String kind, int seconds) =>
    TestMessages.dm(
        fromDevice: mine ? _me : _peer,
        body: '',
        messageId: 'c$minute',
        sentAtMs: BigInt.from(
            _time.add(Duration(minutes: minute)).millisecondsSinceEpoch),
        callEvent: CallEvent(
            kind: kind,
            durationMs: BigInt.from(seconds * 1000),
            callId: 'call-$minute'),
        deliveryStatus: MessageDeliveryStatus.sent,
        read: mine);

/// Maya's history: a few lines of chat and one call of every outcome.
final List<ChatMessage> callHistory = [
  _text(0, false, 'Coffee after the walk?'),
  _text(1, true, 'Absolutely. Riverside at 10?'),
  _call(2, false, 'missed', 0),
  _call(3, true, 'completed', 754),
  _text(20, false, 'Thanks, the route sounds lovely.'),
  _call(30, true, 'missed', 0),
  _call(31, false, 'completed', 95),
  _call(40, true, 'update_required', 0),
  _text(41, false, 'See you by the bridge!'),
];

ScriptableGateway _gateway(
        {PendingCall? pending,
        OutgoingCall? outgoing,
        ActiveCall? active,
        CallAvailability? availability}) =>
    ScriptableGateway()
      ..seedSessions([
        TestSnapshots.dm(
            sessionId: callSession,
            displayName: _me,
            peerDisplayName: _peer,
            callAvailability: availability,
            pendingCall: pending,
            outgoingCall: outgoing,
            activeCall: active,
            messages: callHistory),
        TestSnapshots.dm(
            sessionId: 'leo',
            displayName: _me,
            peerDisplayName: 'Leo Park',
            messages: [
              TestMessages.dm(
                  fromDevice: 'Leo Park', body: 'Thanks for the photos!')
            ]),
      ]);

/// The canned runtime with history persistence running, as in a real
/// install (the fake's default warns that history is not saved).
NativeRuntimeStatus _savingHistory() {
  final canned = cannedNativeRuntimeStatus();
  return NativeRuntimeStatus(
      moss: canned.moss,
      secureStorage: canned.secureStorage,
      persistence: const PersistenceRuntimeStatus(
          backend: 'redb+aes-256-gcm+os-keychain',
          database: 'mosh.redb',
          available: true,
          encryptedAtRest: true),
      openmlsSmoke: canned.openmlsSmoke,
      openmlsRoundtrip: canned.openmlsRoundtrip);
}

/// Mounts the real shell at [location] (Maya's DM by default) with the
/// given call. [media] is what
/// every snapshot read returns (the engine's polls are answered [polls]
/// times, then go quiet so the frame settles). [script] scripts the bridge
/// before mounting, e.g. to fail audio setup; [extra] adds providers.
Future<void> openCall(WidgetTester tester, Size size,
    {PendingCall? pending,
    OutgoingCall? outgoing,
    ActiveCall? active,
    CallAvailability? availability,
    native.Snapshot? media,
    String? location,
    void Function(ScriptableBridge bridge)? script,
    List<Override> extra = const [],
    int polls = 30}) async {
  final gateway = _gateway(
      pending: pending,
      outgoing: outgoing,
      active: active,
      availability: availability);
  final bridge = ScriptableBridge(conversations: gateway.conversations)
    ..seedNativeRuntimeStatus(_savingHistory());
  for (var i = 0; i < polls; i++) {
    bridge.respondNext(
        BridgeMethod.nativeCallSnapshot, Future.value(media ?? callMedia()));
  }
  script?.call(bridge);
  mockCallVideoPlugin(tester);
  final window = size == FigmaDevice.desktop.size ? _framed(tester) : null;
  await pumpShellApp(tester,
      gateway: gateway,
      bridge: bridge,
      physical: size,
      windowController: window,
      location: location ?? AppRoutes.dmFor(callSession),
      overrides: [
        ...figmaLocale,
        conversationCallBindingProvider.overrideWithValue(voiceCallBinding),
        // As in production the owner lives with the app, so unmounting the
        // tree stops its media polling.
        nativeCallOwnerProvider.overrideWith((ref) {
          final owner = NativeCallOwner(bridge, () async => true);
          ref.onDispose(owner.dispose);
          return owner;
        }),
        if (window != null)
          desktopWindowControllerProvider.overrideWithValue(window),
        ...extra,
      ]);
  await settleCall(tester);
}

/// Lets media binding, the video textures and the call surface finish.
Future<void> settleCall(WidgetTester tester) async {
  await tester
      .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
}

/// Taps the control with [tooltip] and lets the call surface settle.
Future<void> tapCall(WidgetTester tester, String tooltip) async {
  await tester.tap(find.byTooltip(tooltip).last);
  await tester.pump();
  await settleCall(tester);
}
