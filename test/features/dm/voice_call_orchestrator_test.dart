// Parity tests for VoiceCallOrchestrator -- the 1:1 port of React
// use-voice-call-orchestration's useEffect pump. Each test drives the
// orchestrator with Noop / recording / firing capture + playback factories
// and a recording transport over a recording Gateway, so the React
// effect's full surface (cancelled windows, draining guard, seq
// snapshot+inc, jitter reorder, setup-failure -> endCall) is exercised
// without any native audio backend. Real Future.delayed matches the
// repo convention; the crypto futures (sealFrame/openFrame) use real
// microtask scheduling that fake_async would not speed up here.
// ignore_for_file: constant_identifier_names

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/dm/call_frame_transport.dart';
import 'package:mosh/src/features/dm/frame_codec.dart';
import 'package:mosh/src/features/dm/frame_crypto.dart';
import 'package:mosh/src/features/dm/voice_call_orchestrator.dart';
import 'package:mosh/src/features/dm/voice_capture.dart';
import 'package:mosh/src/features/dm/voice_playback.dart';
import 'package:mosh/src/gateway/gateway.dart' show Gateway;

const String KEY_B64 = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='; // 32 zero bytes
const String PREFIX_B64 = 'AAAAAA=='; // 4 zero bytes

/// Minimal recording Gateway: only callSendFrame / callDrainFrames / callEnd
/// are exercised; the rest throw UnimplementedError so any other call
/// surface surfaces loudly in the test. drainCompleter lets a test stall
/// the poll (the draining-guard test) instead of resolving immediately.
class _RecordingGateway implements Gateway {
  final List<({String sessionId, String callId, Uint8List frame})> sent = [];
  int drainCalls = 0;
  List<Uint8List> drainReturn = const [];
  Completer<List<Uint8List>>? drainCompleter;
  int endCalls = 0;
  String? lastEndReason;

  @override
  Future<void> callSendFrame({
    required String sessionId,
    required String callId,
    required Uint8List frame,
  }) async {
    sent.add((sessionId: sessionId, callId: callId, frame: frame));
  }

  @override
  Future<List<Uint8List>> callDrainFrames({
    required String sessionId,
    required String callId,
  }) async {
    drainCalls++;
    final c = drainCompleter;
    if (c != null) return c.future;
    return drainReturn;
  }

  @override
  Future<void> callEnd({
    required String sessionId,
    required String callId,
    required String reason,
  }) async {
    endCalls++;
    lastEndReason = reason;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(' ${invocation.memberName}');
}

/// A capture handle that records its `stop()` call.
class _RecordingCaptureHandle implements VoiceCaptureHandle {
  bool stopped = false;
  @override
  Future<void> stop() async {
    stopped = true;
  }
}

/// A capture factory that never fires onFrame (mirrors NoopVoiceCaptureFactory
/// but with a recording handle so detach's stop() is observable).
class _RecordingCaptureFactory implements VoiceCaptureFactory {
  late _RecordingCaptureHandle handle;
  @override
  bool get isSupported => true;
  @override
  Future<VoiceCaptureHandle> start(void Function(Uint8List opusFrame) onFrame) async {
    handle = _RecordingCaptureHandle();
    return handle;
  }
}

/// A capture handle that fires a queued frame via a Timer and records stop.
class _FiringCaptureHandle implements VoiceCaptureHandle {
  _FiringCaptureHandle(this._onFrame, this._frames);
  final void Function(Uint8List) _onFrame;
  final List<Uint8List> _frames;
  Timer? _timer;
  int _i = 0;
  bool stopped = false;

  void start() {
    _scheduleNext();
  }

  void _scheduleNext() {
    if (_i >= _frames.length) return;
    _timer = Timer(const Duration(milliseconds: 30), () {
      if (stopped) return;
      _onFrame(_frames[_i]);
      _i++;
      _scheduleNext();
    });
  }

  @override
  Future<void> stop() async {
    stopped = true;
    _timer?.cancel();
    _timer = null;
  }
}

/// A capture factory that fires `frames` on a 30ms cadence after start()
/// returns, so tests can toggle mute / detach in between ticks. The handle
/// is exposed for stop() observability.
class _FiringCaptureFactory implements VoiceCaptureFactory {
  _FiringCaptureFactory(this._frames);
  final List<Uint8List> _frames;
  _FiringCaptureHandle? handle;
  @override
  bool get isSupported => true;
  @override
  Future<VoiceCaptureHandle> start(void Function(Uint8List opusFrame) onFrame) async {
    final h = _FiringCaptureHandle(onFrame, _frames);
    handle = h;
    h.start();
    return h;
  }
}

/// A recording playback handle: records pushed frames + the stop() call.
class _RecordingPlaybackHandle implements VoicePlaybackHandle {
  final List<({BigInt seq, Uint8List payload})> received = [];
  bool stopped = false;
  @override
  void pushFrame(BigInt seq, Uint8List opusFrame) {
    received.add((seq: seq, payload: Uint8List.fromList(opusFrame)));
  }
  @override
  Future<void> stop() async {
    stopped = true;
  }
}

/// A playback factory returning a recording handle (exposed for assertions).
class _RecordingPlaybackFactory implements VoicePlaybackFactory {
  _RecordingPlaybackHandle? handle;
  @override
  Future<VoicePlaybackHandle> start() async {
    handle = _RecordingPlaybackHandle();
    return handle!;
  }
}

/// A playback factory whose start() throws -- drives attach's catch branch.
class _FailingPlaybackFactory implements VoicePlaybackFactory {
  final Object error;
  _FailingPlaybackFactory(this.error);
  @override
  Future<VoicePlaybackHandle> start() async {
    throw error;
  }
}

/// Wires up a fresh orchestrator for an attach() call.
VoiceCallOrchestrator _orchestrator() => VoiceCallOrchestrator();

void main() {
  group('voice_call_orchestrator', () {
    test('attach imports the call key and starts the poll', () async {
      final gateway = _RecordingGateway();
      final transport = CallFrameTransport(gateway);
      final orchestrator = _orchestrator();
      await orchestrator.attach(
        sessionId: 's',
        callId: 'c',
        keyB64: KEY_B64,
        noncePrefixB64: PREFIX_B64,
        direction: 'caller',
        transport: transport,
        captureFactory: const NoopVoiceCaptureFactory(),
        playbackFactory: const NoopVoicePlaybackFactory(),
        onError: (_) {},
        endCall: (_, __, ___) async {},
      );
      // 60ms > the 20ms poll interval, so at least one tick has fired.
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(gateway.drainCalls, greaterThanOrEqualTo(1));
      await orchestrator.detach();
    });

    test('toggleMute flips isMuted', () {
      final orchestrator = _orchestrator();
      expect(orchestrator.isMuted, isFalse);
      orchestrator.toggleMute();
      expect(orchestrator.isMuted, isTrue);
      orchestrator.toggleMute();
      expect(orchestrator.isMuted, isFalse);
    });

    test('a captured frame while muted is not sent, and is sent when unmuted', () async {
      // Unmuted path.
      final gateway1 = _RecordingGateway();
      final transport1 = CallFrameTransport(gateway1);
      final capture1 = _FiringCaptureFactory([Uint8List.fromList([1, 2, 3])]);
      final orchestrator1 = _orchestrator();
      await orchestrator1.attach(
        sessionId: 's',
        callId: 'c',
        keyB64: KEY_B64,
        noncePrefixB64: PREFIX_B64,
        direction: 'caller',
        transport: transport1,
        captureFactory: capture1,
        playbackFactory: _RecordingPlaybackFactory(),
        onError: (_) {},
        endCall: (_, __, ___) async {},
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(gateway1.sent.length, 1);
      final key = await importCallKey(KEY_B64);
      final opened = await openFrame(key, PREFIX_B64, gateway1.sent.single.frame);
      expect(opened, isNotNull);
      expect(opened!.seq & SEQ_VALUE_MASK, BigInt.zero);
      expect(opened.payload, Uint8List.fromList([1, 2, 3]));
      await orchestrator1.detach();

      // Muted path: toggleMute before the 30ms frame fires.
      final gateway2 = _RecordingGateway();
      final transport2 = CallFrameTransport(gateway2);
      final capture2 = _FiringCaptureFactory([Uint8List.fromList([1, 2, 3])]);
      final orchestrator2 = _orchestrator();
      await orchestrator2.attach(
        sessionId: 's',
        callId: 'c',
        keyB64: KEY_B64,
        noncePrefixB64: PREFIX_B64,
        direction: 'caller',
        transport: transport2,
        captureFactory: capture2,
        playbackFactory: _RecordingPlaybackFactory(),
        onError: (_) {},
        endCall: (_, __, ___) async {},
      );
      orchestrator2.toggleMute();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(gateway2.sent, isEmpty);
      await orchestrator2.detach();
    });

    test('seq increments per frame and the direction bit is applied', () async {
      for (final direction in ['caller', 'callee']) {
        final gateway = _RecordingGateway();
        final transport = CallFrameTransport(gateway);
        final capture = _FiringCaptureFactory([
          Uint8List.fromList([10]),
          Uint8List.fromList([20]),
          Uint8List.fromList([30]),
        ]);
        final orchestrator = _orchestrator();
        await orchestrator.attach(
          sessionId: 's',
          callId: 'c',
          keyB64: KEY_B64,
          noncePrefixB64: PREFIX_B64,
          direction: direction,
          transport: transport,
          captureFactory: capture,
          playbackFactory: _RecordingPlaybackFactory(),
          onError: (_) {},
          endCall: (_, __, ___) async {},
        );
        // 3 frames at 30ms cadence -> ~90ms+, plus a margin.
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(gateway.sent.length, 3);
        await orchestrator.detach();

        final key = await importCallKey(KEY_B64);
        final seqs = <BigInt>[];
        final highBits = <BigInt>[];
        for (final entry in gateway.sent) {
          final opened = await openFrame(key, PREFIX_B64, entry.frame);
          expect(opened, isNotNull);
          seqs.add(opened!.seq & SEQ_VALUE_MASK);
          highBits.add(opened.seq >> 63);
        }
        expect(seqs, [BigInt.zero, BigInt.one, BigInt.two]);
        final expectedHigh =
            direction == 'callee' ? BigInt.one : BigInt.zero;
        expect(highBits, [expectedHigh, expectedHigh, expectedHigh]);
      }
    });

    test('drained frames surface reordered to playback', () async {
      final gateway = _RecordingGateway();
      final transport = CallFrameTransport(gateway);
      final playbackFactory = _RecordingPlaybackFactory();
      final key = await importCallKey(KEY_B64);
      // Seal frames for seqs [3,1,2] with payloads [30,10,20]; deliver them
      // raw (the transport base64-encodes for drainCallFrames); the jitter
      // buffer must reorder to [1,2,3] -> payloads [10,20,30].
      final f1 = await sealFrame(key, PREFIX_B64, BigInt.one, CALLER_DIRECTION_BIT, Uint8List.fromList([10]));
      final f2 = await sealFrame(key, PREFIX_B64, BigInt.two, CALLER_DIRECTION_BIT, Uint8List.fromList([20]));
      final f3 = await sealFrame(key, PREFIX_B64, BigInt.from(3), CALLER_DIRECTION_BIT, Uint8List.fromList([30]));
      gateway.drainReturn = [f3, f1, f2];
      final orchestrator = _orchestrator();
      await orchestrator.attach(
        sessionId: 's',
        callId: 'c',
        keyB64: KEY_B64,
        noncePrefixB64: PREFIX_B64,
        direction: 'caller',
        transport: transport,
        captureFactory: const NoopVoiceCaptureFactory(),
        playbackFactory: playbackFactory,
        onError: (_) {},
        endCall: (_, __, ___) async {},
      );
      // 60ms lets the 20ms poll fire at least once with the seeded frames.
      await Future<void>.delayed(const Duration(milliseconds: 60));
      final playback = playbackFactory.handle!;
      expect(playback.received.length, 3);
      expect(playback.received[0].seq, BigInt.one);
      expect(playback.received[0].payload, Uint8List.fromList([10]));
      expect(playback.received[1].seq, BigInt.two);
      expect(playback.received[1].payload, Uint8List.fromList([20]));
      expect(playback.received[2].seq, BigInt.from(3));
      expect(playback.received[2].payload, Uint8List.fromList([30]));
      await orchestrator.detach();
    });

    test('the draining guard drops a tick while a drain is in flight', () async {
      final gateway = _RecordingGateway();
      final transport = CallFrameTransport(gateway);
      final orchestrator = _orchestrator();
      await orchestrator.attach(
        sessionId: 's',
        callId: 'c',
        keyB64: KEY_B64,
        noncePrefixB64: PREFIX_B64,
        direction: 'caller',
        transport: transport,
        captureFactory: const NoopVoiceCaptureFactory(),
        playbackFactory: const NoopVoicePlaybackFactory(),
        onError: (_) {},
        endCall: (_, __, ___) async {},
      );
      // Seed a stall: the first drain grabs the completer and does not
      // resolve, so subsequent 20ms ticks must early-return (draining guard).
      gateway.drainCompleter = Completer<List<Uint8List>>();
      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(gateway.drainCalls, 1);
      // Complete the in-flight drain -> draining flips false -> next tick
      // fires another drain.
      gateway.drainCompleter!.complete(<Uint8List>[]);
      gateway.drainCompleter = null;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(gateway.drainCalls, greaterThan(1));
      await orchestrator.detach();
    });

    test('detach cancels the poll and stops capture/playback', () async {
      final gateway = _RecordingGateway();
      final transport = CallFrameTransport(gateway);
      final captureFactory = _RecordingCaptureFactory();
      final playbackFactory = _RecordingPlaybackFactory();
      final orchestrator = _orchestrator();
      await orchestrator.attach(
        sessionId: 's',
        callId: 'c',
        keyB64: KEY_B64,
        noncePrefixB64: PREFIX_B64,
        direction: 'caller',
        transport: transport,
        captureFactory: captureFactory,
        playbackFactory: playbackFactory,
        onError: (_) {},
        endCall: (_, __, ___) async {},
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final before = gateway.drainCalls;
      expect(before, greaterThanOrEqualTo(1));
      await orchestrator.detach();
      expect(captureFactory.handle.stopped, isTrue);
      expect(playbackFactory.handle!.stopped, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(gateway.drainCalls, before);
    });

    test('a capture onFrame firing after detach is a no-op', () async {
      final gateway = _RecordingGateway();
      final transport = CallFrameTransport(gateway);
      final capture = _FiringCaptureFactory([Uint8List.fromList([1, 2, 3])]);
      final orchestrator = _orchestrator();
      await orchestrator.attach(
        sessionId: 's',
        callId: 'c',
        keyB64: KEY_B64,
        noncePrefixB64: PREFIX_B64,
        direction: 'caller',
        transport: transport,
        captureFactory: capture,
        playbackFactory: _RecordingPlaybackFactory(),
        onError: (_) {},
        endCall: (_, __, ___) async {},
      );
      // Detach immediately; the factory's 30ms frame tick fires later but
      // _cancelled is true so onFrame is a no-op.
      await orchestrator.detach();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(gateway.sent, isEmpty);
    });

    test('setup failure calls onError + endCall(setup_failed)', () async {
      final gateway = _RecordingGateway();
      final transport = CallFrameTransport(gateway);
      final orchestrator = _orchestrator();
      String? errorMessage;
      String? endReason;
      await orchestrator.attach(
        sessionId: 's',
        callId: 'c',
        keyB64: KEY_B64,
        noncePrefixB64: PREFIX_B64,
        direction: 'caller',
        transport: transport,
        captureFactory: const NoopVoiceCaptureFactory(),
        playbackFactory: _FailingPlaybackFactory(Exception('boom')),
        onError: (msg) => errorMessage = msg,
        endCall: (_, __, reason) async => endReason = reason,
      );
      expect(errorMessage, isNotNull);
      expect(errorMessage, contains('boom'));
      expect(endReason, kSetupFailedReason);
    });
  });
}
