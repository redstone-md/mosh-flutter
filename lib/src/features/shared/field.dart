// `Field` shared primitive. Layout-only wrapper:
// label -> child input -> optional hint, stacked vertically with a 4px gap.
// The caller supplies the input as `child`.
library;

import 'package:flutter/material.dart';

import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;

/// A vertical stack of label, child, optional hint
/// with a 4px gap. The label is 11px/600/fg-2/
/// letter-spacing 0.02em; the hint is 10.5px/fg-4/line-height 1.45.
class Field extends StatelessWidget {
  const Field({
    super.key,
    required this.label,
    this.hint,
    required this.child,
  });

  final String label;
  final String? hint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurfaceVariant,
            // `letter-spacing: 0.02em` on an 11px label is
            // ~0.22 logical px (0.02 * 11). Dart uses logical px, not em.
            letterSpacing: 0.22,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 4),
        child,
        if (hint != null) ...[
          const SizedBox(height: 4),
          Text(
            hint!,
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 10.5,
              // fg-4 hint color.
              color: MoshColors.fg4,
              height: 1.45,
            ),
          ),
        ],
      ],
    );
  }
}
