import 'dart:async' show unawaited;
import 'dart:convert' show base64Decode;
import 'dart:math' as math;
import 'dart:typed_data' show Uint8List;

import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_theme.dart'
    show MoshColors, kLiveNumberFontFeatures;

import 'package:media_kit/media_kit.dart';

import 'package:mosh/src/features/shared/voice_composer.dart'
    show formatVoiceClock, waveformBuckets;
import 'package:mosh/src/features/shared/contextual_icon_switcher.dart';
import 'package:mosh/src/features/shared/press_scale.dart';
import 'conversation_attachment.dart';
import 'conversation_state.dart' show ConversationPendingDropped;

import 'package:mosh/src/rust/conversation/attachments.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/util/format.dart' show formatBytes;

/// Decode the base64 peaks. Malformed -> flat zeros, never fatal.
Uint8List _peaksFromBase64(String? b64) {
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

/// Plays a local voice message or downloads it when the user presses play.
class VoiceMessageCard extends StatefulWidget {
  const VoiceMessageCard({
    super.key,
    required this.descriptor,
    required this.view,
    required this.busy,
    required this.onDownload,
    required this.playLabel,
    required this.pauseLabel,
    this.own = false,
    this.messageFooter,
    this.createPlayer,
  });

  final AttachmentDescriptor descriptor;
  final AttachmentView? view;
  final bool own;
  final bool busy;
  final void Function(String attachmentId) onDownload;

  final String playLabel;
  final String pauseLabel;
  final Widget? messageFooter;

  /// Uses media_kit's existing platform-player seam in headless tests.
  final Player Function()? createPlayer;

  @override
  State<VoiceMessageCard> createState() => _VoiceMessageCardState();
}

class _VoiceMessageCardState extends State<VoiceMessageCard> {
  ConversationAttachment get _attachment => ConversationAttachment(
      descriptor: widget.descriptor, view: widget.view, own: widget.own);
  Player? _player;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  String? _loadedPath;
  String? _openingPath;
  // A play request survives download and load failure until playback succeeds.
  bool _playWhenReady = false;

  void _ifMounted(VoidCallback fn) {
    if (mounted) fn();
  }

  @override
  void initState() {
    super.initState();
    // The card still renders when native playback is unavailable.
    try {
      final player = (widget.createPlayer ?? Player.new)();
      _player = player;
      player.stream.playing.listen((playing) {
        _ifMounted(() => setState(() => _playing = playing));
      });
      player.stream.position.listen((pos) {
        _ifMounted(() => setState(() => _position = pos));
      });
      player.stream.duration.listen((dur) {
        _ifMounted(() => setState(() => _duration = dur));
      });
    } catch (_) {
      _player = null;
    }
  }

  @override
  void didUpdateWidget(covariant VoiceMessageCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_attachment.resolvePendingOpen() is ConversationPendingDropped) {
      _playWhenReady = false;
    }
    final newPath = _attachment.localPath;
    final oldPath = ConversationAttachment(
            descriptor: oldWidget.descriptor,
            view: oldWidget.view,
            own: oldWidget.own)
        .localPath;
    if (newPath != null && newPath != oldPath) {
      unawaited(_open(newPath));
    }
  }

  Future<void> _open(String path) async {
    final player = _player;
    if (player == null || _openingPath == path) return;
    _openingPath = path;
    try {
      await player.open(Media(path), play: false);
      if (!mounted || _attachment.localPath != path) return;
      _loadedPath = path;
      if (_playWhenReady) {
        await player.play();
        _playWhenReady = false;
      }
    } catch (_) {
      // Keep the request so the next play tap retries loading.
    } finally {
      if (_openingPath == path) _openingPath = null;
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  /// Tapping play before the file is local starts its download (once).
  void _requestDownload() {
    if (_attachment.progress == null) {
      widget.onDownload(widget.descriptor.attachmentId);
    }
  }

  Future<void> _toggle() async {
    final player = _player;
    final localPath = _attachment.localPath;
    if (localPath == null) {
      if (_attachment.outgoing) return;
      _playWhenReady = true;
      _requestDownload();
      return;
    }
    if (player == null) return;
    if (_loadedPath != localPath) {
      _playWhenReady = true;
      await _open(localPath);
      return;
    }
    try {
      await player.playOrPause();
      if (mounted) _playWhenReady = false;
    } catch (_) {
      // A failed queued request remains available for another play tap.
    }
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
    final progress = durationMs > 0
        ? (math.min(1.0, _position.inMilliseconds / durationMs))
        : 0.0;
    final showMs = (_playing || _position.inMilliseconds > 0)
        ? _position.inMilliseconds
        : durationMs;
    final playLabel = _playing ? widget.pauseLabel : widget.playLabel;
    final enabled =
        _attachment.localPath != null || !(widget.busy || _attachment.outgoing);
    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Opacity(
            opacity: enabled ? 1 : 0.65,
            child: PressScale(
              enabled: enabled,
              child: Material(
                color: theme.colorScheme.primary,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: enabled ? _toggle : null,
                  child: Tooltip(
                    message: playLabel,
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: Center(
                        child: ContextualIconSwitcher(
                          icon: _playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: 18,
                          color: theme.colorScheme.onPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                VoiceWaveform(
                    peaks: peaks,
                    progress: progress,
                    played: theme.colorScheme.primary,
                    unplayed: theme.colorScheme.onSurfaceVariant,
                    onSeekRatio: _seek,
                    displayHeight: 22),
                const SizedBox(height: 2),
                Row(children: [
                  Expanded(
                      child: VoiceCardTimeLabel(
                          ms: showMs, totalSize: widget.descriptor.totalSize)),
                  if (widget.messageFooter case final footer?) ...[
                    const SizedBox(width: 8),
                    footer,
                  ],
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Live duration and optional file size beneath the wave, with tabular figures.
class VoiceCardTimeLabel extends StatelessWidget {
  const VoiceCardTimeLabel({super.key, required this.ms, this.totalSize});

  /// Playback position while playing/seeked, otherwise the full duration.
  final int ms;
  final BigInt? totalSize;

  @override
  Widget build(BuildContext context) {
    final size = totalSize;
    final time = formatVoiceClock(ms);
    final sizeText = size == null
        ? null
        : formatBytes(size,
            decimalPlaces: 1,
            locale: AppLocalizations.of(context)?.localeName ?? 'en');
    final label =
        sizeText == null ? time : '${time.padLeft(5, '0')} · $sizeText';
    return Opacity(
      opacity: 0.75,
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 12,
          color: MoshColors.fg1,
          fontFeatures: kLiveNumberFontFeatures,
        ),
      ),
    );
  }
}

/// Waveform seeking measures its own width, independently of the card.
class VoiceWaveform extends StatelessWidget {
  const VoiceWaveform({
    super.key,
    required this.peaks,
    required this.progress,
    required this.played,
    required this.unplayed,
    required this.onSeekRatio,
    this.displayHeight,
  });

  static const double width = 168;
  static const double height = 36;

  final Uint8List peaks;
  final double progress;
  final Color played;
  final Color unplayed;
  final double? displayHeight;

  /// Called with the tapped position as a 0..1 fraction of the wave width.
  final ValueChanged<double> onSeekRatio;

  @override
  Widget build(BuildContext context) {
    // Measure the waveform's render object.
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
          height: displayHeight ?? height,
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

/// Draws 64 amplitude bars, marking the played portion in its own color.
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
    final barWidth = size.width / waveformBuckets;
    final playedBars = (progress * waveformBuckets).round();
    final playedPaint = Paint()..color = played;
    final unplayedPaint = Paint()..color = unplayed;
    for (var i = 0; i < waveformBuckets; i++) {
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
