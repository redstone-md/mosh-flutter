import 'dart:async' show StreamSubscription, Timer, unawaited;
import 'dart:convert' show base64Encode;
import 'dart:io' show Directory, File;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:mosh/src/features/shared/voice_composer_types.dart';
import 'package:path_provider/path_provider.dart'
    show getApplicationCacheDirectory;
import 'package:record/record.dart';

/// Where a recording is: not started, capturing, or paused with everything
/// said so far in one finished clip.
enum VoiceRecordingPhase { idle, recording, paused }

/// One voice recording from the first press of the microphone to its send
/// or its cancel. It owns the recorder, the clock and the files; the
/// composer draws [phase] and calls the actions.
///
/// A pause closes the file, so that the pause can be listened to, and a
/// resume starts another; [join] makes the two one clip again. At rest
/// there is therefore at most one finished clip, [clip].
class VoiceRecording extends ChangeNotifier {
  VoiceRecording({
    required this.inputDeviceId,
    required this.join,
    required this.canCapture,
    required this.onPermissionDenied,
    required this.onError,
  });

  /// The stored input-device pick; null is the platform default.
  final String? Function() inputDeviceId;
  final VoiceSegmentJoin join;

  /// Whether the composer is on screen: a hidden one must not leave the
  /// microphone capturing unattended.
  final bool Function() canCapture;
  final VoidCallback onPermissionDenied;
  final void Function(Object error) onError;

  static const _mime = 'audio/mp4';

  final AudioRecorder _recorder = AudioRecorder();
  VoiceRecordingPhase _phase = VoiceRecordingPhase.idle;
  late final _VoiceMeter _meter = _VoiceMeter(onTick: _onTick);
  // The finished clip, and the meter's reading when it was closed: what a
  // piece that cannot be joined falls back to.
  final _VoiceFiles _files = _VoiceFiles();
  _MeterReading _clipReading = _VoiceMeter.zero;
  // One recorder transition at a time: a cancel racing a pause would
  // delete the file the pause is still closing.
  bool _busy = false;
  bool _disposed = false;

  VoiceRecordingPhase get phase => _phase;

  /// How much has been recorded, pauses left out.
  Duration get elapsed => _meter.elapsed;

  /// The finished clip of a paused recording, to listen to.
  String? get clip => _files.clip;

  /// The waveform of the recording so far.
  Uint8List get peaks => voiceWaveform(_meter.levels);

  /// Whether an action is still closing or joining files.
  bool get busy => _busy;

  /// Whether a paused recording has room to go on.
  bool get canResume =>
      _phase == VoiceRecordingPhase.paused && elapsed < maxRecording;

  /// Asks for the microphone and starts capturing.
  Future<void> start() => _exclusive(() async {
        if (_phase != VoiceRecordingPhase.idle) return;
        // Ask at the moment of intent: `record`'s start() never requests
        // the microphone on its own, so hasPermission() is the only gate.
        final allowed = await _recorder.hasPermission();
        if (_disposed) return;
        if (!allowed) return onPermissionDenied();
        if (!canCapture()) return;
        _meter.rewind(_VoiceMeter.zero);
        await _capture();
      });

  /// Closes what was said so far into [clip].
  Future<void> pause() => _exclusive(() async {
        if (_phase != VoiceRecordingPhase.recording) return;
        await _close();
        _set(VoiceRecordingPhase.paused);
      });

  /// Goes on recording after a pause.
  Future<void> resume() => _exclusive(() async {
        if (canResume && canCapture()) await _capture();
      });

  /// Throws the recording away.
  Future<void> cancel() => _exclusive(() async {
        if (_phase == VoiceRecordingPhase.idle) return;
        await _discard();
        _set(VoiceRecordingPhase.idle);
      });

  /// Ends the recording and hands it over; null when there is nothing to
  /// send. The clip's file is the caller's from here on.
  Future<VoiceSend?> finish() async {
    VoiceSend? voice;
    await _exclusive(() async {
      // A last piece that could not be joined is not sent short of it.
      if (_phase == VoiceRecordingPhase.recording && !await _close()) {
        return _set(VoiceRecordingPhase.paused);
      }
      final path = _files.release();
      if (path == null) return;
      voice = VoiceSend(
        path: path,
        mime: _mime,
        durationMs: elapsed.inMilliseconds,
        peaksBase64: base64Encode(peaks),
      );
      _set(VoiceRecordingPhase.idle);
    });
    return voice;
  }

  @override
  void dispose() {
    _disposed = true;
    _meter.stop();
    unawaited(_recorder.dispose());
    _files.deleteAll();
    super.dispose();
  }

  /// Runs one recorder transition; a second one asked for meanwhile is
  /// dropped. A failure ends the recording and is reported.
  Future<void> _exclusive(Future<void> Function() transition) async {
    if (_busy || _disposed) return;
    _busy = true;
    _notify();
    try {
      await transition();
    } catch (error) {
      await _abort(error);
    } finally {
      _busy = false;
      // A transition that outlived the composer leaves no file behind.
      if (_disposed) _files.deleteAll();
      _notify();
    }
  }

  /// Starts a new file and the clock. A composer that went out of sight
  /// while the recorder was starting is paused at once.
  Future<void> _capture() async {
    final path = _files.live = await newVoiceClipPath();
    // The stored input pick (audio-devices.json); null = platform default.
    // The label is cosmetic on the platform side, so the id doubles as it.
    final picked = inputDeviceId();
    await _recorder.start(
      RecordConfig(
        encoder: AudioEncoder.aacLc,
        device: picked == null ? null : InputDevice(id: picked, label: picked),
      ),
      path: path,
    );
    _meter.start(_recorder);
    _set(VoiceRecordingPhase.recording);
    if (!canCapture()) {
      await _close();
      _set(VoiceRecordingPhase.paused);
    }
  }

  void _onTick() {
    _notify();
    // The longest recording pauses itself, to be listened to or sent.
    if (elapsed >= maxRecording) unawaited(pause());
  }

  /// Stops the capture and adds its file to [clip]; false when the piece
  /// could not be joined: it is told and dropped, what was paused stays.
  Future<bool> _close() async {
    _meter.stop();
    final segment = await _recorder.stop() ?? _files.live;
    var joined = true;
    try {
      await _files.close(segment, join);
    } catch (error) {
      joined = false;
      _meter.rewind(_clipReading);
      if (!_disposed) onError(error);
    }
    _clipReading = _meter.reading;
    return joined;
  }

  Future<void> _abort(Object error) async {
    if (!_disposed) onError(error);
    await _discard();
    _set(VoiceRecordingPhase.idle);
  }

  Future<void> _discard() async {
    _meter.stop();
    try {
      await _recorder.cancel();
    } catch (_) {/* best-effort */}
    _files.deleteAll();
  }

  void _set(VoiceRecordingPhase phase) {
    _phase = phase;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}

/// The files of one recording: the piece being captured and the clip of
/// everything finished before it.
class _VoiceFiles {
  String? clip;
  String? live;

  /// Adds the captured [segment] to [clip]. Throws when the two cannot be
  /// joined: the segment is gone then and [clip] is as it was.
  Future<void> close(String? segment, VoiceSegmentJoin join) async {
    live = null;
    final before = clip;
    if (before == null || segment == null) {
      clip = segment ?? before;
      return;
    }
    final joined = await newVoiceClipPath();
    try {
      await join(segments: [before, segment], output: joined);
    } catch (_) {
      deleteVoiceClip(joined);
      rethrow;
    } finally {
      deleteVoiceClip(segment);
    }
    clip = joined;
    deleteVoiceClip(before);
  }

  /// Hands [clip] over: its file is the caller's from here on.
  String? release() {
    final released = clip;
    clip = null;
    return released;
  }

  void deleteAll() {
    deleteVoiceClip(live);
    deleteVoiceClip(clip);
    live = clip = null;
  }
}

/// How long a recording is and how many loudness readings it has.
typedef _MeterReading = ({Duration elapsed, int levels});

/// The clock and the loudness of a recording, running only while the
/// microphone captures, so pauses are left out of both.
class _VoiceMeter {
  _VoiceMeter({required this.onTick});

  static const _MeterReading zero = (elapsed: Duration.zero, levels: 0);
  static const _tick = Duration(milliseconds: 200);

  final VoidCallback onTick;

  /// One loudness reading, 0..255, per amplitude tick of the recording.
  final List<int> levels = <int>[];
  Duration elapsed = Duration.zero;
  Timer? _clock;
  StreamSubscription<Amplitude>? _amplitudes;

  _MeterReading get reading => (elapsed: elapsed, levels: levels.length);

  void start(AudioRecorder recorder) {
    _amplitudes = recorder
        .onAmplitudeChanged(const Duration(milliseconds: 100))
        .listen((amplitude) {
      // Amplitude.current is dBFS (-60..0); keep it as 0..255.
      final normalized = ((amplitude.current + 60) / 60).clamp(0.0, 1.0);
      levels.add((normalized * 255).round());
    });
    _clock = Timer.periodic(_tick, (_) {
      elapsed += _tick;
      onTick();
    });
  }

  void stop() {
    _clock?.cancel();
    _clock = null;
    _amplitudes?.cancel();
    _amplitudes = null;
  }

  /// Goes back to an earlier [reading], dropping what came after it.
  void rewind(_MeterReading to) {
    elapsed = to.elapsed;
    levels.length = to.levels;
  }
}

/// A new file for a piece of a recording, in `mosh-voice/` under the app
/// cache. The directory is created here, recursively: `record_macos` writes
/// through `AVCaptureFileOutput`, which creates no parent directory and
/// reports that only to a delegate nobody hears, so a missing directory
/// surfaced as errno 2 when the clip was read for sending (macOS 0.9.3).
/// Created here, a broken directory fails at capture time, visibly.
Future<String> newVoiceClipPath() async {
  final cache = await getApplicationCacheDirectory();
  final dir = Directory('${cache.path}/mosh-voice');
  // Sync: the directory must exist before the recorder gets the path.
  dir.createSync(recursive: true);
  return '${dir.path}/mosh-voice-${DateTime.now().microsecondsSinceEpoch}.m4a';
}

/// Removes a recorded file. Best effort and synchronous: a clip is a few
/// megabytes at most.
void deleteVoiceClip(String? path) {
  if (path == null) return;
  try {
    final file = File(path);
    if (file.existsSync()) file.deleteSync();
  } catch (_) {/* best-effort */}
}

/// Loudness readings, one per tick of a recording, as the
/// [waveformBuckets] peaks a voice message carries, spread over its length.
Uint8List voiceWaveform(List<int> levels) {
  final peaks = Uint8List(waveformBuckets);
  final count = levels.length;
  if (count == 0) return peaks;
  for (var bucket = 0; bucket < waveformBuckets; bucket++) {
    final from = bucket * count ~/ waveformBuckets;
    final to = math.max(from + 1, (bucket + 1) * count ~/ waveformBuckets);
    peaks[bucket] = levels.sublist(from, to).reduce(math.max);
  }
  return peaks;
}
