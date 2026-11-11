part of 'media_viewer.dart';

/// The video branch: the attachment plays as soon as it opens, in a box
/// the stage constrains so a tall or wide clip never overflows the
/// viewport (max-width 92vw; max-height 82vh). libmpv's player brings
/// media_kit's picture and Material controls; the system's player on
/// Android gets [_SystemVideo].
class _VideoStage extends StatefulWidget {
  const _VideoStage({
    required this.descriptor,
    required this.src,
    required this.createPlayer,
  });

  final AttachmentDescriptor descriptor;
  final String src;
  final MediaPlayerFactory createPlayer;

  @override
  State<_VideoStage> createState() => _VideoStageState();
}

class _VideoStageState extends State<_VideoStage> {
  Player? _player;

  /// The picture with its controls; null where the video cannot play.
  Widget? _picture;

  @override
  void initState() {
    super.initState();
    // Where no player can be made (a test host without libmpv) the stage
    // shows the file's card instead.
    try {
      final player = widget.createPlayer(video: true);
      _player = player;
      _picture = switch (player.platform) {
        final SystemPlayer system =>
          _SystemVideo(player: player, system: system),
        _ => Video(
            controller: VideoController(player),
            controls: MaterialVideoControls,
            fill: Colors.transparent,
          ),
      };
      unawaited(_open(player));
    } catch (_) {
      _player = null;
      _picture = null;
    }
  }

  /// Opens and plays the media. A source the player cannot open (a missing
  /// codec, an unreadable file) fails here, after the stage is live, and
  /// the stage drops back to the file's card.
  Future<void> _open(Player player) async {
    try {
      await player.open(Media(widget.src));
    } catch (_) {
      // A stage already disposed has let its player go.
      if (!mounted) return;
      setState(() {
        _player = null;
        _picture = null;
      });
      await player.dispose();
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final picture = _picture;
    if (picture == null) {
      return _PlaybackPlaceholderCard(
        fileName: widget.descriptor.fileName,
        icon: Icons.play_circle_filled,
      );
    }
    return ClipRRect(borderRadius: BorderRadius.circular(8), child: picture);
  }
}

/// A video in the system's player: its picture, which a tap pauses, over
/// the viewer's own controls, as video_player draws none. The display
/// stays awake while it is open, as media_kit's picture keeps it.
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
    return ValueListenableBuilder(
      valueListenable: widget.system.opened,
      builder: (context, video, _) {
        if (video == null) {
          return const Padding(
            padding: EdgeInsets.all(48),
            child: CircularProgressIndicator(),
          );
        }
        return ColoredBox(
          color: MoshColors.bg2,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: AspectRatio(
                  aspectRatio: video.value.aspectRatio,
                  child: GestureDetector(
                    onTap: widget.player.playOrPause,
                    child: VideoPlayer(video),
                  ),
                ),
              ),
              _PlaybackControls(player: widget.player),
            ],
          ),
        );
      },
    );
  }
}

/// The controls' live "m:ss / m:ss" label, on its own so the format and the
/// tabular figures are testable where no player is available.
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

/// Play or pause, a seek bar and the time, for a player that draws no
/// controls of its own.
class _PlaybackControls extends StatefulWidget {
  const _PlaybackControls({required this.player});

  final Player player;

  @override
  State<_PlaybackControls> createState() => _PlaybackControlsState();
}

class _PlaybackControlsState extends State<_PlaybackControls> {
  late final List<StreamSubscription<Object>> _changes;

  @override
  void initState() {
    super.initState();
    // Each change is drawn from the player's state, which also holds what
    // it reported before these controls were shown.
    void changed(Object _) => setState(() {});
    final stream = widget.player.stream;
    _changes = [
      stream.playing.listen(changed),
      stream.position.listen(changed),
      stream.duration.listen(changed),
    ];
  }

  @override
  void dispose() {
    for (final change in _changes) {
      unawaited(change.cancel());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = widget.player;
    final PlayerState(:playing, :position, :duration) = player.state;
    final length = math.max(1, duration.inMilliseconds).toDouble();
    return Row(
      children: [
        IconButton(
          icon: Icon(playing ? Icons.pause : Icons.play_arrow),
          onPressed: player.playOrPause,
        ),
        Expanded(
          child: Slider(
            value: math.min(position.inMilliseconds.toDouble(), length),
            max: length,
            onChanged: (value) =>
                player.seek(Duration(milliseconds: value.round())),
          ),
        ),
        SizedBox(
          width: 80,
          child: MediaAudioTimeLabel(position: position, duration: duration),
        ),
      ],
    );
  }
}

/// The audio branch: a card with a play icon, the file's name and the
/// controls. The attachment plays as soon as it opens.
class _AudioStage extends StatefulWidget {
  const _AudioStage({
    required this.descriptor,
    required this.src,
    required this.createPlayer,
  });

  final AttachmentDescriptor descriptor;
  final String src;
  final MediaPlayerFactory createPlayer;

  @override
  State<_AudioStage> createState() => _AudioStageState();
}

class _AudioStageState extends State<_AudioStage> {
  Player? _player;

  @override
  void initState() {
    super.initState();
    // Where no player can be made (a test host without libmpv) the stage
    // shows the file's card instead.
    try {
      final player = widget.createPlayer();
      _player = player;
      unawaited(_open(player));
    } catch (_) {
      _player = null;
    }
  }

  /// Opens and plays the media. A source the player cannot open fails
  /// here, after the stage is live, and the stage drops back to the file's
  /// card.
  Future<void> _open(Player player) async {
    try {
      await player.open(Media(widget.src));
    } catch (_) {
      // A stage already disposed has let its player go.
      if (!mounted) return;
      setState(() => _player = null);
      await player.dispose();
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
      return _PlaybackPlaceholderCard(
        fileName: widget.descriptor.fileName,
        icon: Icons.play_circle_filled,
      );
    }
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
            widget.descriptor.fileName,
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
