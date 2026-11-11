part of 'media_viewer.dart';

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
          child: MediaTimeLabel(position: position, duration: duration),
        ),
      ],
    );
  }
}

/// The controls' live "m:ss / m:ss" label, on its own so the format and the
/// tabular figures are testable where no player is available.
/// Tabular figures: the digits change on every position tick, and
/// proportional numerals reflow the fixed 80px box (audit 2026-09-21).
class MediaTimeLabel extends StatelessWidget {
  const MediaTimeLabel({
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
