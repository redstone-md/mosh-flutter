import 'dart:async' show StreamSubscription, unawaited;
import 'dart:typed_data' show Uint8List;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_shapes.dart';
import 'package:mosh/src/app/mosh_theme.dart'
    show MoshColors, kLiveNumberFontFeatures;
import 'package:mosh/src/features/shared/composer_send_button.dart';
import 'package:mosh/src/features/shared/contextual_icon_switcher.dart';
import 'package:mosh/src/features/shared/media_player.dart';
import 'package:mosh/src/features/shared/voice_composer_types.dart';
import 'package:mosh/src/features/shared/voice_recording.dart';
import 'package:mosh/src/features/shared/voice_waveform.dart';
import 'package:mosh/src/rust/api/audio_devices.dart' show audioInputDeviceId;
import 'package:mosh/src/rust/api/voice_clip.dart' show joinVoiceSegments;

export 'package:mosh/src/features/shared/voice_composer_types.dart';

/// The voice half of the Composer card. At rest it shows [idle], the row
/// its owner draws around the microphone it is handed. A press on the
/// microphone turns the whole row into the recording, as Telegram's locked
/// recording does: the clock, Cancel, pause and send. A paused recording
/// can be listened to, continued, sent or thrown away.
///
/// Stateless from the screen's view: it owns the recording and hands a
/// ready-to-send [VoiceSend] to [onSend].
class VoiceComposer extends StatefulWidget {
  const VoiceComposer({
    super.key,
    required this.disabled,
    required this.labels,
    required this.onSend,
    required this.onError,
    required this.idle,
    this.inputDeviceId = audioInputDeviceId,
    this.createPlayer = createMediaPlayer,
    this.joinSegments = joinVoiceSegments,
  });

  /// Whether the microphone takes a press.
  final bool disabled;
  final VoiceComposerLabels labels;
  final void Function(VoiceSend voice) onSend;
  final void Function(String message) onError;

  /// The row shown while nothing is recorded, around the microphone.
  final Widget Function(BuildContext context, Widget microphone) idle;

  /// Reads the stored input-device pick (audio-devices.json) for the
  /// capture config. Injectable so tests (no cdylib) pass a plain getter;
  /// production uses the frb store read. Null return = platform default.
  final String? Function() inputDeviceId;

  /// Makes the player a paused recording is listened to with; tests pass
  /// their own.
  final MediaPlayerFactory createPlayer;

  /// Joins a resumed recording into one clip; tests (no cdylib) pass their
  /// own.
  final VoiceSegmentJoin joinSegments;

  @override
  State<VoiceComposer> createState() => _VoiceComposerState();
}

class _VoiceComposerState extends State<VoiceComposer> {
  late final VoiceRecording _recording = VoiceRecording(
    inputDeviceId: () => widget.inputDeviceId(),
    join: ({required segments, required output}) =>
        widget.joinSegments(segments: segments, output: output),
    canCapture: () => mounted && Visibility.of(context),
    onPermissionDenied: () => widget.onError(widget.labels.permissionDenied),
    onError: (error) => widget.onError(error.toString()),
  );
  late final _ClipPlayer _listening =
      _ClipPlayer(create: () => widget.createPlayer());

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Hidden controls leave neither the microphone capturing nor the
    // recording playing unattended.
    if (Visibility.of(context)) return;
    _listening.close();
    unawaited(_recording.pause());
  }

  @override
  void dispose() {
    _listening.dispose();
    _recording.dispose();
    super.dispose();
  }

  /// Lets go of the clip's player before the clip changes.
  Future<void> _afterListening(Future<void> Function() action) {
    _listening.close();
    return action();
  }

  Future<void> _send() => _afterListening(() async {
        final voice = await _recording.finish();
        if (voice != null) widget.onSend(voice);
      });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([_recording, _listening]),
        builder: (context, _) => AnimatedSwitcher(
          duration: MoshMotion.effectsFast.duration,
          switchInCurve: MoshMotion.effectsFast.curve,
          switchOutCurve: MoshMotion.effectsFast.curve,
          // A fade that hides a clear row from semantics trips the
          // framework's tree check on the swap: the new row is read at once.
          transitionBuilder: (row, animation) => FadeTransition(
            opacity: animation,
            alwaysIncludeSemantics: true,
            child: row,
          ),
          // The row on its way out is neither pressed nor read aloud.
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.center,
            children: [
              for (final row in previous)
                IgnorePointer(child: ExcludeSemantics(child: row)),
              if (current != null) current,
            ],
          ),
          child: KeyedSubtree(
            key: ValueKey<VoiceRecordingPhase>(_recording.phase),
            child: switch (_recording.phase) {
              VoiceRecordingPhase.idle => widget.idle(context, _microphone()),
              VoiceRecordingPhase.recording => _recordingRow(context),
              VoiceRecordingPhase.paused => _pausedRow(),
            },
          ),
        ),
      );

  Widget _microphone() => IconButton(
        icon: const Icon(MoshIcons.mic),
        tooltip: widget.labels.record,
        onPressed: widget.disabled ? null : _recording.start,
      );

  /// Send rests with the microphone: while another send is on its way.
  VoidCallback? get _sendPressed => widget.disabled ? null : _unlessBusy(_send);

  VoidCallback? _unlessBusy(VoidCallback action) =>
      _recording.busy ? null : action;

  /// The Recording state of the card: the clock, Cancel, pause and send.
  Widget _recordingRow(BuildContext context) {
    final labels = widget.labels;
    return Row(
      spacing: MoshShapes.composerGap,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: MoshSpace.s4),
            child: Row(
              spacing: MoshSpace.s2,
              children: [
                const VoiceRecordingDot(),
                Text(
                  formatVoiceClock(_recording.elapsed.inMilliseconds),
                  style: Theme.of(context).textTheme.labelLarge!.copyWith(
                        color: MoshColors.of(context).onSurface,
                        fontFeatures: kLiveNumberFontFeatures,
                      ),
                ),
              ],
            ),
          ),
        ),
        TextButton(
          onPressed: _unlessBusy(_recording.cancel),
          child: Text(labels.cancel),
        ),
        IconButton(
          icon: const Icon(MoshIcons.pause),
          tooltip: labels.pause,
          onPressed: _unlessBusy(_recording.pause),
        ),
        ComposerSendButton(label: labels.send, onPressed: _sendPressed),
      ],
    );
  }

  /// The Recorded state of the card: the recording to listen to, between
  /// the ways to throw it away, to go on with it and to send it.
  Widget _pausedRow() {
    final labels = widget.labels;
    return Row(
      spacing: MoshShapes.composerGap,
      children: [
        IconButton(
          icon: const Icon(MoshIcons.delete),
          tooltip: labels.discard,
          onPressed: _unlessBusy(() => _afterListening(_recording.cancel)),
        ),
        Expanded(
          child: _RecordedTake(
            label: _listening.playing ? labels.pausePlayback : labels.play,
            playing: _listening.playing,
            played: _listening.played,
            peaks: _recording.peaks,
            durationMs: _recording.elapsed.inMilliseconds,
            onPressed: _unlessBusy(
                () => _listening.toggle(_recording.clip, _recording.elapsed)),
          ),
        ),
        IconButton(
          icon: const Icon(MoshIcons.mic),
          tooltip: labels.resume,
          onPressed: widget.disabled || !_recording.canResume
              ? null
              : _unlessBusy(() => _afterListening(_recording.resume)),
        ),
        ComposerSendButton(label: labels.send, onPressed: _sendPressed),
      ],
    );
  }
}

/// The recording itself, as the card draws a paused one: a capsule that
/// plays it when pressed, with its waveform and its length.
class _RecordedTake extends StatelessWidget {
  const _RecordedTake({
    required this.label,
    required this.playing,
    required this.played,
    required this.peaks,
    required this.durationMs,
    required this.onPressed,
  });

  final String label;
  final bool playing;
  final double played;
  final Uint8List peaks;
  final int durationMs;
  final VoidCallback? onPressed;

  /// The bars keep their pitch: a narrow capsule cuts the wave where it
  /// ends.
  Widget _wave(MoshColors c) => ClipRect(
        child: OverflowBox(
          alignment: AlignmentDirectional.centerStart,
          minWidth: VoiceWaveform.width,
          maxWidth: VoiceWaveform.width,
          child: VoiceWaveform(
            peaks: peaks,
            progress: played,
            played: c.primary,
            unplayed: c.outline,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = MoshColors.of(context);
    final theme = Theme.of(context);
    return Tooltip(
      message: label,
      child: Material(
        color: c.surfaceContainerHighest,
        shape: MoshShapes.pill,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          overlayColor: MoshState.layer(c.onSurface),
          child: Container(
            height: MoshControl.height(theme.platform),
            padding: const EdgeInsets.symmetric(horizontal: MoshSpace.s3),
            child: Row(
              spacing: MoshSpace.s2,
              children: [
                ContextualIconSwitcher(
                  icon: playing ? MoshIcons.pause : MoshIcons.play,
                  size: MoshSpace.s5,
                  color: c.onSurface,
                ),
                Expanded(child: _wave(c)),
                Text(
                  formatVoiceClock(durationMs),
                  style: theme.textTheme.labelMedium!.copyWith(
                    color: c.onSurfaceVariant,
                    fontFeatures: kLiveNumberFontFeatures,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The player a paused recording is listened to with. Made on the first
/// listen and let go whenever the clip changes hands: a resume, a send, a
/// cancel, a composer out of sight.
class _ClipPlayer extends ChangeNotifier {
  _ClipPlayer({required this.create});

  final MediaPlayerFactory create;
  Player? _player;
  final List<StreamSubscription<Object?>> _events = [];
  bool _disposed = false;

  bool playing = false;

  /// How much of the clip has played, 0..1.
  double played = 0;

  /// Plays or pauses [clip], [length] long. Where no player can be made (a
  /// test host without libmpv) it does nothing.
  Future<void> toggle(String? clip, Duration length) async {
    if (clip == null) return;
    final player = _player;
    try {
      if (player != null) return await player.playOrPause();
    } catch (_) {
      return close();
    }
    final opened = _player = create();
    _events
      ..add(opened.stream.playing.listen((now) => _set(() => playing = now)))
      ..add(opened.stream.position.listen((at) => _set(() => played =
          length == Duration.zero
              ? 0
              : (at.inMilliseconds / length.inMilliseconds).clamp(0.0, 1.0))));
    try {
      await opened.open(Media(clip));
    } catch (_) {
      // Only the player that failed: a newer one may have taken its place.
      if (_player == opened) close();
    }
  }

  void close() {
    for (final event in _events) {
      unawaited(event.cancel());
    }
    _events.clear();
    unawaited(_player?.dispose());
    _player = null;
    _set(() => playing = false);
    played = 0;
  }

  @override
  void dispose() {
    close();
    _disposed = true;
    super.dispose();
  }

  void _set(VoidCallback change) {
    change();
    if (!_disposed) notifyListeners();
  }
}
