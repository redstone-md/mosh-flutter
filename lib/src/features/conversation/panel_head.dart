import 'package:flutter/material.dart';

import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/features/conversation/conversation_helpers.dart'
    show kChatHeaderHeight;

/// The head of a panel beside a conversation: its title, and its buttons at
/// the right. As tall as the bar at the top of the conversation.
class PanelHead extends StatelessWidget {
  const PanelHead({super.key, required this.title, required this.actions});

  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: kChatHeaderHeight),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
              MoshSpace.s5, MoshSpace.s2, MoshSpace.s2, MoshSpace.s2),
          child: Row(children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium),
              ),
            ),
            ...actions,
          ]),
        ),
      );
}
