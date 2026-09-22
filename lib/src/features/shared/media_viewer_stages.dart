// Stages of the [MediaViewer]: the media_kit-backed video + audio branches
// and the shared playback placeholder. A `part` of media_viewer.dart so the
// stage widgets stay library-private while the file stays under the 400-line
// repo cap.
part of 'media_viewer.dart';

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
  VideoController? _controller;
  Player? _player;

  @override
  void initState() {
    super.initState();
    // media_kit needs its native lib; in test envs without it (or on an
    // unsupported platform) Player() throws -- fall back to the placeholder
    // card so the viewer still renders. Opens + plays immediately on the
    // happy path. The open is awaited INSIDE the stage: a Player() that
    // constructs but fails asynchronously (missing codec, unreadable src)
    // must land in the same catch, so the viewer renders the fallback card
    // instead of surfacing an unhandled error.
    try {
      final player = Player();
      _player = player;
      final controller = VideoController(player);
      _controller = controller;
      unawaited(_open(player));
    } catch (_) {
      _player = null;
      _controller = null;
    }
  }

  /// Opens + plays the stage's media. An asynchronous open failure is not
  /// a constructor throw: it surfaces here, after the stage is live, so
  /// the catch drops back to the placeholder card.
  Future<void> _open(Player player) async {
    try {
      await player.open(Media(widget.src));
    } catch (_) {
      await player.dispose();
      if (mounted) {
        setState(() {
          _player = null;
          _controller = null;
        });
      }
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
    // media_kit needs its native lib; in test envs without it (or on an
    // unsupported platform) Player() throws -- fall back to the placeholder
    // card. Opens + plays on the happy path. The open is awaited INSIDE the
    // stage: a Player() that constructs but fails asynchronously (missing
    // codec, unreadable src) must land in the same catch, so the viewer
    // renders the fallback card instead of surfacing an unhandled error.
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
      unawaited(_open(player));
    } catch (_) {
      _player = null;
    }
  }

  /// Opens + plays the stage's media. An asynchronous open failure is not
  /// a constructor throw: it surfaces here, after the stage is live, so
  /// the catch drops back to the placeholder card.
  Future<void> _open(Player player) async {
    try {
      await player.open(Media(widget.src));
    } catch (_) {
      await player.dispose();
      if (mounted) setState(() => _player = null);
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
