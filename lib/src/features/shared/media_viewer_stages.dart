part of 'media_viewer.dart';

/// A stage that plays the attachment in a player of its own, from the
/// moment it opens. Where no player can be made (a test host without
/// libmpv) or the player cannot open the source (a missing codec, an
/// unreadable file), the stage shows the file's card instead.
class _PlayingStage extends StatefulWidget {
  const _PlayingStage({
    required this.descriptor,
    required this.src,
    required this.createPlayer,
    required this.video,
    required this.builder,
  });

  final AttachmentDescriptor descriptor;
  final String src;
  final MediaPlayerFactory createPlayer;

  /// Whether the attachment is watched rather than only heard.
  final bool video;

  /// What the stage shows of its player. Called once.
  final Widget Function(Player player) builder;

  @override
  State<_PlayingStage> createState() => _PlayingStageState();
}

class _PlayingStageState extends State<_PlayingStage> {
  Player? _player;

  /// What the builder made; null where the attachment cannot play.
  Widget? _playing;

  @override
  void initState() {
    super.initState();
    try {
      final player = _player = widget.createPlayer(video: widget.video);
      _playing = widget.builder(player);
      unawaited(_open(player));
    } catch (_) {
      unawaited(_player?.dispose());
      _player = null;
    }
  }

  /// A source the player cannot open fails here, after the stage is live.
  Future<void> _open(Player player) async {
    try {
      await player.open(Media(widget.src));
    } catch (_) {
      // A stage already disposed has let its player go.
      if (!mounted) return;
      setState(() => _player = _playing = null);
      await player.dispose();
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _playing ??
      _PlaybackPlaceholderCard(
        fileName: widget.descriptor.fileName,
        icon: Icons.play_circle_filled,
      );
}

/// A video's picture with its controls, in the box the stage constrains so
/// a tall or wide clip never overflows the viewport (max-width 92vw;
/// max-height 82vh). libmpv's player brings media_kit's picture and
/// Material controls; the system's player on Android gets [_SystemVideo].
Widget _videoPicture(Player player) => ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: switch (player.platform) {
        final SystemPlayer system =>
          _SystemVideo(player: player, system: system),
        _ => Video(
            controller: VideoController(player),
            controls: MaterialVideoControls,
            fill: Colors.transparent,
          ),
      },
    );

/// A video in the system's player: its picture, which a tap pauses, over
/// the viewer's own controls, as video_player draws none. A spinner shows
/// while the video opens or waits for its stream. The display stays awake
/// while the video is open, as media_kit's picture keeps it.
class _SystemVideo extends StatefulWidget {
  const _SystemVideo({required this.player, required this.system});

  final Player player;
  final SystemPlayer system;

  @override
  State<_SystemVideo> createState() => _SystemVideoState();
}

class _SystemVideoState extends State<_SystemVideo> {
  @override
  void initState() {
    super.initState();
    unawaited(WakelockPlus.enable());
  }

  @override
  void dispose() {
    unawaited(WakelockPlus.disable());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = widget.player;
    return ColoredBox(
      color: MoshColors.bg2,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: ValueListenableBuilder(
              valueListenable: widget.system.opened,
              // Without a picture, after the system gave up on the video,
              // the controls below open it again.
              builder: (context, video, waiting) => AspectRatio(
                aspectRatio: video?.value.aspectRatio ?? 16 / 9,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (video != null)
                      Positioned.fill(
                        child: GestureDetector(
                          onTap: player.playOrPause,
                          child: VideoPlayer(video),
                        ),
                      ),
                    waiting!,
                  ],
                ),
              ),
              child: StreamBuilder(
                stream: player.stream.buffering,
                initialData: player.state.buffering,
                builder: (context, waiting) => waiting.requireData
                    ? const CircularProgressIndicator()
                    : const SizedBox.shrink(),
              ),
            ),
          ),
          _PlaybackControls(player: player),
        ],
      ),
    );
  }
}

/// An audio attachment: a card with a play icon, the file's name and the
/// controls.
class _AudioCard extends StatelessWidget {
  const _AudioCard({required this.fileName, required this.player});

  final String fileName;
  final Player player;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
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
            fileName,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 14),
          _PlaybackControls(player: player),
        ],
      ),
    );
  }
}

class _PlaybackPlaceholderCard extends StatelessWidget {
  const _PlaybackPlaceholderCard({
    required this.fileName,
    required this.icon,
  });

  final String fileName;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
      decoration: BoxDecoration(
        color: MoshColors.bg2,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
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
