part of 'media_viewer.dart';

/// A stage that plays the attachment in a player of its own, from the
/// moment it opens. Where no player can be made (a test host without
/// libmpv) or the player cannot open the source (a missing codec, an
/// unreadable file), the stage shows [unavailable] instead.
class _PlayingStage extends StatefulWidget {
  const _PlayingStage({
    required this.src,
    required this.createPlayer,
    required this.builder,
    required this.unavailable,
  });

  final String src;
  final MediaPlayerFactory createPlayer;

  /// What the stage shows of its player. Called once.
  final Widget Function(Player player) builder;

  /// Says that the attachment cannot play here and offers the way out.
  final Widget unavailable;

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
      final player = _player = widget.createPlayer();
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
  Widget build(BuildContext context) => _playing ?? widget.unavailable;
}

/// A video's picture with its controls, in the box the stage constrains so
/// a tall or wide clip never overflows the viewport. libmpv's player brings media_kit's picture and
/// Material controls; the system's player on Android gets [_SystemVideo].
Widget _videoPicture(Player player) => ClipRRect(
      borderRadius: const BorderRadius.all(Radius.circular(MoshRadius.medium)),
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
/// while the video opens or waits for its stream. As media_kit's picture
/// does, it keeps the display awake while it is open and pauses the video
/// when the app goes to the background.
class _SystemVideo extends StatefulWidget {
  const _SystemVideo({required this.player, required this.system});

  final Player player;
  final SystemPlayer system;

  @override
  State<_SystemVideo> createState() => _SystemVideoState();
}

class _SystemVideoState extends State<_SystemVideo> {
  late final AppLifecycleListener _background;

  @override
  void initState() {
    super.initState();
    unawaited(WakelockPlus.enable());
    _background = AppLifecycleListener(onPause: widget.player.pause);
  }

  @override
  void dispose() {
    _background.dispose();
    unawaited(WakelockPlus.disable());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = widget.player;
    return ColoredBox(
      color: MoshLevel.panel.fill(MoshColors.of(context)),
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

/// The player of a sound: a card on the panel level with play or pause, the
/// seek bar and the time.
class _AudioCard extends StatelessWidget {
  const _AudioCard({required this.player});

  final Player player;

  @override
  Widget build(BuildContext context) {
    final colors = MoshColors.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: DecoratedBox(
        decoration: MoshLevel.card(colors,
            const BorderRadius.all(Radius.circular(MoshRadius.extraLarge))),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
              MoshSpace.s3, MoshSpace.s3, MoshSpace.s5, MoshSpace.s3),
          // A slider is as tall as it is allowed to be: the column lets
          // the controls keep their own height.
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [_PlaybackControls(player: player)],
          ),
        ),
      ),
    );
  }
}

/// A message in place of media the viewer cannot show, with the way out:
/// saving the file to open it elsewhere.
class _Unavailable extends StatelessWidget {
  const _Unavailable({
    required this.icon,
    required this.title,
    required this.line,
    required this.onSave,
  });

  final IconData icon;
  final String title;
  final String line;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final colors = MoshColors.of(context);
    final text = Theme.of(context).textTheme;
    return SizedBox(
      width: 300,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: MoshSpace.s2,
        children: [
          Icon(icon, size: MoshSpace.s10, color: colors.onSurfaceVariant),
          Text(title,
              textAlign: TextAlign.center,
              style: text.titleMedium?.copyWith(color: colors.onSurface)),
          // A file still arriving cannot be saved yet: no way out to offer.
          if (onSave != null) ...[
            Text(line,
                textAlign: TextAlign.center,
                style:
                    text.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
            Padding(
              padding: const EdgeInsets.only(top: MoshSpace.s2),
              child: OutlinedButton.icon(
                onPressed: onSave,
                icon: const Icon(MoshIcons.download),
                label: Text(AppLocalizations.of(context)!.mediaViewerSave),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
