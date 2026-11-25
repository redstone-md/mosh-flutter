import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/features/shared/mosh_notice.dart';

/// The Add members kind of the Banner card. [count] is the number of missing
/// roster members; [busy] gates the Add button; [onAdd] fires the invite.
/// [missingOne]/[missingMany] are the localized "roster member(s) not in
/// this group" phrases, singular vs plural picked on count == 1; [addLabel]
/// is "Add to group".
class OrgAddMissingBanner extends StatelessWidget {
  const OrgAddMissingBanner({
    super.key,
    required this.count,
    required this.busy,
    required this.onAdd,
    required this.missingOne,
    required this.missingMany,
    required this.addLabel,
  });

  final int count;
  final bool busy;
  final VoidCallback onAdd;
  final String missingOne;
  final String missingMany;
  final String addLabel;

  @override
  Widget build(BuildContext context) => MoshNotice(
        tone: MoshNoticeTone.neutral,
        icon: MoshIcons.group,
        title: '$count ${count == 1 ? missingOne : missingMany}',
        actionLabel: addLabel,
        onAction: onAdd,
        busy: busy,
      );
}
