library;

import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_theme.dart'
    show MoshColors, kLiveNumberFontFeatures;

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
