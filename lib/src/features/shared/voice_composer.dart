/// Slice-3 voice composer. Microphone capture with
/// three phases (idle -> recording -> review) before sending. The recording
/// itself uses the `record` package (`AudioRecorder`); live amplitude samples
/// feed a 64-bucket waveform (peak
/// per bucket, base64-encoded for `VoiceMeta.peaksB64`).
///
/// Phases: idle renders a mic IconButton;
/// recording renders a dot + elapsed timer + discard + stop; review renders
/// play + duration + discard + send. `disabled` gates the mic button (idle).
/// `onSend(voice)` hands a `VoiceSend` to the screen; `onError(message)`
/// surfaces mic-permission / start failures. `supported` is checked once on
/// init (`AudioRecorder.hasPermission`); unsupported renders nothing.
library;

import 'dart:async' show StreamSubscription, Timer;
import 'dart:convert' show base64Encode;
import 'dart:io' show File;
import 'dart:typed_data' show Uint8List;

import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_theme.dart'
    show MoshColors, kLiveNumberFontFeatures;
import 'package:path_provider/path_provider.dart' show getTemporaryDirectory;
import 'package:record/record.dart';
import 'package:media_kit/media_kit.dart';

/// A finished voice clip ready to send. `path`
/// points at the recorded file; `mime` is the container; `durationMs` + the
/// 64-bucket `peaksBase64` waveform form `VoiceMeta` on the gateway seam.
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

/// `m:ss`.
String _formatElapsed(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds.remainder(60);
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// The live m:ss timers (record elapsed, preview duration). Tabular figures:
/// the digits change every tick, and proportional numerals let the row
/// (discard/stop after the timer) shift horizontally -- the call overlay's
/// timer already renders this way (audit 2026-09-21).
const TextStyle kVoiceTimerStyle =
    TextStyle(fontFeatures: kLiveNumberFontFeatures);

/// The recording indicator's 8px dot. Palette
/// accent, not a raw Material red: the theme's danger token (audit
/// 2026-09-21 palette-drift). Public so the accent is testable without the
/// platform microphone.
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
  });

  final bool disabled;
  final void Function(VoiceSend voice) onSend;
  final void Function(String message) onError;
  final String recordLabel;
  final String discardLabel;
  final String stopLabel;
  final String playLabel;
  final String sendLabel;

  @override
  State<VoiceComposer> createState() => _VoiceComposerState();
}

class _VoiceComposerState extends State<VoiceComposer> {
  final AudioRecorder _recorder = AudioRecorder();
  _Phase _phase = _Phase.idle;
  bool _supported = false;
  Timer? _elapsedTimer;
  Timer? _autoStopTimer;
  StreamSubscription<Amplitude>? _amplitudeSub;
  Duration _elapsed = Duration.zero;
  final List<int> _peaks = List<int>.filled(waveformBuckets, 0);
  String? _path;
  String _mime = '';
  int _durationMs = 0;
  // Review-phase preview player (media_kit). Lazy + nullable: created on the
  // first _togglePreview and disposed on discard / send / widget dispose.
  // Null (test env without the native lib) -> the play button is a no-op,
  // matching the previous inert placeholder so existing tests stay green.
  Player? _previewPlayer;
  bool _previewPlaying = false;

  @override
  void initState() {
    super.initState();
    _checkSupported();
  }

  Future<void> _checkSupported() async {
    try {
      final ok = await _recorder.hasPermission();
      if (mounted) setState(() => _supported = ok);
    } catch (_) {
      // Permission check itself failed -- treat as unsupported (render null).
    }
  }

  @override
  void dispose() {
    _stopTimers();
    _amplitudeSub?.cancel();
    _disposePreview();
    _recorder.dispose();
    super.dispose();
  }

  void _stopTimers() {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    _autoStopTimer?.cancel();
    _autoStopTimer = null;
  }

  /// Toggle the review-phase preview. Lazily creates
  /// a media_kit Player on first tap, opens the recorded file, and
  /// playOrPauses. The playing stream drives the play/pause icon. Defensive:
  /// if Player() throws (test env), the button is a no-op so the review row
  /// still renders minus live preview.
  Future<void> _togglePreview() async {
    final path = _path;
    if (path == null) return;
    var player = _previewPlayer;
    try {
      if (player == null) {
        player = Player();
        _previewPlayer = player;
        player.stream.playing.listen((playing) {
          if (mounted) setState(() => _previewPlaying = playing);
        });
        await player.open(Media(path));
      } else {
        await player.playOrPause();
      }
    } catch (_) {
      _previewPlayer = null;
      _previewPlaying = false;
    }
  }

  void _disposePreview() {
    _previewPlayer?.dispose();
    _previewPlayer = null;
    _previewPlaying = false;
  }

  Future<void> _startRecording() async {
    if (widget.disabled || !_supported) return;
    try {
      final dir = await getTemporaryDirectory();
      _path =
          '${dir.path}/mosh-voice-${DateTime.now().millisecondsSinceEpoch}.m4a';
      _mime = 'audio/mp4';
      _elapsed = Duration.zero;
      _durationMs = 0;
      for (var i = 0; i < _peaks.length; i++) {
        _peaks[i] = 0;
      }
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: _path!,
      );
      _amplitudeSub = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 100))
          .listen(_onAmplitude);
      _elapsedTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (mounted) {
          setState(() => _elapsed += const Duration(milliseconds: 200));
        }
      });
      _autoStopTimer = Timer(maxRecording, _finishRecording);
      if (mounted) setState(() => _phase = _Phase.recording);
    } catch (error) {
      widget.onError(error.toString());
      await _cleanupRecorder();
      if (mounted) setState(() => _phase = _Phase.idle);
    }
  }

  void _onAmplitude(Amplitude amplitude) {
    // Amplitude.current is in dBFS (-60..0). Map to 0..255 and store the peak
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
    _stopTimers();
    _amplitudeSub?.cancel();
    _amplitudeSub = null;
    try {
      final path = await _recorder.stop();
      _durationMs = _elapsed.inMilliseconds;
      _path = path;
      if (mounted) setState(() => _phase = _Phase.review);
    } catch (error) {
      widget.onError(error.toString());
      await _cleanupRecorder();
      if (mounted) setState(() => _phase = _Phase.idle);
    }
  }

  Future<void> _discard() async {
    _stopTimers();
    _amplitudeSub?.cancel();
    _amplitudeSub = null;
    await _cleanupRecorder();
    _disposePreview();
    if (mounted) setState(() => _phase = _Phase.idle);
  }

  Future<void> _cleanupRecorder() async {
    try {
      await _recorder.cancel();
    } catch (_) {
      // best-effort
    }
    if (_path != null) {
      try {
        final file = File(_path!);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // best-effort
      }
    }
    _path = null;
  }

  void _send() {
    if (_path == null) return;
    _disposePreview();
    final peaks = Uint8List.fromList(_peaks);
    widget.onSend(VoiceSend(
      path: _path!,
      mime: _mime,
      durationMs: _durationMs,
      peaksBase64: base64Encode(peaks),
    ));
    _path = null;
    if (mounted) setState(() => _phase = _Phase.idle);
  }

  @override
  Widget build(BuildContext context) {
    if (!_supported) return const SizedBox.shrink();
    switch (_phase) {
      case _Phase.idle:
        return IconButton(
          icon: const Icon(Icons.mic_none_outlined),
          tooltip: widget.recordLabel,
          onPressed: widget.disabled ? null : _startRecording,
        );
      case _Phase.recording:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const VoiceRecordingDot(),
            const SizedBox(width: 8),
            Text(_formatElapsed(_elapsed), style: kVoiceTimerStyle),
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
      case _Phase.review:
        return Row(
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
              _formatElapsed(Duration(milliseconds: _durationMs)),
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
  }
}
