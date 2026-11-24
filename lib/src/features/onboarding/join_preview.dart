import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'package:mosh/src/invite/invite_detection.dart';

/// What a pasted link opens, as far as the link itself says: its kind and,
/// for a group or an organization, the name it carries. Screen readers
/// hear each change.
class JoinPreview extends StatelessWidget {
  const JoinPreview({
    super.key,
    required this.kind,
    required this.title,
    this.name,
  });

  final InviteDetectionKind kind;

  /// The detection line: "Group invite detected", "Waiting for…".
  final String title;
  final String? name;

  @override
  Widget build(BuildContext context) {
    final colors = MoshColors.of(context);
    final l = AppLocalizations.of(context)!;
    final text = Theme.of(context).textTheme;
    final (icon, color, detail) = switch (kind) {
      InviteDetectionKind.dm => (
          Icons.chat_bubble_outline,
          colors.primary,
          l.onboardJoinPreviewDm
        ),
      InviteDetectionKind.group => (
          Icons.group_outlined,
          colors.primary,
          name ?? l.onboardJoinPreviewGroup
        ),
      InviteDetectionKind.org => (
          Icons.business_outlined,
          colors.primary,
          name ?? l.onboardJoinPreviewOrg
        ),
      InviteDetectionKind.unknown => (
          Icons.link_off,
          colors.error,
          l.onboardJoinPreviewBad
        ),
      InviteDetectionKind.empty => (
          Icons.forum_outlined,
          colors.onSurfaceMuted,
          l.onboardJoinPreviewEmpty
        ),
    };
    final known = color == colors.primary;
    return Semantics(
      liveRegion: true,
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 250),
        curve: const Cubic(0.22, 1, 0.36, 1),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color:
              known ? colors.secondaryContainer : colors.surfaceContainerLowest,
          border: Border.all(
              color: known
                  ? colors.primary.withValues(alpha: 0.3)
                  : kind == InviteDetectionKind.unknown
                      ? colors.error
                      : colors.outlineVariant),
        ),
        child: Row(children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 24, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: text.titleSmall?.copyWith(
                        color: kind == InviteDetectionKind.unknown
                            ? colors.error
                            : colors.onSurface,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(detail,
                    style: text.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant, height: 1.4)),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
