import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/features/shared/contextual_icon_switcher.dart';

/// What a call button says by its plate (Call controls card). [neutral] is a
/// setting as it stands in a plain voice call, [lit] marks what differs from
/// one (a muted microphone, a camera that is on), [accept] answers and [end]
/// is kept for the one button that ends or declines the call.
enum CallTone {
  neutral,
  lit,
  accept,
  end;

  Color plate(MoshColors c) => switch (this) {
        neutral => c.surfaceContainerHighest,
        lit => c.inverseSurface,
        accept => c.primary,
        end => c.error,
      };

  Color ink(MoshColors c) => switch (this) {
        neutral => c.onSurface,
        lit => c.onInverseSurface,
        accept => c.onPrimary,
        end => c.onError,
      };
}

/// One button of a call, apart from the shape it is drawn in: the dock's
/// [CallButton], or a [CallMiniButton] where the call is minimized.
class CallControl {
  const CallControl(
      {required this.icon,
      required this.tooltip,
      required this.onPressed,
      this.tone = CallTone.neutral,
      this.toggled});

  final IconData icon;

  /// What the button does: its tooltip and what a screen reader says.
  final String tooltip;

  /// Null while the button cannot be pressed.
  final VoidCallback? onPressed;
  final CallTone tone;

  /// For a switch (microphone, camera): whether it is on.
  final bool? toggled;
}

/// The round Call button: 48 px with a 24 px glyph, or [large] for a phone
/// held upright, 64 px with a 32 px glyph. A control that cannot be pressed
/// is the card's disabled button.
class CallButton extends StatelessWidget {
  const CallButton({super.key, required this.control, this.large = false});

  final CallControl control;
  final bool large;

  @override
  Widget build(BuildContext context) => _CallIconButton(
      control: control,
      size: large ? MoshSpace.s16 : MoshSpace.s12,
      glyph: large ? MoshSpace.s8 : MoshSpace.s6);
}

/// A call's button where the call is minimized and has no room for a
/// [CallButton]: an Icon button on the plate of its tone, and with [mark]
/// the 24 px one of the title bar's plate. A neutral button has no plate.
class CallMiniButton extends StatelessWidget {
  const CallMiniButton({super.key, required this.control, this.mark = false});

  final CallControl control;
  final bool mark;

  @override
  Widget build(BuildContext context) => _CallIconButton(
      control: control,
      size: mark ? MoshSpace.s6 : null,
      glyph: mark ? MoshSpace.s4 : null,
      bare: control.tone == CallTone.neutral);
}

/// An icon button in a call tone. [size] and [glyph] default to the Icon
/// button card's; [bare] leaves the theme's plain button.
class _CallIconButton extends StatelessWidget {
  const _CallIconButton(
      {required this.control, this.size, this.glyph, this.bare = false});

  final CallControl control;
  final double? size, glyph;
  final bool bare;

  @override
  Widget build(BuildContext context) {
    final colors = MoshColors.of(context);
    final tone = control.tone;
    // A bare button of the Icon button's size is the theme's own; the
    // plate's small one takes the ink of the name beside it.
    final style = bare
        ? ButtonStyle(
            foregroundColor: size == null
                ? null
                : MoshState.unlessDisabled(
                    colors.onSurface,
                    MoshState.tint(
                        colors.onSurface, MoshState.disabledContent)))
        : moshPlateIconButtonStyle(colors,
            plate: tone.plate(colors), ink: tone.ink(colors));
    // One node says what the button does and whether it is on.
    return MergeSemantics(
        child: Semantics(
      toggled: control.toggled,
      child: IconButton(
        tooltip: control.tooltip,
        onPressed: control.onPressed,
        style: style.copyWith(
          fixedSize:
              size == null ? null : WidgetStatePropertyAll(Size.square(size!)),
          minimumSize:
              size == null ? null : const WidgetStatePropertyAll(Size.zero),
          tapTargetSize: size == null ? null : MaterialTapTargetSize.shrinkWrap,
          iconSize: glyph == null ? null : WidgetStatePropertyAll(glyph),
        ),
        icon: ContextualIconSwitcher(
            icon: control.icon,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : MoshMotion.effectsDefault.duration),
      ),
    ));
  }
}
