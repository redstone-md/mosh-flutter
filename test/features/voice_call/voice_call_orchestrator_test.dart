// Real frame crypto with controlled capture callbacks and polling time.
// No native audio backend or real delay is needed for these contracts.
// ignore_for_file: constant_identifier_names

import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';

import 'package:flutter_test/flutter_test.dart';

import 'call_capture_config_cases.dart' as call_capture_config;
import 'record_voice_capture_cases.dart' as record_voice_capture;
import 'voice_capture_cases.dart' as voice_capture;
import 'voice_playback_cases.dart' as voice_playback;

import '../../support/scriptable_bridge.dart';
import 'package:mosh/src/features/voice_call/frame_codec.dart';
import 'package:mosh/src/features/voice_call/frame_crypto.dart';
import 'package:mosh/src/features/voice_call/voice_call_orchestrator.dart';
import 'package:mosh/src/features/voice_call/voice_capture.dart';
import 'package:mosh/src/features/voice_call/voice_playback.dart';

part 'voice_call_orchestrator_support.dart';

void main() {
  group('call_capture_config', call_capture_config.main);
  group('record_voice_capture', record_voice_capture.main);
  group('voice_capture', voice_capture.main);
  group('voice_playback', voice_playback.main);
  group('voice_call_orchestrator', () {
    test(
        'attach imports the call key and starts the poll',
        () => _withClock((clock) async {
              final gateway = ScriptableBridge();
              final orchestrator = _orchestrator();
              await orchestrator.attach(
                sessionId: 's',
                callId: 'c',
                keyB64: kKeyB64,
                noncePrefixB64: kNoncePrefixB64,
                direction: 'caller',
                bridge: gateway,
                captureFactory: const NoopVoiceCaptureFactory(),
                playbackFactory: const NoopVoicePlaybackFactory(),
                onError: (_) {},
                endCall: (_, __, ___) async {},
              );
              // Advance the production timer to its first poll.
              clock.elapse(kCallFramePollInterval);
              expect(gateway.countOf(BridgeMethod.callDrainFrames),
                  greaterThanOrEqualTo(1));
              await orchestrator.detach();
            }));

    test('toggleMute does not claim an unattached microphone is muted', () {
      final orchestrator = _orchestrator();
      expect(orchestrator.isMuted, isFalse);
      orchestrator.toggleMute();
      expect(orchestrator.isMuted, isFalse);
    });

    test(
        'a captured frame while muted is not sent, and is sent when unmuted',
        () => _withClock((clock) async {
              // Unmuted path.
              final gateway1 = ScriptableBridge();
              final capture1 = _FiringCaptureFactory([
                Uint8List.fromList([1, 2, 3])
              ]);
              final orchestrator1 = _orchestrator();
              await orchestrator1.attach(
                sessionId: 's',
                callId: 'c',
                keyB64: kKeyB64,
                noncePrefixB64: kNoncePrefixB64,
                direction: 'caller',
                bridge: gateway1,
                captureFactory: capture1,
                playbackFactory: _RecordingPlaybackFactory(),
                onError: (_) {},
                endCall: (_, __, ___) async {},
              );
              capture1.handle!.fire();
              clock.flushMicrotasks();
              expect(gateway1.countOf(BridgeMethod.callSendFrame), 1);
              final call = gateway1.lastCall(BridgeMethod.callSendFrame)!;
              expect(call.arg<String>('sessionId'), 's');
              expect(call.arg<String>('callId'), 'c');
              final key = await importCallKey(kKeyB64);
              final opened = await openFrame(
                  key,
                  kNoncePrefixB64,
                  gateway1
                      .argValues<Uint8List>(BridgeMethod.callSendFrame, 'frame')
                      .single);
              expect(opened, isNotNull);
              expect(opened!.seq & SEQ_VALUE_MASK, BigInt.zero);
              expect(opened.payload, Uint8List.fromList([1, 2, 3]));
              await orchestrator1.detach();

              // Muted path: choose mute before explicitly delivering the frame.
              final gateway2 = ScriptableBridge();
              final capture2 = _FiringCaptureFactory([
                Uint8List.fromList([1, 2, 3])
              ]);
              final orchestrator2 = _orchestrator();
              await orchestrator2.attach(
                sessionId: 's',
                callId: 'c',
                keyB64: kKeyB64,
                noncePrefixB64: kNoncePrefixB64,
                direction: 'caller',
                bridge: gateway2,
                captureFactory: capture2,
                playbackFactory: _RecordingPlaybackFactory(),
                onError: (_) {},
                endCall: (_, __, ___) async {},
              );
              orchestrator2.toggleMute();
              capture2.handle!.fire();
              clock.flushMicrotasks();
              expect(
                  gateway2.argValues<Uint8List>(
                      BridgeMethod.callSendFrame, 'frame'),
                  isEmpty);
              await orchestrator2.detach();
            }));

    // Keep concurrent capture, real crypto and its complete nonce proof together.
    // This existing multi-phase scenario is a test-body size exception.
    test(
        'seq increments per frame and the direction bit is applied',
        () => _withClock((clock) async {
              for (final direction in ['caller', 'callee']) {
                final gateway = ScriptableBridge();
                final capture = _FiringCaptureFactory([
                  Uint8List.fromList([10]),
                  Uint8List.fromList([20]),
                  Uint8List.fromList([30]),
                ]);
                final orchestrator = _orchestrator();
                await orchestrator.attach(
                  sessionId: 's',
                  callId: 'c',
                  keyB64: kKeyB64,
                  noncePrefixB64: kNoncePrefixB64,
                  direction: direction,
                  bridge: gateway,
                  captureFactory: capture,
                  playbackFactory: _RecordingPlaybackFactory(),
                  onError: (_) {},
                  endCall: (_, __, ___) async {},
                );
                // Deliver consecutive callbacks before crypto futures finish.
                capture.handle!.fire();
                clock.flushMicrotasks();
                expect(gateway.countOf(BridgeMethod.callSendFrame), 3);
                await orchestrator.detach();

                final key = await importCallKey(kKeyB64);
                final payloads = <BigInt, List<int>>{};
                final expectedHigh =
                    direction == 'callee' ? BigInt.one : BigInt.zero;
                for (final frame in gateway.argValues<Uint8List>(
                    BridgeMethod.callSendFrame, 'frame')) {
                  final opened = await openFrame(key, kNoncePrefixB64, frame);
                  expect(opened, isNotNull);
                  final seq = opened!.seq & SEQ_VALUE_MASK;
                  expect(payloads.containsKey(seq), isFalse,
                      reason:
                          'Consecutive callbacks must use distinct nonces.');
                  payloads[seq] = opened.payload;
                  expect(opened.seq >> 63, expectedHigh);
                }
                // Crypto completion may reorder writes; capture order owns seq.
                expect(payloads, {
                  BigInt.zero: [10],
                  BigInt.one: [20],
                  BigInt.two: [30],
                });
              }
            }));

    test(
        'drained frames surface reordered to playback',
        () => _withClock((clock) async {
              final gateway = ScriptableBridge();
              final playbackFactory = _RecordingPlaybackFactory();
              final key = await importCallKey(kKeyB64);
              // Seal frames for seqs [3,1,2] with payloads [30,10,20]; deliver them
              // raw through the bridge; the jitter
              // buffer must reorder to [1,2,3] -> payloads [10,20,30].
              final f1 = await sealFrame(key, kNoncePrefixB64, BigInt.one,
                  CALLER_DIRECTION_BIT, Uint8List.fromList([10]));
              final f2 = await sealFrame(key, kNoncePrefixB64, BigInt.two,
                  CALLER_DIRECTION_BIT, Uint8List.fromList([20]));
              final f3 = await sealFrame(key, kNoncePrefixB64, BigInt.from(3),
                  CALLER_DIRECTION_BIT, Uint8List.fromList([30]));
              gateway.seedCallFrames([f3, f1, f2]);
              final orchestrator = _orchestrator();
              await orchestrator.attach(
                sessionId: 's',
                callId: 'c',
                keyB64: kKeyB64,
                noncePrefixB64: kNoncePrefixB64,
                direction: 'caller',
                bridge: gateway,
                captureFactory: const NoopVoiceCaptureFactory(),
                playbackFactory: playbackFactory,
                onError: (_) {},
                endCall: (_, __, ___) async {},
              );
              // Advance the poll and flush the actual decrypt futures.
              clock.elapse(kCallFramePollInterval);
              final playback = playbackFactory.handle!;
              expect(playback.received.length, 3);
              expect(playback.received[0].seq, BigInt.one);
              expect(playback.received[0].payload, Uint8List.fromList([10]));
              expect(playback.received[1].seq, BigInt.two);
              expect(playback.received[1].payload, Uint8List.fromList([20]));
              expect(playback.received[2].seq, BigInt.from(3));
              expect(playback.received[2].payload, Uint8List.fromList([30]));
              await orchestrator.detach();
            }));

    test(
        'the draining guard drops a tick while a drain is in flight',
        () => _withClock((clock) async {
              final gateway = ScriptableBridge();
              final orchestrator = _orchestrator();
              await orchestrator.attach(
                sessionId: 's',
                callId: 'c',
                keyB64: kKeyB64,
                noncePrefixB64: kNoncePrefixB64,
                direction: 'caller',
                bridge: gateway,
                captureFactory: const NoopVoiceCaptureFactory(),
                playbackFactory: const NoopVoicePlaybackFactory(),
                onError: (_) {},
                endCall: (_, __, ___) async {},
              );
              // Seed a stall: the first drain grabs the completer and does not
              // resolve, so subsequent 20ms ticks must early-return (draining guard).
              gateway.hold(BridgeMethod.callDrainFrames);
              clock.elapse(kCallFramePollInterval * 3);
              expect(gateway.countOf(BridgeMethod.callDrainFrames), 1);
              // Complete the in-flight drain -> draining flips false -> next tick
              // fires another drain.
              gateway.release(BridgeMethod.callDrainFrames);
              clock.flushMicrotasks();
              clock.elapse(kCallFramePollInterval);
              expect(gateway.countOf(BridgeMethod.callDrainFrames),
                  greaterThan(1));
              await orchestrator.detach();
            }));

    test(
        'detach cancels the poll and stops capture/playback',
        () => _withClock((clock) async {
              final gateway = ScriptableBridge();
              final captureFactory = _RecordingCaptureFactory();
              final playbackFactory = _RecordingPlaybackFactory();
              final orchestrator = _orchestrator();
              await orchestrator.attach(
                sessionId: 's',
                callId: 'c',
                keyB64: kKeyB64,
                noncePrefixB64: kNoncePrefixB64,
                direction: 'caller',
                bridge: gateway,
                captureFactory: captureFactory,
                playbackFactory: playbackFactory,
                onError: (_) {},
                endCall: (_, __, ___) async {},
              );
              clock.elapse(kCallFramePollInterval);
              final before = gateway.countOf(BridgeMethod.callDrainFrames);
              expect(before, greaterThanOrEqualTo(1));
              await orchestrator.detach();
              expect(captureFactory.handle.stopped, isTrue);
              expect(playbackFactory.handle!.stopped, isTrue);
              clock.elapse(kCallFramePollInterval * 3);
              expect(gateway.countOf(BridgeMethod.callDrainFrames), before);
            }));

    test(
        'a capture onFrame firing after detach is a no-op',
        () => _withClock((clock) async {
              final gateway = ScriptableBridge();
              final capture = _FiringCaptureFactory([
                Uint8List.fromList([1, 2, 3])
              ]);
              final orchestrator = _orchestrator();
              await orchestrator.attach(
                sessionId: 's',
                callId: 'c',
                keyB64: kKeyB64,
                noncePrefixB64: kNoncePrefixB64,
                direction: 'caller',
                bridge: gateway,
                captureFactory: capture,
                playbackFactory: _RecordingPlaybackFactory(),
                onError: (_) {},
                endCall: (_, __, ___) async {},
              );
              // Deliver the already queued callback even after capture has stopped.
              await orchestrator.detach();
              expect(capture.handle!.stopped, isTrue);
              capture.handle!.fire();
              clock.flushMicrotasks();
              expect(
                  gateway.argValues<Uint8List>(
                      BridgeMethod.callSendFrame, 'frame'),
                  isEmpty);
            }));

    test('setup failure calls onError + endCall(setup_failed)', () async {
      final gateway = ScriptableBridge();
      final orchestrator = _orchestrator();
      String? errorMessage;
      String? endReason;
      await orchestrator.attach(
        sessionId: 's',
        callId: 'c',
        keyB64: kKeyB64,
        noncePrefixB64: kNoncePrefixB64,
        direction: 'caller',
        bridge: gateway,
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
