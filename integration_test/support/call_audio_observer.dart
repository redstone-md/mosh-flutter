import 'dart:typed_data';

import 'package:mosh/src/features/voice_call/cpal_ringtone.dart';
import 'package:mosh/src/features/voice_call/process_call_window.dart';
import 'package:mosh/src/features/voice_call/call_window_coordinator.dart';
import 'package:mosh/src/features/voice_call/call_view_state.dart';
import 'package:mosh/src/features/voice_call/cpal_voice_playback.dart';
import 'package:mosh/src/features/voice_call/record_voice_capture.dart';
import 'package:mosh/src/features/voice_call/ringtone_player.dart';
import 'package:mosh/src/features/voice_call/voice_capture.dart';
import 'package:mosh/src/features/voice_call/voice_playback.dart';

/// Tracks completed audio operations. Defaults to Record and CPAL.
class CallAudioObserver {
  CallAudioObserver({
    VoiceCaptureFactory captureSource = const RecordVoiceCaptureFactory(),
    VoicePlaybackFactory playbackSource = const CpalVoicePlaybackFactory(),
  })  : _captureSource = captureSource,
        _playbackSource = playbackSource;

  final VoiceCaptureFactory _captureSource;
  final VoicePlaybackFactory _playbackSource;
  int captures = 0;
  int captureStops = 0;
  int players = 0;
  int playerStops = 0;
  int playedFrames = 0;
  int rings = 0;
  int ringStops = 0;
  int windows = 0;

  Future<CallWindowHandle> openWindow(
      Future<void> Function(CallViewCommand) onCommand) async {
    final handle = await ProcessCallWindow.open(onCommand);
    windows++;
    return _ObservedWindow(this, handle);
  }

  late final VoiceCaptureFactory capture = _CaptureFactory(this);
  late final VoicePlaybackFactory playback = _PlaybackFactory(this);
  late final RingtonePlayer ringtone = _Ringtone(this);
}

class _CaptureFactory implements VoiceCaptureFactory {
  _CaptureFactory(this.observer);
  final CallAudioObserver observer;
  @override
  bool get isSupported => observer._captureSource.isSupported;
  @override
  Future<VoiceCaptureHandle> start(void Function(Uint8List) onFrame) async {
    final handle = await observer._captureSource.start(onFrame);
    observer.captures++;
    return _CaptureHandle(observer, handle);
  }
}

class _CaptureHandle implements VoiceCaptureHandle {
  _CaptureHandle(this.observer, this.inner);
  final CallAudioObserver observer;
  final VoiceCaptureHandle inner;
  @override
  Future<void> stop() async {
    await inner.stop();
    observer.captureStops++;
  }
}

class _PlaybackFactory implements VoicePlaybackFactory {
  _PlaybackFactory(this.observer);
  final CallAudioObserver observer;
  @override
  Future<VoicePlaybackHandle> start() async {
    final handle = await observer._playbackSource.start();
    observer.players++;
    return _PlaybackHandle(observer, handle);
  }
}

class _PlaybackHandle implements VoicePlaybackHandle {
  _PlaybackHandle(this.observer, this.inner);
  final CallAudioObserver observer;
  final VoicePlaybackHandle inner;
  @override
  void pushFrame(BigInt seq, Uint8List opusFrame) {
    inner.pushFrame(seq, opusFrame);
    observer.playedFrames++;
  }

  @override
  Future<void> stop() async {
    await inner.stop();
    observer.playerStops++;
  }
}

class _Ringtone implements RingtonePlayer {
  _Ringtone(this.observer);
  final CallAudioObserver observer;
  @override
  RingtoneHandle start() {
    final handle = const CpalRingtonePlayer().start();
    observer.rings++;
    return _RingHandle(observer, handle);
  }
}

class _RingHandle implements RingtoneHandle {
  _RingHandle(this.observer, this.inner);
  final CallAudioObserver observer;
  final RingtoneHandle inner;
  @override
  void stop() {
    inner.stop();
    observer.ringStops++;
  }
}

class _ObservedWindow implements CallWindowHandle {
  _ObservedWindow(this.observer, this.inner);
  final CallAudioObserver observer;
  final CallWindowHandle inner;
  @override
  Future<void> present(CallViewState state) => inner.present(state);
  @override
  Future<void> show() => inner.show();
  @override
  Future<bool> isFocused() => inner.isFocused();
  @override
  Future<void> close() async {
    await inner.close();
    observer.windows--;
  }
}
