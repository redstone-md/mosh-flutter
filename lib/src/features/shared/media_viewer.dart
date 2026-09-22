// Shared MediaViewer. The caller (the slice-3 attachment transfer seam)
// resolves the URL and invokes [showMediaViewer]. Image uses Image.network;
// video + audio use media_kit (Player + VideoController).
library;

import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_theme.dart'
    show MoshColors, kLiveNumberFontFeatures;

import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/shared/modal_focus_trap.dart';
import 'package:mosh/src/rust/conversation/attachments.dart';

/// Fullscreen in-app media viewer.
///
/// Construct directly and pass to `showDialog`, or use the [showMediaViewer]
/// helper which wires `onClose` to `Navigator.pop`.
/// - `descriptor` -- the `AttachmentDescriptor` (carries `mime` + `fileName`).
/// - `src`        -- the media URL.
/// - `onClose`    -- invoked by the close button, the backdrop tap, or Esc.
class MediaViewer extends StatelessWidget {
  const MediaViewer({
    super.key,
    required this.descriptor,
    required this.src,
    required this.onClose,
  });

  /// The attachment's metadata. Drives the mime
  /// branch (`descriptor.mime`) and the
  /// semantics label + caption (`descriptor.fileName`).
  final AttachmentDescriptor descriptor;

  /// The media source URL. For `image/*` this is loaded via
  /// `Image.network`; for video/audio/other it is unused by the placeholder
  /// and reserved for the slice-3 player wiring.
  final String src;

  /// Invoked when the user closes the viewer (close button, backdrop tap,
  /// or Esc via [showMediaViewer]).
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // The stage and the image/video cap at max-width 92vw, max-height 82vh.
    // `MediaQuery` gives the viewport; 0.92/0.82 map
    // the CSS vw/vh units faithfully.
    final maxStageWidth = media.size.width * 0.92;
    final maxStageHeight = media.size.height * 0.82;

    // Fade in: opacity 0 -> 1 over 0.16s ease. A
    // `TweenAnimationBuilder` keeps the widget stateless (no
    // `AnimationController` lifecycle to manage).
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 160),
      curve: Curves.ease,
      builder: (context, opacity, child) {
        return Opacity(opacity: opacity, child: child);
      },
      child: Semantics(
        // The `showDialog` host already scopes the modal route (the `Dialog`
        // route IS the modal semantics boundary),
        // so we do NOT set `scopesRoute: true` here: that requires
        // `explicitChildNodes: true` (framework assertion) AND duplicates
        // the modal-route scoping the `showDialog` host already provides.
        // Keeping `container: true, label: fileName` gives the labeled-group
        // announcement. Mirrors the ConfirmDialog's semantics approach.
        container: true,
        label: descriptor.fileName,
        // ModalFocusTrap goes inside Semantics so Tab key events are handled
        // by the trap, while Escape is caught at the ModalRoute level.
        child: ModalFocusTrap(
          child: Dialog(
            // Fullscreen: no inset padding.
            insetPadding: EdgeInsets.zero,
            backgroundColor: Colors.transparent,
            // No default Material elevation/clip on the fullscreen surface.
            elevation: 0,
            child: GestureDetector(
              // Tap the backdrop (anywhere outside the stage) closes the
              // viewer.
              behavior: HitTestBehavior.opaque,
              onTap: onClose,
              child: Stack(
                children: [
                  // A near-opaque dark scrim (rgba(8, 9, 10, 0.92)).
                  // (A `backdrop-filter: blur(6px)` nicety is deferred:
                  // Flutter `BackdropFilter` needs the ImageFilter to blur
                  // what is *behind* the route.)
                  Positioned.fill(
                    child: ColoredBox(color: const Color(0xEB08090A)),
                  ),
                  // Centered flex column, gap 14px, padding 48px 32px 32px.
                  // The Column is centered + padded; the close button is
                  // absolutely positioned over it.
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.only(
                        top: 48,
                        left: 32,
                        right: 32,
                        bottom: 32,
                      ),
                      // Wrapped in a vertical `SingleChildScrollView` so a
                      // tall image/video never overflows the viewport: when
                      // the stage + caption fit (the common case) the
                      // content stays centered; when they exceed the
                      // available height the column scrolls instead of
                      // throwing a layout overflow (Flutter errors on
                      // overflow, so scroll is the safe behavior).
                      child: Center(
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _MediaStage(
                                descriptor: descriptor,
                                src: src,
                                maxStageWidth: maxStageWidth,
                                maxStageHeight: maxStageHeight,
                              ),
                              const SizedBox(height: 14),
                              _MediaCaption(
                                fileName: descriptor.fileName,
                                maxWidth: media.size.width * 0.80,
                                fg2: MoshColors.fg2,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // The close button: absolute top 16 right 18.
                  Positioned(
                    top: 16,
                    right: 18,
                    child: _MediaCloseButton(onPressed: onClose),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The centered media stage. Tapping inside the stage does NOT close the
/// viewer (the inner `GestureDetector` swallows the tap). Branches on
/// `descriptor.mime`: `image/*` -> image, `video/*` -> video placeholder,
/// `audio/*` -> audio placeholder, else -> file placeholder.
class _MediaStage extends StatelessWidget {
  const _MediaStage({
    required this.descriptor,
    required this.src,
    required this.maxStageWidth,
    required this.maxStageHeight,
  });

  final AttachmentDescriptor descriptor;
  final String src;
  final double maxStageWidth;
  final double maxStageHeight;

  @override
  Widget build(BuildContext context) {
    final mime = descriptor.mime;
    // `isImage = mime.startsWith("image/")`, etc.
    final isImage = mime.startsWith('image/');
    final isVideo = mime.startsWith('video/');
    final isAudio = mime.startsWith('audio/');

    return GestureDetector(
      // Swallow taps so the media itself does not close the viewer.
      onTap: () {},
      behavior: HitTestBehavior.opaque,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxStageWidth,
          maxHeight: maxStageHeight,
        ),
        child: isImage
            ? _ImageStage(
                descriptor: descriptor,
                src: src,
                maxStageWidth: maxStageWidth,
                maxStageHeight: maxStageHeight,
                bg0: MoshColors.bg0,
              )
            : isVideo
                ? _VideoStage(
                    descriptor: descriptor,
                    src: src,
                    maxStageWidth: maxStageWidth,
                    maxStageHeight: maxStageHeight,
                  )
                : isAudio
                    ? _AudioStage(
                        descriptor: descriptor,
                        src: src,
                        maxStageWidth: maxStageWidth,
                      )
                    : _PlaybackPlaceholderCard(
                        fileName: descriptor.fileName,
                        // `Icons.insert_drive_file_outlined` (matches the
                        // attachment_card file-card icon choice).
                        icon: Icons.insert_drive_file_outlined,
                        bg2: MoshColors.bg2,
                      ),
      ),
    );
  }
}

/// The image branch (`max-width 92vw; max-height 82vh; object-fit:
/// contain; border-radius: 8px; background: var(--bg-0)`).
/// `Image.network` loads a URL `src`.
class _ImageStage extends StatelessWidget {
  const _ImageStage({
    required this.descriptor,
    required this.src,
    required this.maxStageWidth,
    required this.maxStageHeight,
    required this.bg0,
  });

  final AttachmentDescriptor descriptor;
  final String src;
  final double maxStageWidth;
  final double maxStageHeight;
  final Color bg0;

  /// A downloaded attachment is a `file://` URL (see `localFileSrc`), which
  /// `NetworkImage` cannot fetch: `HttpClient` rejects the scheme and the
  /// stage would show the broken-image fallback for every local picture.
  ImageProvider get _image {
    final uri = Uri.parse(src);
    return uri.scheme == 'file'
        ? FileImage(File(uri.toFilePath()))
        : NetworkImage(src);
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: ColoredBox(
        // bg-0 background behind the image.
        color: bg0,
        child: Image(
          image: _image,
          fit: BoxFit.contain,
          width: maxStageWidth,
          height: maxStageHeight,
          gaplessPlayback: true,
          // The screen reader label.
          semanticLabel: descriptor.fileName,
          errorBuilder: (context, error, stackTrace) => SizedBox(
            width: maxStageWidth,
            height: maxStageHeight,
            child: Center(
              child: Icon(
                Icons.broken_image_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The video branch (a `video` element with `src controls autoPlay`).
/// Uses media_kit: a [Player]
/// drives playback, a [VideoController] surfaces the frames to a [Video]
/// widget with MaterialVideoControls (the Material counterpart to the
/// native `controls` attribute). Constrained to the stage box so a
/// tall/wide clip never overflows the viewport (max-width 92vw;
/// max-height 82vh).
class _VideoStage extends StatefulWidget {
  const _VideoStage({
    required this.descriptor,
    required this.src,
    required this.maxStageWidth,
    required this.maxStageHeight,
  });

  final AttachmentDescriptor descriptor;
  final String src;
  final double maxStageWidth;
  final double maxStageHeight;

  @override
  State<_VideoStage> createState() => _VideoStageState();
}

class _VideoStageState extends State<_VideoStage> {
  Player? _player;
  VideoController? _controller;

  @override
  void initState() {
    super.initState();
    // media_kit needs its native lib; in test envs without it (or on an
    // unsupported platform) Player() throws -- fall back to the placeholder
    // card so the viewer still renders. Opens + plays immediately on the
    // happy path.
    try {
      final player = Player();
      _player = player;
      _controller = VideoController(player);
      player.open(Media(widget.src));
    } catch (_) {
      _player = null;
      _controller = null;
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      // Fallback (test env / unsupported platform) -- the same placeholder
      // card the viewer used before the slice-3 player wiring.
      return _PlaybackPlaceholderCard(
        fileName: widget.descriptor.fileName,
        icon: Icons.play_circle_filled,
        bg2: MoshColors.bg2,
      );
    }
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: widget.maxStageWidth,
        maxHeight: widget.maxStageHeight,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Video(
          controller: controller,
          // Material controls (play/pause/seek/volume
          // + fullscreen), the closest native counterpart.
          controls: MaterialVideoControls,
          fill: Colors.transparent,
        ),
      ),
    );
  }
}

/// The audio stage's live "m:ss / m:ss" label, extracted so the format and
/// the tabular figures are testable without the media_kit native library
/// (the stage falls back to a placeholder where the player is unavailable).
/// Tabular figures: the digits change on every position tick, and
/// proportional numerals reflow the fixed 80px box (audit 2026-09-21).
class MediaAudioTimeLabel extends StatelessWidget {
  const MediaAudioTimeLabel({
    super.key,
    required this.position,
    required this.duration,
  });

  final Duration position;
  final Duration duration;

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60);
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    // Scale down instead of wrapping: the fixed 80px slot keeps the controls
    // row's height stable even for recordings of 100+ minutes, where
    // "133:00 / 135:00" exceeds the slot (CodeAnt PR #12).
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        '${_fmt(position)} / ${_fmt(duration)}',
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(fontFeatures: kLiveNumberFontFeatures),
        textAlign: TextAlign.center,
      ),
    );
  }
}

/// The audio branch (play icon + strong file_name + an `audio` element
/// with `src controls autoPlay`). Uses media_kit [Player] (audio-only --
/// no VideoController); a minimal control row (play/pause + seek Slider +
/// position/duration label) stands in for the native `audio controls`
/// affordance since media_kit ships no ready audio-controls widget.
/// Listens to the player stream for live position + duration.
class _AudioStage extends StatefulWidget {
  const _AudioStage({
    required this.descriptor,
    required this.src,
    required this.maxStageWidth,
  });

  final AttachmentDescriptor descriptor;
  final String src;
  final double maxStageWidth;

  @override
  State<_AudioStage> createState() => _AudioStageState();
}

class _AudioStageState extends State<_AudioStage> {
  Player? _player;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    // media_kit needs its native lib; in test envs without it Player()
    // throws -- fall back to the placeholder card. Opens + plays on the
    // happy path.
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
      player.open(Media(widget.src));
    } catch (_) {
      _player = null;
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final player = _player;
    if (player == null) {
      // Fallback (test env / unsupported platform).
      return _PlaybackPlaceholderCard(
        fileName: widget.descriptor.fileName,
        icon: Icons.play_circle_filled,
        bg2: MoshColors.bg2,
      );
    }
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: widget.maxStageWidth),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
        // `.media-viewer-audio { padding: 32px 40px; border: 1px solid
        // var(--line); border-radius: 14px; background: var(--bg-2) }`.
        decoration: BoxDecoration(
          color: MoshColors.bg2,
          border: Border.all(color: MoshColors.line),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              Icons.play_circle_filled,
              size: 32,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 14),
            Text(
              widget.descriptor.fileName,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                IconButton(
                  icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                  onPressed: () => player.playOrPause(),
                ),
                Expanded(
                  child: Slider(
                    value: _position.inMilliseconds.toDouble(),
                    min: 0,
                    max: _duration.inMilliseconds.toDouble().clamp(
                          1,
                          double.infinity,
                        ),
                    onChanged: (value) =>
                        player.seek(Duration(milliseconds: value.round())),
                  ),
                ),
                SizedBox(
                  width: 80,
                  child: MediaAudioTimeLabel(
                    position: _position,
                    duration: _duration,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The video / audio / other placeholder card
/// (`display:flex; flex-direction:column; align-items:center; gap:14px;
/// padding:32px 40px; border:1px var(--line); border-radius:14px;
/// background:var(--bg-2); color:var(--moss)`; `strong` -> `color:var(--fg-1);
/// font-size:13px`). Used for video, audio, and the "other" file branch
/// (each with a different icon). A real player is a slice-3 follow-up.
class _PlaybackPlaceholderCard extends StatelessWidget {
  const _PlaybackPlaceholderCard({
    required this.fileName,
    required this.icon,
    required this.bg2,
  });

  final String fileName;
  final IconData icon;
  final Color bg2;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
      decoration: BoxDecoration(
        // bg-2 background.
        color: bg2,
        // 1px line border.
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        // 14px gap between icon and file name.
        children: [
          Icon(
            // Play icon (video/audio) or file icon (other).
            icon,
            size: 32,
            // Moss accent. Material has no
            // per-app moss token; the theme primary is the closest accent.
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 14),
          Text(
            fileName,
            // fg-1, 13px, bold.
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: theme.colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ],
      ),
    );
  }
}

/// The caption
/// (`max-width:80vw; color:var(--fg-2); font-size:12.5px; text-align:center`).
class _MediaCaption extends StatelessWidget {
  const _MediaCaption({
    required this.fileName,
    required this.maxWidth,
    required this.fg2,
  });

  final String fileName;
  final double maxWidth;
  final Color fg2;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Text(
        fileName,
        style: TextStyle(
          fontSize: 12.5,
          // Muted fg-2.
          color: fg2,
        ),
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
        maxLines: 2,
      ),
    );
  }
}

/// The close button
/// (`position:absolute; top:16px; right:18px; width:36px; height:36px;
/// display:grid; place-items:center; border:1px var(--line);
/// border-radius:9px; background:var(--bg-2); color:var(--fg-2)`;
/// `IconX size=18`). Hover swaps to `bg-3/fg-1`
/// -- Material's `IconButton` hover/inherited state covers that.
class _MediaCloseButton extends StatelessWidget {
  const _MediaCloseButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Semantics(
      // "Close viewer", localized via the `closeViewer` ARB key.
      label: l.closeViewer,
      button: true,
      child: Tooltip(
        message: l.closeViewer,
        child: Material(
          // bg-2 background; 1px line border; 9px border-radius.
          // A custom Container (not IconButton) so the
          // 36x36 bordered square is exact -- IconButton's
          // default splash/padding would not match.
          color: theme.colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9),
            side: BorderSide(color: theme.dividerColor),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: SizedBox(
              width: 36,
              height: 36,
              child: Icon(
                Icons.close,
                size: 18,
                // Muted fg-2.
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows a [MediaViewer] as a fullscreen modal. The caller resolves the
/// descriptor + src and calls this helper; `onClose` pops the route. The
/// barrier is dismissible (click-outside + Esc), so both the close button
/// and the backdrop close the viewer.
///
/// `barrierLabel` is the localized `closeViewer` string so the modal scrim
/// announces itself as a close affordance to assistive tech.
Future<void> showMediaViewer({
  required BuildContext context,
  required AttachmentDescriptor descriptor,
  required String src,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: AppLocalizations.of(context)!.closeViewer,
    builder: (dialogContext) => MediaViewer(
      descriptor: descriptor,
      src: src,
      onClose: () => Navigator.of(dialogContext).pop(),
    ),
  );
}
