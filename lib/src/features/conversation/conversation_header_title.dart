import 'package:flutter/material.dart';
import 'package:mosh/src/features/conversation/conversation_helpers.dart';

/// One name/status rhythm for DMs, groups and public channels.
class ConversationHeaderTitle extends StatelessWidget {
  const ConversationHeaderTitle({
    super.key,
    required this.name,
    required this.subtitle,
  });

  final String name;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          SizedBox(height: chatSubtitleGap(context)),
          Text(subtitle,
              style: chatSubtitleStyle(context),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      );
}
