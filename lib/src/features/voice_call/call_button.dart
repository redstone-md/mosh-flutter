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

/// The round Call button: 48 px with a 24 px glyph, or [large] for a phone
/// held upright, 64 px with a 32 px glyph. Without [onPressed] it is the
/// card's disabled button.
class CallButton extends StatelessWidget {
  const CallButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.tone = CallTone.neutral,
    this.large = false,
    this.toggled,
  });

  final IconData icon;

  /// What the button does: its tooltip and what a screen reader says.
  final String tooltip;
  final VoidCallback? onPressed;
  final CallTone tone;
  final bool large;

  /// For a switch (microphone, camera): whether it is on.
  final bool? toggled;

  @override
  Widget build(BuildContext context) {
    final colors = MoshColors.of(context);
    // One node says what the button does and whether it is on.
    return MergeSemantics(
        child: Semantics(
      toggled: toggled,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        style: moshPlateIconButtonStyle(colors,
                plate: tone.plate(colors), ink: tone.ink(colors))
            .copyWith(
          fixedSize: WidgetStatePropertyAll(
              Size.square(large ? MoshSpace.s16 : MoshSpace.s12)),
          iconSize: WidgetStatePropertyAll(large ? MoshSpace.s8 : MoshSpace.s6),
        ),
        icon: ContextualIconSwitcher(
            icon: icon,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : MoshMotion.effectsDefault.duration),
      ),
    ));
  }
}
