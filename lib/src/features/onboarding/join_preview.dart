import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/features/shared/mosh_notice.dart';
import 'package:mosh/src/invite/invite_detection.dart';

/// What a pasted link opens, as far as the link itself says: its kind and,
/// for a group or an organization, the name it carries: an inline note under
/// the link field, marked in the primary colour once the link is recognised
/// and an error plate when it is not a Mosh invite. Screen readers hear each
/// change.
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
    final l = AppLocalizations.of(context)!;
    final (tone, icon, detail) = switch (kind) {
      InviteDetectionKind.dm => (
          MoshNoticeTone.secure,
          MoshIcons.chat,
          l.onboardJoinPreviewDm
        ),
      InviteDetectionKind.group => (
          MoshNoticeTone.secure,
          MoshIcons.group,
          name ?? l.onboardJoinPreviewGroup
        ),
      InviteDetectionKind.org => (
          MoshNoticeTone.secure,
          MoshIcons.organisation,
          name ?? l.onboardJoinPreviewOrg
        ),
      InviteDetectionKind.unknown => (
          MoshNoticeTone.error,
          MoshIcons.linkOff,
          l.onboardJoinPreviewBad
        ),
      InviteDetectionKind.empty => (
          MoshNoticeTone.neutral,
          MoshIcons.chats,
          l.onboardJoinPreviewEmpty
        ),
    };
    return MoshNotice(
      tone: tone,
      icon: icon,
      title: title,
      detail: detail,
      inline: true,
      announced: true,
    );
  }
}
