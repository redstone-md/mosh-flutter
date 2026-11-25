import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/features/shared/mosh_notice.dart';

/// The Rejoin group kind of the Banner card: the group is out of sync and
/// only a new invitation puts it right, so the banner offers nothing to do.
class GroupRejoinNeededError extends StatelessWidget {
  const GroupRejoinNeededError(
      {super.key, required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => MoshNotice(
        tone: MoshNoticeTone.error,
        icon: MoshIcons.error,
        title: title,
        detail: body,
      );
}
