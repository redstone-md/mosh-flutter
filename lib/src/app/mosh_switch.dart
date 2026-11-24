import 'package:flutter/material.dart';

import 'mosh_dimensions.dart';
import 'mosh_shapes.dart';
import 'mosh_spinner.dart';
import 'mosh_theme.dart' show MoshColors;

/// The Switch row card: a setting that takes effect at once. The whole row
/// is the press target and names the setting in [title], with one line of
/// explanation in [subtitle]. A null [onChanged] draws the row disabled;
/// [saving] shows a spinner beside the switch and takes no press, while the
/// words stay as they were.
class MoshSwitchRow extends StatefulWidget {
  const MoshSwitchRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.saving = false,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool saving;

  @override
  State<MoshSwitchRow> createState() => _MoshSwitchRowState();
}

class _MoshSwitchRowState extends State<MoshSwitchRow> {
  // InkWell reports focus here only while the keyboard drives it.
  final _states = WidgetStatesController();

  @override
  void dispose() {
    _states.dispose();
    super.dispose();
  }

  static const _shape = RoundedRectangleBorder(borderRadius: MoshShapes.field);

  @override
  Widget build(BuildContext context) {
    final c = MoshColors.of(context);
    final enabled = widget.onChanged != null && !widget.saving;
    return MergeSemantics(
      child: Semantics(
        toggled: widget.value,
        enabled: enabled,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            statesController: _states,
            customBorder: _shape,
            overlayColor: MoshState.layer(c.onSurface),
            onTap: widget.onChanged == null ? null : _press,
            child: ListenableBuilder(
              listenable: _states,
              builder: (context, child) => DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: _ring(c),
                child: child,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: MoshSpace.s12),
                child: Padding(
                  padding: const EdgeInsets.all(MoshSpace.s3),
                  child: _content(context, c, enabled),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// A row being saved takes the press and does nothing with it: turned
  /// off instead, it would drop the keyboard focus that started the save.
  void _press() {
    if (!widget.saving) widget.onChanged!(!widget.value);
  }

  /// The keyboard focus ring, 2 px outside the row.
  Decoration _ring(MoshColors c) => _states.value.contains(WidgetState.focused)
      ? ShapeDecoration(
          shape: _shape.copyWith(
              side: BorderSide(
                  color: c.focusRing,
                  width: MoshBorder.thick,
                  strokeAlign: BorderSide.strokeAlignOutside)))
      : const BoxDecoration();

  Widget _content(BuildContext context, MoshColors c, bool enabled) {
    final text = Theme.of(context).textTheme;
    // Saving keeps the words; only a row that is off fades them.
    Color ink(Color colour) => enabled || widget.saving
        ? colour
        : MoshState.tint(colour, MoshState.disabledContent);
    final subtitle = widget.subtitle;
    return Row(children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.title,
                style: text.titleSmall?.copyWith(color: ink(c.onSurface))),
            if (subtitle != null) ...[
              const SizedBox(height: MoshSpace.s1),
              Text(subtitle,
                  style:
                      text.bodySmall?.copyWith(color: ink(c.onSurfaceVariant))),
            ],
          ],
        ),
      ),
      const SizedBox(width: MoshSpace.s4),
      if (widget.saving) ...[
        IconTheme.merge(
            data: IconThemeData(color: c.onSurfaceVariant),
            child: const MoshSpinner()),
        const SizedBox(width: MoshSpace.s4),
      ],
      _SwitchTrack(value: widget.value, enabled: enabled),
    ]);
  }
}

/// The Switch card on its own, for a setting whose words stand elsewhere,
/// in a card's header for instance. On a phone it is a 48 px press target.
/// A null [onChanged] draws it disabled. Give it a [Semantics] label where
/// nothing beside it names the setting to a screen reader.
class MoshSwitch extends StatefulWidget {
  const MoshSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  State<MoshSwitch> createState() => _MoshSwitchState();
}

class _MoshSwitchState extends State<MoshSwitch> {
  final _states = WidgetStatesController();

  @override
  void dispose() {
    _states.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onChanged = widget.onChanged;
    final target =
        MoshControl.touch(Theme.of(context).platform) ? MoshSpace.s12 : 0.0;
    return Semantics(
      toggled: widget.value,
      enabled: onChanged != null,
      child: Material(
        type: MaterialType.transparency,
        // The track draws its own state layer; the press target is wider.
        child: InkWell(
          statesController: _states,
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          onTap: onChanged == null ? null : () => onChanged(!widget.value),
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: target, minHeight: target),
            child: Center(
              widthFactor: 1,
              heightFactor: 1,
              child: ListenableBuilder(
                listenable: _states,
                builder: (context, _) => _SwitchTrack(
                    value: widget.value,
                    enabled: onChanged != null,
                    states: _states.value),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The Switch card: a 40×24 track with a 16 px thumb. On is the primary
/// track; off is an outlined one; disabled keeps only a faint plate or edge.
/// A switch pressed on its own passes its [states] for the layer and the
/// focus ring; in a row the row draws both.
class _SwitchTrack extends StatelessWidget {
  const _SwitchTrack(
      {required this.value, required this.enabled, this.states = const {}});

  final bool value;
  final bool enabled;
  final Set<WidgetState> states;

  @override
  Widget build(BuildContext context) {
    final c = MoshColors.of(context);
    final Color fill, thumb;
    if (!enabled) {
      fill = value
          ? MoshState.tint(c.onSurface, MoshState.disabledContainer)
          : Colors.transparent;
      thumb = MoshState.tint(c.onSurface, MoshState.disabledContent);
    } else {
      fill = value ? c.primary : c.surfaceContainerHighest;
      thumb = value ? c.onPrimary : c.outline;
    }
    final motion = MoshMotion.effectsFast;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : motion.duration;
    return AnimatedContainer(
      duration: duration,
      curve: motion.curve,
      width: MoshSpace.s10,
      height: MoshSpace.s6,
      padding: const EdgeInsets.symmetric(horizontal: MoshSpace.s1),
      alignment: value
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      decoration: ShapeDecoration(color: fill, shape: MoshShapes.pill),
      foregroundDecoration: ShapeDecoration(
          color: MoshState.layer(value ? c.onPrimary : c.onSurface)
              .resolve(states),
          shape: MoshShapes.pill.copyWith(side: _edge(c))),
      child: AnimatedContainer(
        duration: duration,
        curve: motion.curve,
        width: MoshSpace.s4,
        height: MoshSpace.s4,
        decoration: BoxDecoration(color: thumb, shape: BoxShape.circle),
      ),
    );
  }

  /// The focus ring in place of the edge; an off track is outlined.
  BorderSide _edge(MoshColors c) {
    if (states.contains(WidgetState.focused)) {
      return BorderSide(
          color: c.focusRing,
          width: MoshBorder.thick,
          strokeAlign: BorderSide.strokeAlignOutside);
    }
    if (value) return BorderSide.none;
    return BorderSide(
        color: enabled ? c.outline : c.outlineVariant, width: MoshBorder.thin);
  }
}
