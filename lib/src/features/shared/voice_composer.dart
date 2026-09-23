/// Slice-3 voice composer. Microphone capture with three phases
/// (idle -> recording -> review) before sending, via the `record` package
/// (`AudioRecorder`); live amplitude samples feed a 64-bucket waveform
/// (peak per bucket, base64-encoded for `VoiceMeta.peaksB64`).
///
/// idle renders a mic IconButton; recording renders dot + elapsed timer +
/// discard + stop; review renders play + duration + discard + send.
/// `disabled` gates the mic button (idle). `onSend(voice)` hands a
/// [VoiceSend] to the screen; `onError(message)` surfaces mic-permission /
/// start failures. The mic button always renders; the permission request
/// happens on tap (`AudioRecorder.hasPermission`), never at mount — asking
/// at chat open is what triggered the macOS TCC crash, and a dialog
/// before intent is bad form anyway.
library;

import 'dart:async' show StreamSubscription, Timer;
import 'dart:convert' show base64Encode;
import 'dart:io' show Directory, File;
import 'dart:typed_data' show Uint8List;

import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_theme.dart'
    show MoshColors, kLiveNumberFontFeatures;
import 'package:mosh/src/rust/api/audio_devices.dart' show audioInputDeviceId;
import 'package:path_provider/path_provider.dart'
    show getApplicationCacheDirectory;
import 'package:record/record.dart';
import 'package:media_kit/media_kit.dart';

/// A finished voice clip ready to send: `path` points at the recorded
/// file, `mime` is the container; `durationMs` + the 64-bucket
/// `peaksBase64` waveform form `VoiceMeta` on the gateway seam.
class VoiceSend {
  const VoiceSend({
    required this.path,
    required this.mime,
    required this.durationMs,
    required this.peaksBase64,
  });

  final String path;
  final String mime;
  final int durationMs;
  final String peaksBase64;
}

/// 64 amplitude buckets (one byte each, 0-255).
const int waveformBuckets = 64;

/// Maximum recording length; auto-stops here.
const Duration maxRecording = Duration(minutes: 5);

/// `m:ss`, shared by the composer's live timers and the voice-message
/// card's time label. Negative input clamps to zero.
String formatVoiceClock(int ms) {
  final total = ms < 0 ? 0 : ms ~/ 1000;
  final m = total ~/ 60;
  final s = total % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// The live m:ss timers (record elapsed, preview duration). Tabular
/// figures: the digits change every tick, and proportional numerals would
/// let the row shift horizontally (audit 2026-09-21).
const TextStyle kVoiceTimerStyle =
    TextStyle(fontFeatures: kLiveNumberFontFeatures);

/// The recording indicator's 8px dot — the theme's danger token, not a raw
/// Material red (audit 2026-09-21 palette-drift). Public so the accent is
/// testable without the platform microphone.
class VoiceRecordingDot extends StatelessWidget {
  const VoiceRecordingDot({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: const BoxDecoration(
        color: MoshColors.danger,
        shape: BoxShape.circle,
      ),
    );
  }
}

enum _Phase { idle, recording, review }

/// The production input pick: mosh-core's audio-devices store. A top
///-level default (not inline) so the widget stays const-constructible.
String? _storedInputDeviceId() => audioInputDeviceId();

/// Microphone control for the composer. Stateless from the screen's view:
/// owns the recorder + the phase + the elapsed timer + the amplitude stream
/// internally, and hands a ready-to-send [VoiceSend] to `onSend`.
class VoiceComposer extends StatefulWidget {
  const VoiceComposer({
    super.key,
    required this.disabled,
    required this.onSend,
    required this.onError,
    required this.recordLabel,
    required this.discardLabel,
    required this.stopLabel,
    required this.playLabel,
    required this.sendLabel,
    required this.permissionDeniedLabel,
    this.inputDeviceId = _storedInputDeviceId,
  });

  final bool disabled;
  final void Function(VoiceSend voice) onSend;
  final void Function(String message) onError;
  final String recordLabel;
  final String discardLabel;
  final String stopLabel;
  final String playLabel;
  final String sendLabel;

  /// Shown via [onError] when the tap-time permission request is refused.
  final String permissionDeniedLabel;

  /// Reads the stored input-device pick (audio-devices.json) for the
  /// capture config. Injectable so tests (no cdylib) pass a plain getter;
  /// production uses the frb store read. Null return = platform default.
  final String? Function() inputDeviceId;

  @override
  State<VoiceComposer> createState() => _VoiceComposerState();
}

class _VoiceComposerState extends State<VoiceComposer> {
  final AudioRecorder _recorder = AudioRecorder();
  _Phase _phase = _Phase.idle;
  Timer? _elapsedTimer;
  Timer? _autoStopTimer;
  StreamSubscription<Amplitude>? _amplitudeSub;
  Duration _elapsed = Duration.zero;
  final List<int> _peaks = List<int>.filled(waveformBuckets, 0);
  String? _path;
  String _mime = '';
  int _durationMs = 0;
  // Review-phase preview player (media_kit). Lazy + nullable: created on
  // the first _togglePreview, disposed on discard / send / dispose. Null
  // (test env without the native lib) -> the play button is a no-op.
  Player? _previewPlayer;
  bool _previewPlaying = false;
  // One recorder teardown at a time: manual stop, the auto-stop timer and
  // discard all tear the capture down asynchronously; without the guard a
  // discard racing a stop cancelled the recorder under the stop() call
  // and deleted the file stop() was still writing.
  bool _finalizing = false;

  /// setState only while the state is still alive.
  void _ifMounted(VoidCallback fn) {
    if (mounted) fn();
  }

  @override
  void dispose() {
    _stopTimersAndAmplitude();
    _disposePreview();
    _recorder.dispose();
    super.dispose();
  }

  /// Cancels the elapsed / auto-stop timers and the amplitude stream.
  void _stopTimersAndAmplitude() {
    _stopTimers();
    _amplitudeSub?.cancel();
    _amplitudeSub = null;
  }

  void _stopTimers() {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    _autoStopTimer?.cancel();
    _autoStopTimer = null;
  }

  /// Toggle the review-phase preview: the first tap creates the player and
  /// opens the recorded file; later taps toggle play/pause (the playing
  /// stream drives the icon). If Player() throws (test env without the
  /// native lib) the button is a no-op so the review row still renders.
  Future<void> _togglePreview() async {
    final path = _path;
    if (path == null) return;
    final player = _previewPlayer;
    try {
      if (player == null) {
        await _openPreview(path);
      } else {
        await player.playOrPause();
      }
    } catch (_) {
      _previewPlayer = null;
      _previewPlaying = false;
    }
  }

  /// Creates the preview player, wires its playing stream, opens the file.
  /// Throwing here resets the preview in the caller's catch.
  Future<void> _openPreview(String path) async {
    final player = Player();
    _previewPlayer = player;
    player.stream.playing.listen((playing) {
      _ifMounted(() => setState(() => _previewPlaying = playing));
    });
    await player.open(Media(path));
  }

  void _disposePreview() {
    _previewPlayer?.dispose();
    _previewPlayer = null;
    _previewPlaying = false;
  }

  Future<void> _startRecording() async {
    if (widget.disabled || _phase != _Phase.idle) return;
    try {
      // Ask at the moment of intent: hasPermission() requests when the
      // status is .notDetermined and just reports otherwise. `record`'s
      // start() never requests on its own, so this call is the only gate.
      final allowed = await _recorder.hasPermission();
      if (!allowed) {
        widget.onError(widget.permissionDeniedLabel);
        return;
      }
      await _capture();
      _ifMounted(() => setState(() => _phase = _Phase.recording));
    } catch (error) {
      await _abortRecording(error);
    }
  }

  /// Starts the capture: allocates the temp file, resets the meter, wires
  /// the amplitude / elapsed timers and the auto-stop deadline.
  ///
  /// The clip lands in an explicit `mosh-voice/` subdirectory of the app
  /// cache, created recursively HERE. Two reasons (macOS 0.9.3 field bug):
  /// `getTemporaryDirectory()` maps to `NSCachesDirectory` + the bundle id
  /// and path_provider never creates that base, and `record_macos` writes
  /// via `AVCaptureFileOutput.startRecording(to:)`, which creates no
  /// parent directory and reports the failure only to an unsurfaced
  /// delegate — `stop()` still returns the path, so the file's absence
  /// surfaced later as errno 2 in `sendVoice`'s `readAsBytes()`. The app
  /// cache base (`getApplicationCacheDirectory`) IS created by the plugin,
  /// and the explicit recursive create makes the invariant ours: a broken
  /// directory fails at capture time, visibly, not at send time.
  Future<void> _capture() async {
    final cache = await getApplicationCacheDirectory();
    final dir = Directory('${cache.path}/mosh-voice');
    // Sync, not `await dir.create()`: the clip dir must exist before the
    // recorder gets the path, and a sync create is indistinguishable in
    // production (one mkdir per recording start).
    dir.createSync(recursive: true);
    _path =
        '${dir.path}/mosh-voice-${DateTime.now().millisecondsSinceEpoch}.m4a';
    _mime = 'audio/mp4';
    _elapsed = Duration.zero;
    _durationMs = 0;
    _peaks.fillRange(0, _peaks.length, 0);
    // The stored input pick (audio-devices.json); null = platform default.
    // The label is cosmetic on the platform side, so the id doubles as it.
    final picked = widget.inputDeviceId();
    await _recorder.start(
      RecordConfig(
        encoder: AudioEncoder.aacLc,
        device: picked == null ? null : InputDevice(id: picked, label: picked),
      ),
      path: _path!,
    );
    _amplitudeSub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 100))
        .listen(_onAmplitude);
    _elapsedTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      _ifMounted(
          () => setState(() => _elapsed += const Duration(milliseconds: 200)));
    });
    _autoStopTimer = Timer(maxRecording, _finishRecording);
  }

  /// Shared failure path of start/finish: surface the error, tear the
  /// capture down, drop back to idle. Called with the guard already held
  /// or straight from _startRecording.
  Future<void> _abortRecording(Object error) async {
    widget.onError(error.toString());
    _stopTimersAndAmplitude();
    await _cleanupRecorder();
    _disposePreview();
    _ifMounted(() => setState(() => _phase = _Phase.idle));
  }

  void _onAmplitude(Amplitude amplitude) {
    // Amplitude.current is dBFS (-60..0); map to 0..255 and keep the peak
    // per bucket as the recording progresses (live downsample).
    final db = amplitude.current;
    final normalized = ((db + 60) / 60).clamp(0.0, 1.0);
    final value = (normalized * 255).round();
    final bucket = (_elapsed.inMilliseconds *
            waveformBuckets ~/
            maxRecording.inMilliseconds)
        .clamp(0, waveformBuckets - 1);
    if (value > _peaks[bucket]) {
      _peaks[bucket] = value;
    }
  }

  Future<void> _finishRecording() async {
    // The auto-stop timer, the stop button, and a racing discard can all
    // land here (or in _discard); one of them wins, the rest are no-ops.
    if (_finalizing || _phase != _Phase.recording) return;
    _finalizing = true;
    _stopTimersAndAmplitude();
    try {
      final path = await _recorder.stop();
      _durationMs = _elapsed.inMilliseconds;
      _path = path;
      _ifMounted(() => setState(() => _phase = _Phase.review));
    } catch (error) {
      await _abortRecording(error);
    } finally {
      _finalizing = false;
    }
  }

  Future<void> _discard() async {
    if (_finalizing) return;
    _finalizing = true;
    try {
      _stopTimersAndAmplitude();
      await _cleanupRecorder();
      _disposePreview();
      _ifMounted(() => setState(() => _phase = _Phase.idle));
    } finally {
      _finalizing = false;
    }
  }

  Future<void> _cleanupRecorder() async {
    try {
      await _recorder.cancel();
    } catch (_) {/* best-effort */}
    if (_path != null) {
      try {
        final file = File(_path!);
        if (await file.exists()) await file.delete();
      } catch (_) {/* best-effort */}
    }
    _path = null;
  }

  void _send() {
    final path = _path;
    if (path == null) return;
    _disposePreview();
    widget.onSend(VoiceSend(
      path: path,
      mime: _mime,
      durationMs: _durationMs,
      peaksBase64: base64Encode(Uint8List.fromList(_peaks)),
    ));
    _path = null;
    _ifMounted(() => setState(() => _phase = _Phase.idle));
  }

  @override
  Widget build(BuildContext context) {
    return switch (_phase) {
      _Phase.idle => _buildIdle(),
      _Phase.recording => _buildRecording(),
      _Phase.review => _buildReview(),
    };
  }

  /// The mic button; gated by the composer's `disabled` flag.
  Widget _buildIdle() => IconButton(
        icon: const Icon(Icons.mic_none_outlined),
        tooltip: widget.recordLabel,
        onPressed: widget.disabled ? null : _startRecording,
      );

  /// Dot + elapsed timer + discard + stop.
  Widget _buildRecording() => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const VoiceRecordingDot(),
          const SizedBox(width: 8),
          Text(formatVoiceClock(_elapsed.inMilliseconds),
              style: kVoiceTimerStyle),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: widget.discardLabel,
            onPressed: _discard,
          ),
          IconButton(
            icon: const Icon(Icons.stop),
            tooltip: widget.stopLabel,
            onPressed: _finishRecording,
          ),
        ],
      );

  /// Play + duration + discard + send.
  Widget _buildReview() => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            // Toggles the preview play state. The icon
            // swaps play_arrow <-> pause on the playing stream (set in
            // _togglePreview).
            icon: Icon(_previewPlaying ? Icons.pause : Icons.play_arrow),
            tooltip: widget.playLabel,
            onPressed: _togglePreview,
          ),
          const SizedBox(width: 8),
          Text(
            formatVoiceClock(_durationMs),
            style: kVoiceTimerStyle,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: widget.discardLabel,
            onPressed: _discard,
          ),
          IconButton(
            icon: const Icon(Icons.send),
            tooltip: widget.sendLabel,
            onPressed: _send,
          ),
        ],
      );
}
