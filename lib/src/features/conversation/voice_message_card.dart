// Slice-3 voice-message card -- 1-в-1 port of React
// src/features/private-dm/voice/VoiceMessage.tsx. Rendered by AttachmentCard
// when descriptor.voice != null (React: if (voice) return VoiceMessage). An
// inline player: a play/pause button + a 64-bucket waveform (CustomPaint,
// played/unplayed split at the live progress) + a position/duration label.
// Tapping the waveform seeks. Playback uses media_kit (the same engine
// MediaViewer + VoiceComposer preview use); the file path comes from
// view.localPath. If the file is not local yet (offered/offered incoming),
// the play button triggers onDownload (React toggle's download branch).
library;

import 'dart:convert' show base64Decode;
import 'dart:math' as math;
import 'dart:typed_data' show Uint8List;

import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;

import 'package:media_kit/media_kit.dart';

import 'package:mosh/src/rust/conversation/attachments.dart';

/// 64 amplitude buckets (mirrors React WAVEFORM_BUCKETS / voice_composer).
const int _waveformBuckets = 64;

String _formatClock(int ms) {
  final total = math.max(0, ms ~/ 1000);
  final m = total ~/ 60;
  final s = total % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// Decode the base64 peaks (React peaksFromBase64). Malformed -> flat zeros,
/// never fatal.
Uint8List _peaksFromBase64(String? b64) {
  final peaks = Uint8List(_waveformBuckets);
  if (b64 == null || b64.isEmpty) return peaks;
  try {
    final bytes = base64Decode(b64);
    for (var i = 0; i < _waveformBuckets && i < bytes.length; i++) {
      peaks[i] = bytes[i];
    }
  } catch (_) {
    // flat zeros
  }
  return peaks;
}

/// Inline voice-message player. [descriptor] carries the VoiceMeta (duration
/// + peaks); [view] carries the local path + transfer state; [onDownload] is
/// fired when the user taps play before the file is local (React toggle).
class VoiceMessageCard extends StatefulWidget {
  const VoiceMessageCard({
    super.key,
    required this.descriptor,
    required this.view,
    required this.busy,
    required this.onDownload,
    required this.playLabel,
    required this.pauseLabel,
  });

  final AttachmentDescriptor descriptor;
  final AttachmentView? view;
  final bool busy;
  final void Function(String attachmentId) onDownload;

  final String playLabel;
  final String pauseLabel;

  @override
  State<VoiceMessageCard> createState() => _VoiceMessageCardState();
}

class _VoiceMessageCardState extends State<VoiceMessageCard> {
  Player? _player;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    // Defensive: Player() throws in test envs (no native lib) -> the card
    // renders the waveform + a disabled play button so the row still shows.
    try {
      final player = Player();
      _player = player;
      player.stream.playing.listen((playing) {
        if (mounted) setState(() => _playing = playing);
      });
      player.stream.position.listen((pos) {
        if (mounted) setState(() => _position = pos);
      });
      player.stream.duration.listen((dur) {
        if (mounted) setState(() => _duration = dur);
      });
    } catch (_) {
      _player = null;
    }
  }

  @override
  void didUpdateWidget(covariant VoiceMessageCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the local path arrived (download finished), open it on the player so
    // the queued play can proceed (React playWhenReady effect).
    final newPath = widget.view?.localPath;
    final oldPath = oldWidget.view?.localPath;
    if (newPath != null && newPath != oldPath) {
      _open(newPath);
    }
  }

  Future<void> _open(String path) async {
    final player = _player;
    if (player == null) return;
    try {
      await player.open(Media(path));
    } catch (_) {
      // best-effort
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  bool get _downloading => widget.view?.state == AttachmentState.downloading;

  Future<void> _toggle() async {
    final player = _player;
    final localPath = widget.view?.localPath;
    if (localPath == null) {
      // React toggle download branch: not local yet -> trigger download.
      if (!_downloading) {
        widget.onDownload(widget.descriptor.attachmentId);
      }
      return;
    }
    if (player == null) return;
    // Open on first play (the player was idle until the path arrived).
    if (_duration == Duration.zero) {
      await _open(localPath);
    }
    await player.playOrPause();
  }

  void _seek(double ratio) {
    final player = _player;
    final dur = _duration;
    if (player == null || dur.inMilliseconds == 0) return;
    final ms = (ratio * dur.inMilliseconds).round();
    player.seek(Duration(milliseconds: ms));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final voice = widget.descriptor.voice;
    final durationMs = voice?.durationMs ?? 0;
    final peaks = _peaksFromBase64(voice?.peaksB64);
    // React: progress = durationMs > 0 ? min(1, positionMs / durationMs) : 0.
    final progress = durationMs > 0
        ? (math.min(1.0, _position.inMilliseconds / durationMs))
        : 0.0;
    // React: time shows position while playing/seeked, else the full duration.
    final showMs = (_playing || _position.inMilliseconds > 0)
        ? _position.inMilliseconds
        : durationMs;
    final playLabel = _playing ? widget.pauseLabel : widget.playLabel;
    // React `.voice-message { gap: 8px; padding: 6px 8px; border-radius:
    // 10px; background: rgba(127,127,127,0.12); max-width: 280px }`.
    final enabled = !(widget.busy && widget.view?.localPath == null);
    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF7F7F7F).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // `.voice-message-play { width: 32px; height: 32px; border-radius:
          // 50%; background: #4f8cff; color: #fff }`, 0.65 opacity while it
          // waits on the file.
          Opacity(
            opacity: enabled ? 1 : 0.65,
            child: Material(
              color: const Color(0xFF4F8CFF),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: enabled ? _toggle : null,
                child: Tooltip(
                  message: playLabel,
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: Icon(
                      _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          VoiceWaveform(
            peaks: peaks,
            progress: progress,
            played: theme.colorScheme.primary,
            unplayed: theme.colorScheme.onSurfaceVariant,
            onSeekRatio: _seek,
          ),
          const SizedBox(width: 8),
          // `.voice-message-time { font-size: 12px; opacity: 0.75 }`.
          Opacity(
            opacity: 0.75,
            child: Text(
              _formatClock(showMs),
              style: const TextStyle(fontSize: 12, color: MoshColors.fg1),
            ),
          ),
        ],
      ),
    );
  }
}

/// The voice wave: 64 buckets with a played/unplayed split, plus the seek
/// gesture. Owns its own box: the ratio is measured against the WAVE's
/// width, not the card's (`Builder` context), so a tap near the right edge
/// reports ~1.0 no matter how wide the card renders -- the React contract
/// `ratio = (clientX - rect.left) / rect.width` with `rect` = the wave.
class VoiceWaveform extends StatelessWidget {
  const VoiceWaveform({
    super.key,
    required this.peaks,
    required this.progress,
    required this.played,
    required this.unplayed,
    required this.onSeekRatio,
  });

  static const double width = 168;
  static const double height = 36;

  final Uint8List peaks;
  final double progress;
  final Color played;
  final Color unplayed;

  /// Called with the tapped position as a 0..1 fraction of the wave width.
  final ValueChanged<double> onSeekRatio;

  @override
  Widget build(BuildContext context) {
    // The Builder's context resolves to the wave's own render object: the
    // card's context would measure the whole card (the audit's HIGH finding).
    return Builder(
      builder: (context) => GestureDetector(
        onTapDown: (details) {
          final box = context.findRenderObject() as RenderBox?;
          final width = box?.size.width ?? 0;
          if (width == 0) return;
          onSeekRatio((details.localPosition.dx / width).clamp(0.0, 1.0));
        },
        child: SizedBox(
          width: width,
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
    );
  }
}

/// Draws the 64-bucket waveform with a played/unplayed split (React
/// drawWaveform): each bucket is a centered vertical bar whose height is the
/// bucket's amplitude (0..255 -> 0..height, min 2px); bars below the progress
/// use the played color, the rest the unplayed color.
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

  @override
  void paint(Canvas canvas, Size size) {
    final barWidth = size.width / _waveformBuckets;
    final playedBars = (progress * _waveformBuckets).round();
    final playedPaint = Paint()..color = played;
    final unplayedPaint = Paint()..color = unplayed;
    for (var i = 0; i < _waveformBuckets; i++) {
      final amplitude = (i < peaks.length ? peaks[i] : 0) / 255;
      final barHeight = math.max(2.0, amplitude * size.height);
      final paint = i < playedBars ? playedPaint : unplayedPaint;
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(i * barWidth + barWidth / 2, size.height / 2),
          width: barWidth * 0.6,
          height: barHeight,
        ),
        paint,
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
