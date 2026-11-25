import 'dart:convert' show base64Decode;
import 'dart:math' as math;
import 'dart:typed_data' show Uint8List;

import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/features/shared/voice_composer.dart'
    show waveformBuckets;

/// Decodes the peaks a voice message carries. Malformed peaks are flat
/// zeros, never fatal.
Uint8List voicePeaksFromBase64(String? b64) {
  final peaks = Uint8List(waveformBuckets);
  if (b64 == null || b64.isEmpty) return peaks;
  try {
    final bytes = base64Decode(b64);
    for (var i = 0; i < waveformBuckets && i < bytes.length; i++) {
      peaks[i] = bytes[i];
    }
  } catch (_) {
    // flat zeros
  }
  return peaks;
}

/// The Waveform card: 28 rounded bars that fill as the message plays. A
/// press on it seeks; it measures its own width, independently of the card
/// around it, and narrows with a narrow message.
class VoiceWaveform extends StatelessWidget {
  const VoiceWaveform({
    super.key,
    required this.peaks,
    required this.progress,
    required this.played,
    required this.unplayed,
    required this.onSeekRatio,
  });

  /// Bars drawn, each [barWidth] wide and [gap] from the next.
  static const int bars = 28;
  static const double barWidth = 3;
  static const double gap = MoshSpace.s1;
  static const double width = bars * barWidth + (bars - 1) * gap;
  static const double height = MoshSpace.s6;

  final Uint8List peaks;
  final double progress;
  final Color played;
  final Color unplayed;

  /// Called with the pressed position as a 0..1 fraction of the wave width.
  final ValueChanged<double> onSeekRatio;

  @override
  Widget build(BuildContext context) => Builder(
        builder: (context) => GestureDetector(
          onTapDown: (details) {
            final box = context.findRenderObject() as RenderBox?;
            final width = box?.size.width ?? 0;
            if (width == 0) return;
            onSeekRatio((details.localPosition.dx / width).clamp(0.0, 1.0));
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: width),
            child: SizedBox(
              width: double.infinity,
              height: height,
              child: CustomPaint(
                painter: _WaveformPainter(
                  peaks: peaks,
                  progress: progress,
                  played: played,
                  unplayed: unplayed,
                ),
              ),
            ),
          ),
        ),
      );
}

/// Draws the bars, each as tall as the loudest of the peaks it stands for,
/// and marks the played ones in their own colour.
class _WaveformPainter extends CustomPainter {
  const _WaveformPainter({
    required this.peaks,
    required this.progress,
    required this.played,
    required this.unplayed,
  });

  final Uint8List peaks;
  final double progress;
  final Color played;
  final Color unplayed;

  /// The loudest peak among those bar [index] stands for, 0..1.
  double _amplitude(int index) {
    final from = index * peaks.length ~/ VoiceWaveform.bars;
    final to =
        math.max(from + 1, (index + 1) * peaks.length ~/ VoiceWaveform.bars);
    var loudest = 0;
    for (var i = from; i < to && i < peaks.length; i++) {
      loudest = math.max(loudest, peaks[i]);
    }
    return loudest / 255;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final step = size.width / VoiceWaveform.bars;
    final bar = math.min(VoiceWaveform.barWidth, step);
    final playedBars = (progress * VoiceWaveform.bars).round();
    final playedPaint = Paint()..color = played;
    final unplayedPaint = Paint()..color = unplayed;
    for (var i = 0; i < VoiceWaveform.bars; i++) {
      final barHeight = math.max(bar * 2, _amplitude(i) * size.height);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(i * step + bar / 2, size.height / 2),
            width: bar,
            height: barHeight,
          ),
          Radius.circular(bar / 2),
        ),
        i < playedBars ? playedPaint : unplayedPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) =>
      old.peaks != peaks ||
      old.progress != progress ||
      old.played != played ||
      old.unplayed != unplayed;
}
