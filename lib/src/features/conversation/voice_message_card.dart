import 'dart:async' show unawaited;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_theme.dart' show kLiveNumberFontFeatures;

import 'package:media_kit/media_kit.dart';

import 'package:mosh/src/features/shared/media_player.dart';
import 'package:mosh/src/features/shared/voice_composer.dart'
    show formatVoiceClock;
import 'package:mosh/src/features/shared/contextual_icon_switcher.dart';
import 'package:mosh/src/features/shared/press_scale.dart';
import 'conversation_attachment.dart';
import 'message_tone.dart';
import 'voice_waveform.dart';
import 'conversation_state.dart' show ConversationPendingDropped;

import 'package:mosh/src/rust/conversation/attachments.dart';
import 'package:mosh/l10n/app_localizations.dart';

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
    this.createPlayer = createMediaPlayer,
  });

  final AttachmentDescriptor descriptor;
  final AttachmentView? view;
  final bool own;
  final bool busy;
  final void Function(String attachmentId) onDownload;

  final String playLabel;
  final String pauseLabel;
  final Widget? messageFooter;

  /// Makes the card's player; tests pass their own.
  final MediaPlayerFactory createPlayer;

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
    // The card still renders where no player can be made.
    try {
      final player = widget.createPlayer();
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

  /// A transfer that failed or was stopped has no audio to play: the
  /// button tries again.
  bool get _failed =>
      _attachment.failed || _attachment.state == AttachmentState.cancelled;

  /// The audio is still arriving: the button spins.
  bool get _loading => _attachment.progress != null;

  int get _durationMs => widget.descriptor.voice?.durationMs ?? 0;

  /// How long the message is, how far it has played, or why it cannot.
  String _detail(AppLocalizations l) {
    if (_failed) return l.attachmentMediaFailed;
    if (_loading) return l.voiceMessageLoading;
    final length = formatVoiceClock(_durationMs);
    return _playing || _position.inMilliseconds > 0
        ? '${formatVoiceClock(_position.inMilliseconds)} / $length'
        : length;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final tone = MessageTone.of(context, own: widget.own);
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: MoshSpace.s3,
      children: [
        _VoiceButton(
          tone: tone,
          glyph: _failed
              ? MoshIcons.refresh
              : _playing
                  ? MoshIcons.pause
                  : MoshIcons.play,
          label: _failed
              ? l.attachmentRetry
              : _playing
                  ? widget.pauseLabel
                  : widget.playLabel,
          loading: _loading,
          onPressed: !_loading &&
                  (_attachment.localPath != null ||
                      !(widget.busy || _attachment.outgoing))
              ? _toggle
              : null,
        ),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: MoshSpace.s1,
            children: [
              VoiceWaveform(
                  peaks:
                      voicePeaksFromBase64(widget.descriptor.voice?.peaksB64),
                  progress: _durationMs > 0
                      ? math.min(1.0, _position.inMilliseconds / _durationMs)
                      : 0.0,
                  played: tone.accent,
                  unplayed: tone.rest,
                  onSeekRatio: _seek),
              // The detail is the card's last line, which the time of a
              // voice message alone ends.
              ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: VoiceWaveform.width),
                child: Row(spacing: MoshSpace.s2, children: [
                  Expanded(
                    child: VoiceCardTimeLabel(
                        label: _detail(l),
                        color: _failed ? tone.error : tone.quiet),
                  ),
                  if (widget.messageFooter case final footer?) footer,
                ]),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The one round button of a voice message: play and pause, try again, or
/// a spinner while the audio is still arriving. It fades when there is
/// nothing it can do.
class _VoiceButton extends StatelessWidget {
  const _VoiceButton({
    required this.tone,
    required this.glyph,
    required this.label,
    required this.loading,
    required this.onPressed,
  });

  final MessageTone tone;
  final IconData glyph;
  final String label;
  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled || loading ? 1 : MoshState.disabledContent,
      child: PressScale(
        enabled: enabled,
        child: Material(
          color: tone.accent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            overlayColor: MoshState.layer(tone.onAccent),
            onTap: onPressed,
            child: Tooltip(
              message: label,
              child: SizedBox.square(
                dimension: MoshControl.height(Theme.of(context).platform),
                child: Center(
                  child: loading
                      ? SizedBox.square(
                          dimension: MoshSpace.s5,
                          child: CircularProgressIndicator(
                              strokeWidth: MoshBorder.thick,
                              color: tone.onAccent),
                        )
                      : ContextualIconSwitcher(
                          icon: glyph,
                          size: MoshSpace.s5,
                          color: tone.onAccent),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The line under the wave: how long the message is, how far it has played,
/// or why it cannot play. Its figures are tabular, as they tick.
class VoiceCardTimeLabel extends StatelessWidget {
  const VoiceCardTimeLabel({super.key, required this.label, this.color});

  final String label;

  /// The quiet ink of the bubble; the theme's own when left out.
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context)
            .textTheme
            .labelSmall!
            .copyWith(color: color, fontFeatures: kLiveNumberFontFeatures),
      );
}
