import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;

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

/// The shortest recording that is sent: a press on Send before this, such
/// as a second press that was meant for the microphone, throws it away.
const Duration minRecording = Duration(seconds: 1);

/// Maximum recording length; the recording pauses itself here.
const Duration maxRecording = Duration(minutes: 5);

/// `m:ss`, shared by the composer's clocks and the voice-message card's
/// time label. Negative input clamps to zero.
String formatVoiceClock(int ms) {
  final total = ms < 0 ? 0 : ms ~/ 1000;
  final m = total ~/ 60;
  final s = total % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// Joins the finished pieces of one recording, in order, into a new clip
/// at [output]; `joinVoiceSegments` of mosh-core in production.
typedef VoiceSegmentJoin = Future<void> Function(
    {required List<String> segments, required String output});

/// What the voice controls are called: [cancel] is read on its button, the
/// rest are tooltips and screen-reader names.
class VoiceComposerLabels {
  const VoiceComposerLabels({
    required this.record,
    required this.cancel,
    required this.pause,
    required this.resume,
    required this.discard,
    required this.play,
    required this.pausePlayback,
    required this.send,
    required this.permissionDenied,
  });

  final String record;
  final String cancel;
  final String pause;
  final String resume;
  final String discard;
  final String play;
  final String pausePlayback;
  final String send;

  /// Told through the composer's error callback when the microphone is
  /// refused at the press.
  final String permissionDenied;
}

/// The recording indicator's 8px dot, in the theme's error colour. Public
/// so the accent is testable without the platform microphone.
class VoiceRecordingDot extends StatelessWidget {
  const VoiceRecordingDot({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: MoshSpace.s2,
      height: MoshSpace.s2,
      decoration: BoxDecoration(
        color: MoshColors.of(context).error,
        shape: BoxShape.circle,
      ),
    );
  }
}
