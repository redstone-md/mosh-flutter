import 'dart:async';
import 'dart:typed_data';

import 'package:mosh/src/features/voice_call/call_view_state.dart';
import 'package:mosh/src/features/voice_call/call_window_coordinator.dart';
import 'package:mosh/src/features/voice_call/ringtone_player.dart';
import 'package:mosh/src/features/voice_call/voice_capture.dart';
import 'package:mosh/src/features/voice_call/voice_playback.dart';

class RecordingCapture implements VoiceCaptureFactory {
  int starts = 0;
  int stops = 0;
  Completer<void>? stopping;
  @override
  bool get isSupported => true;
  @override
  Future<VoiceCaptureHandle> start(void Function(Uint8List) onFrame) async {
    starts++;
    return _Capture(() async {
      stops++;
      await stopping?.future;
    });
  }
}

class _Capture implements VoiceCaptureHandle {
  _Capture(this.onStop);
  final Future<void> Function() onStop;
  @override
  Future<void> stop() => onStop();
}

class RecordingPlayback implements VoicePlaybackFactory {
  int starts = 0;
  int stops = 0;
  int frames = 0;
  @override
  Future<VoicePlaybackHandle> start() async {
    starts++;
    return _Playback(() => stops++, () => frames++);
  }
}

class _Playback implements VoicePlaybackHandle {
  _Playback(this.onStop, this.onFrame);
  final void Function() onStop;
  final void Function() onFrame;
  @override
  void pushFrame(BigInt seq, Uint8List opusFrame) => onFrame();
  @override
  Future<void> stop() async => onStop();
}

class RecordingRingtone implements RingtonePlayer {
  int starts = 0;
  int stops = 0;
  @override
  RingtoneHandle start() {
    starts++;
    return _Ring(() => stops++);
  }
}

class _Ring implements RingtoneHandle {
  _Ring(this.onStop);
  final void Function() onStop;
  @override
  void stop() => onStop();
}

class RecordingCallWindow implements CallWindowHandle {
  final views = <CallViewState>[];
  int shows = 0;
  int closes = 0;
  @override
  Future<void> present(CallViewState state) async => views.add(state);
  @override
  Future<void> show() async => shows++;
  @override
  Future<bool> isFocused() async => false;
  @override
  Future<void> close() async => closes++;
}
