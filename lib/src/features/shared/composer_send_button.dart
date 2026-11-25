import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_shapes.dart';
import 'package:mosh/src/app/mosh_spinner.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;

/// The send button of the Composer card: a 40 px plate in the accent, in a
/// 48 px target on the phone. Without [onPressed] the plate is unlit.
class ComposerSendButton extends StatelessWidget {
  const ComposerSendButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  /// The plate, whatever the size of the target around it.
  static const double plate = MoshSpace.s10;

  final String label;
  final VoidCallback? onPressed;

  /// Shows a spinner in place of the arrow: a send is on its way.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = MoshColors.of(context);
    final touch = MoshControl.touch(Theme.of(context).platform);
    return IconButton(
      tooltip: label,
      onPressed: onPressed,
      style: ButtonStyle(
        fixedSize: const WidgetStatePropertyAll(Size.square(plate)),
        iconSize: const WidgetStatePropertyAll(MoshSpace.s5),
        tapTargetSize: touch
            ? MaterialTapTargetSize.padded
            : MaterialTapTargetSize.shrinkWrap,
        shape: const WidgetStatePropertyAll(MoshShapes.pill),
        backgroundColor: MoshState.unlessDisabled(c.primary,
            MoshState.tint(c.onSurface, MoshState.disabledContainer)),
        foregroundColor: MoshState.unlessDisabled(c.onPrimary,
            MoshState.tint(c.onSurface, MoshState.disabledContent)),
        overlayColor: MoshState.layer(c.onPrimary),
      ),
      icon: busy ? const MoshSpinner() : const Icon(MoshIcons.send),
    );
  }
}
