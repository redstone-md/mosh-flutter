import 'package:flutter/material.dart';

import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_shapes.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'package:mosh/src/features/sessions/rail_compact.dart';
import 'package:mosh/src/features/shared/focus_ring.dart';
import 'package:mosh/src/features/shared/resumed_ink.dart';

/// Starts a conversation: the primary Button across the list, and the
/// primary icon button of the collapsed one.
class RailNewButton extends StatelessWidget {
  const RailNewButton({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (RailCompactScope.of(context)) {
      final colors = MoshColors.of(context);
      return CompactRailButton(
        icon: MoshIcons.add,
        label: label,
        onTap: onTap,
        fill: colors.primary,
        ink: colors.onPrimary,
      );
    }
    return SizedBox(
      width: double.infinity,
      // The start menu covers the list on a phone and freezes the press ink.
      child: ResumedInk(
        builder: (focusNode) => FilledButton.icon(
          focusNode: focusNode,
          onPressed: onTap,
          icon: const Icon(MoshIcons.add),
          label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ),
    );
  }
}

/// The Settings row card, pinned under the list: a quiet pill as tall as a
/// control with the settings glyph and its label. The collapsed list shows
/// the glyph alone.
class RailSettingsButton extends StatelessWidget {
  const RailSettingsButton(
      {super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (RailCompactScope.of(context)) {
      return CompactRailButton(
          icon: MoshIcons.settings, label: label, onTap: onTap);
    }
    final theme = Theme.of(context);
    final ink = MoshColors.of(context).onSurfaceVariant;
    return Semantics(
      button: true,
      child: Material(
        type: MaterialType.transparency,
        shape: MoshShapes.pill,
        clipBehavior: Clip.antiAlias,
        // Settings covers the list; a fresh InkWell drops the press ink
        // that froze under it.
        child: ResumedInk(
          builder: (focusNode) => InkWell(
            focusNode: focusNode,
            onTap: onTap,
            child: FocusRing(
              radius: MoshShapes.pillCorners,
              child: Container(
                constraints: BoxConstraints(
                    minHeight: MoshControl.height(theme.platform)),
                padding: const EdgeInsets.symmetric(horizontal: MoshSpace.s3),
                child: Row(
                  spacing: MoshSpace.s3,
                  children: <Widget>[
                    Icon(MoshIcons.settings, size: MoshSpace.s5, color: ink),
                    Flexible(
                      child: Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              theme.textTheme.labelLarge!.copyWith(color: ink)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
