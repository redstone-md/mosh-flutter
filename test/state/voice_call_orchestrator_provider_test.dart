// Step-5 tests for the voice-call orchestrator provider -- the Riverpod
// mirror of React use-voice-call-orchestration's useEffect dep array. Each
// test wires a ProviderContainer that overrides activeSessionProvider with
// a mutable controller, gatewayProvider with a recording Gateway, and the
// capture/playback factories + error sink with recording fakes. The
// orchestrator's attach is fire-and-forget (async); a listen(...) keeps the
// provider alive so it rebuilds when the watched async provider resolves,
// and assertions wait a microtask so the recording handles' start resolves.
library;

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/dm/voice_capture.dart';
import 'package:mosh/src/features/dm/voice_playback.dart';
import '../support/scriptable_gateway.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/gateway_provider.dart' show gatewayProvider;
import 'package:mosh/src/state/session_providers.dart'
    show activeSessionProvider;
import 'package:mosh/src/state/voice_call_orchestrator_provider.dart';

/// A mutable controller the activeSessionProvider override reads from. Tests
/// mutate `snapshot` then invalidate the session so the orchestrator re-runs
/// build (mirrors the React effect re-running on a dep change).
class _SessionController {
  _SessionController(this.snapshot);
  SessionSnapshot? snapshot;
}

SessionSnapshot _session(String sessionId, {ActiveCall? activeCall}) =>
    SessionSnapshot(
      sessionId: sessionId,
      meshId: 'm',
      role: 'caller',
      displayName: 'me',
      peerDisplayName: 'Alice',
      state: 'ready',
      path: 'direct',
      relayReady: null,
      inviteUri: null,
      fingerprint: 'AA',
      messages: const [],
      attachments: const [],
      mesh: null,
      events: const [],
      pendingCall: null,
      outgoingCall: null,
      activeCall: activeCall,
    );

ActiveCall _activeCall(String callId) => ActiveCall(
      callId: callId,
      direction: 'caller',
      keyB64: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=', // 32 zero bytes
      noncePrefixB64: 'AAAAAA==', // 4 zero bytes
      startedAtMs: BigInt.zero,
    );

/// A capture handle that records its stop() call.
class _RecordingCaptureHandle implements VoiceCaptureHandle {
  int stopCalls = 0;
  @override
  Future<void> stop() async {
    stopCalls++;
  }
}

/// A capture factory that records each start() (count + last handle) so a
/// test can assert the orchestrator attached and re-attached.
class _RecordingCaptureFactory implements VoiceCaptureFactory {
  int startCalls = 0;
  _RecordingCaptureHandle? lastHandle;
  @override
  bool get isSupported => true;
  @override
  Future<VoiceCaptureHandle> start(void Function(Uint8List opusFrame) onFrame) {
    startCalls++;
    final h = _RecordingCaptureHandle();
    lastHandle = h;
    return Future.value(h);
  }
}

/// A capture factory whose start() throws -- drives attach's catch branch
/// so endCall fires (the setup-failure seam).
class _FailingCaptureFactory implements VoiceCaptureFactory {
  _FailingCaptureFactory(this.error);
  final Object error;
  @override
  bool get isSupported => true;
  @override
  Future<VoiceCaptureHandle> start(void Function(Uint8List opusFrame) onFrame) {
    throw error;
  }
}

/// A recording playback handle: records its stop() call.
class _RecordingPlaybackHandle implements VoicePlaybackHandle {
  int stopCalls = 0;
  @override
  void pushFrame(BigInt seq, Uint8List opusFrame) {}
  @override
  Future<void> stop() async {
    stopCalls++;
  }
}

/// A playback factory that records each start() (count + last handle).
class _RecordingPlaybackFactory implements VoicePlaybackFactory {
  int startCalls = 0;
  @override
  Future<VoicePlaybackHandle> start() {
    startCalls++;
    return Future.value(_RecordingPlaybackHandle());
  }
}

/// Builds a ProviderContainer with the orchestrator's full override set.
/// The session controller seeds activeSessionProvider; the recording
/// gateway + factories + error sink are injected for assertions.
ProviderContainer _container({
  required _SessionController controller,
  required ScriptableGateway gateway,
  VoiceCaptureFactory? captureFactory,
  VoicePlaybackFactory? playbackFactory,
  void Function(String? message)? errorSink,
}) {
  return ProviderContainer(overrides: [
    activeSessionProvider('sess-1')
        .overrideWith((ref) => Future.value(controller.snapshot)),
    gatewayProvider.overrideWithValue(gateway),
    voiceCaptureFactoryProvider
        .overrideWithValue(captureFactory ?? const NoopVoiceCaptureFactory()),
    voicePlaybackFactoryProvider
        .overrideWithValue(playbackFactory ?? const NoopVoicePlaybackFactory()),
    voiceCallErrorSinkProvider.overrideWithValue(errorSink ?? (_) {}),
  ]);
}

/// Subscribes to the orchestrator provider so it stays alive + rebuilds when
/// the watched activeSessionProvider resolves (a one-shot read wouldn't).
ProviderSubscription _subscribe(ProviderContainer c) =>
    c.listen(voiceCallOrchestratorProvider('sess-1'), (_, __) {},
        fireImmediately: true);

void main() {
  group('voice_call_orchestrator_provider', () {
    test('no ActiveCall -> no orchestrator, muted false', () async {
      final gateway = ScriptableGateway();
      final controller = _SessionController(_session('sess-1'));
      final container = _container(controller: controller, gateway: gateway);
      addTearDown(container.dispose);

      final sub = _subscribe(container);
      addTearDown(sub.close);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(
          container.read(voiceCallOrchestratorProvider('sess-1')).muted, false);
    });

    test('an ActiveCall appears -> attach runs (capture/playback start)',
        () async {
      final gateway = ScriptableGateway();
      final controller =
          _SessionController(_session('sess-1', activeCall: _activeCall('a')));
      final capture = _RecordingCaptureFactory();
      final playback = _RecordingPlaybackFactory();
      final container = _container(
        controller: controller,
        gateway: gateway,
        captureFactory: capture,
        playbackFactory: playback,
      );
      addTearDown(container.dispose);

      final sub = _subscribe(container);
      addTearDown(sub.close);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(capture.startCalls, 1);
      expect(playback.startCalls, 1);
    });

    test('toggling mute updates state and the orchestrator flag', () async {
      final gateway = ScriptableGateway();
      final controller =
          _SessionController(_session('sess-1', activeCall: _activeCall('a')));
      final container = _container(controller: controller, gateway: gateway);
      addTearDown(container.dispose);

      final sub = _subscribe(container);
      addTearDown(sub.close);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      container
          .read(voiceCallOrchestratorProvider('sess-1').notifier)
          .toggleMute();
      expect(
          container.read(voiceCallOrchestratorProvider('sess-1')).muted, true);
      container
          .read(voiceCallOrchestratorProvider('sess-1').notifier)
          .toggleMute();
      expect(
          container.read(voiceCallOrchestratorProvider('sess-1')).muted, false);
    });

    test('a new ActiveCall (different callId) re-attaches (old detached)',
        () async {
      final gateway = ScriptableGateway();
      final controller =
          _SessionController(_session('sess-1', activeCall: _activeCall('a')));
      final capture = _RecordingCaptureFactory();
      final playback = _RecordingPlaybackFactory();
      final container = _container(
        controller: controller,
        gateway: gateway,
        captureFactory: capture,
        playbackFactory: playback,
      );
      addTearDown(container.dispose);

      final sub = _subscribe(container);
      addTearDown(sub.close);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(capture.startCalls, 1);
      final firstHandle = capture.lastHandle;

      // Change the ActiveCall to a new callId, invalidate the session so the
      // orchestrator re-runs build (mirrors the React effect re-running on a
      // dep change), then wait for the new attach.
      controller.snapshot = _session('sess-1', activeCall: _activeCall('b'));
      container.invalidate(activeSessionProvider('sess-1'));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(capture.startCalls, 2);
      expect(firstHandle!.stopCalls, 1);
    });

    test('ActiveCall disappears -> orchestrator detached (handle stopped)',
        () async {
      final gateway = ScriptableGateway();
      final controller =
          _SessionController(_session('sess-1', activeCall: _activeCall('a')));
      final capture = _RecordingCaptureFactory();
      final playback = _RecordingPlaybackFactory();
      final container = _container(
        controller: controller,
        gateway: gateway,
        captureFactory: capture,
        playbackFactory: playback,
      );
      addTearDown(container.dispose);

      final sub = _subscribe(container);
      addTearDown(sub.close);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(capture.startCalls, 1);
      final firstHandle = capture.lastHandle;

      controller.snapshot = _session('sess-1');
      container.invalidate(activeSessionProvider('sess-1'));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(firstHandle!.stopCalls, 1);
    });

    test('endCall callback calls gateway.callEnd + surfaces error', () async {
      final gateway = ScriptableGateway();
      final controller =
          _SessionController(_session('sess-1', activeCall: _activeCall('a')));
      final capture = _FailingCaptureFactory('boom');
      final playback = _RecordingPlaybackFactory();
      final errors = <String?>[];
      final container = _container(
        controller: controller,
        gateway: gateway,
        captureFactory: capture,
        playbackFactory: playback,
        errorSink: errors.add,
      );
      addTearDown(container.dispose);

      final sub = _subscribe(container);
      addTearDown(sub.close);
      // attach's catch -> onError + endCall -> gateway.callEnd; the failing
      // capture.start throws after importCallKey + playback start resolve,
      // so wait long enough for the async chain to settle.
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(errors, isNotEmpty);
      expect(gateway.countOf(GatewayMethod.callEnd), 1);
      expect(gateway.lastCall(GatewayMethod.callEnd)?.arg<String>('sessionId'),
          'sess-1');
      expect(
          gateway.lastCall(GatewayMethod.callEnd)?.arg<String>('callId'), 'a');
      expect(gateway.lastCall(GatewayMethod.callEnd)?.arg<String>('reason'),
          'setup_failed');
    });
  });
}
