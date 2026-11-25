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

  static const _tick = Duration(milliseconds: 200);
  static const _mime = 'audio/mp4';

  final AudioRecorder _recorder = AudioRecorder();
  VoiceRecordingPhase _phase = VoiceRecordingPhase.idle;
  Duration _elapsed = Duration.zero;
  Timer? _clock;
  StreamSubscription<Amplitude>? _amplitudes;
  // One loudness reading per amplitude tick of the whole recording.
  final List<int> _levels = <int>[];
  Uint8List _peaks = Uint8List(waveformBuckets);
  String? _clip;
  String? _live;
  // One recorder transition at a time: a pause, a cancel, a send and the
  // length limit all tear the capture down asynchronously, and a cancel
  // racing a pause would delete the file the pause is still closing.
  bool _busy = false;
  bool _disposed = false;

  VoiceRecordingPhase get phase => _phase;

  /// How much has been recorded, pauses left out.
  Duration get elapsed => _elapsed;

  /// The finished clip of a paused recording, to listen to.
  String? get clip => _clip;

  /// The waveform of a paused recording.
  Uint8List get peaks => _peaks;

  /// Whether an action is still closing or joining files.
  bool get busy => _busy;

  /// Asks for the microphone and starts capturing.
  Future<void> start() => _exclusive(() async {
        if (_phase != VoiceRecordingPhase.idle) return;
        // Ask at the moment of intent: hasPermission() requests when the
        // status is undetermined and just reports otherwise. `record`'s
        // start() never requests on its own, so this call is the only gate.
        if (!await _recorder.hasPermission()) return onPermissionDenied();
        if (_disposed || !canCapture()) return;
        _elapsed = Duration.zero;
        _levels.clear();
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
        if (_phase != VoiceRecordingPhase.paused || !canCapture()) return;
        await _capture();
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
      if (_phase == VoiceRecordingPhase.recording) await _close();
      final path = _clip;
      if (path == null) return;
      voice = VoiceSend(
        path: path,
        mime: _mime,
        durationMs: _elapsed.inMilliseconds,
        peaksBase64: base64Encode(_peaks),
      );
      _clip = null;
      _set(VoiceRecordingPhase.idle);
    });
    return voice;
  }

  @override
  void dispose() {
    _disposed = true;
    _stopClock();
    unawaited(_recorder.dispose());
    _delete(_clip);
    super.dispose();
  }

  /// Runs one recorder transition; a second one asked for meanwhile is
  /// dropped. A failure ends the recording and is reported.
  Future<void> _exclusive(Future<void> Function() transition) async {
    if (_busy) return;
    _busy = true;
    try {
      await transition();
    } catch (error) {
      await _abort(error);
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// Starts a new file and the clock. A composer that went out of sight
  /// while the recorder was starting is paused at once.
  ///
  /// The file lands in an explicit `mosh-voice/` subdirectory of the app
  /// cache, created recursively HERE. Two reasons (macOS 0.9.3 field bug):
  /// `getTemporaryDirectory()` maps to `NSCachesDirectory` + the bundle id
  /// and path_provider never creates that base, and `record_macos` writes
  /// via `AVCaptureFileOutput.startRecording(to:)`, which creates no
  /// parent directory and reports the failure only to an unsurfaced
  /// delegate: `stop()` still returns the path, so the file's absence
  /// surfaced later as errno 2 when the clip was read for sending. The app
  /// cache base (`getApplicationCacheDirectory`) IS created by the plugin,
  /// and the explicit recursive create makes the invariant ours: a broken
  /// directory fails at capture time, visibly, not at send time.
  Future<void> _capture() async {
    final path = await _newPath();
    _live = path;
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
    _amplitudes = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 100))
        .listen(_onAmplitude);
    _clock = Timer.periodic(_tick, (_) => _onTick());
    _set(VoiceRecordingPhase.recording);
    if (!canCapture()) {
      await _close();
      _set(VoiceRecordingPhase.paused);
    }
  }

  Future<String> _newPath() async {
    final cache = await getApplicationCacheDirectory();
    final dir = Directory('${cache.path}/mosh-voice');
    // Sync: the directory must exist before the recorder gets the path.
    dir.createSync(recursive: true);
    return '${dir.path}/mosh-voice-${DateTime.now().microsecondsSinceEpoch}.m4a';
  }

  void _onTick() {
    _elapsed += _tick;
    _notify();
    // The longest recording pauses itself, to be listened to or sent.
    if (_elapsed >= maxRecording) unawaited(pause());
  }

  void _onAmplitude(Amplitude amplitude) {
    // Amplitude.current is dBFS (-60..0); keep it as 0..255.
    final normalized = ((amplitude.current + 60) / 60).clamp(0.0, 1.0);
    _levels.add((normalized * 255).round());
  }

  /// Stops the capture and adds its file to [clip].
  Future<void> _close() async {
    _stopClock();
    final segment = _live = await _recorder.stop() ?? _live;
    final before = _clip;
    if (before == null || segment == null) {
      _clip = segment ?? before;
    } else {
      final joined = await _newPath();
      await join(segments: [before, segment], output: joined);
      _clip = joined;
      _delete(before);
      _delete(segment);
    }
    _live = null;
    _peaks = _waveform();
  }

  /// The recording's loudness as the [waveformBuckets] peaks a voice
  /// message carries, spread over its real length.
  Uint8List _waveform() {
    final peaks = Uint8List(waveformBuckets);
    final count = _levels.length;
    if (count == 0) return peaks;
    for (var bucket = 0; bucket < waveformBuckets; bucket++) {
      final from = bucket * count ~/ waveformBuckets;
      final to = math.max(from + 1, (bucket + 1) * count ~/ waveformBuckets);
      peaks[bucket] = _levels.sublist(from, to).reduce(math.max);
    }
    return peaks;
  }

  Future<void> _abort(Object error) async {
    onError(error);
    await _discard();
    _set(VoiceRecordingPhase.idle);
  }

  Future<void> _discard() async {
    _stopClock();
    try {
      await _recorder.cancel();
    } catch (_) {/* best-effort */}
    _delete(_live);
    _delete(_clip);
    _live = null;
    _clip = null;
  }

  void _stopClock() {
    _clock?.cancel();
    _clock = null;
    _amplitudes?.cancel();
    _amplitudes = null;
  }

  /// Best effort and synchronous: a clip is a few megabytes at most.
  void _delete(String? path) {
    if (path == null) return;
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } catch (_) {/* best-effort */}
  }

  void _set(VoiceRecordingPhase phase) {
    _phase = phase;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}
