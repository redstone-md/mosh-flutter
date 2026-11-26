import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/features/shared/mosh_notice.dart';
import 'call_notice.dart';

/// The strip of a minimized call: who it is with, how it is going and its
/// buttons. The open call is the CallWindow.
class CallStrip extends StatelessWidget {
  const CallStrip({
    super.key,
    required this.label,
    required this.peer,
    required this.status,
    required this.actions,
    this.statusFontFeatures,
    this.onOpenConversation,
    this.notice,
    this.singleLine = false,
  });

  final String label;
  final String peer;
  final String status;
  final List<Widget> actions;
  final List<FontFeature>? statusFontFeatures;
  final VoidCallback? onOpenConversation;
  final CallNotice? notice;
  final bool singleLine;

  @override
  Widget build(BuildContext context) {
    final colors = MoshColors.of(context);
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Semantics(
        label: label,
        container: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: LayoutBuilder(
              builder: (context, constraints) => !singleLine &&
                      constraints.maxWidth < 480
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                          _identity(colors),
                          const SizedBox(height: 8),
                          Wrap(spacing: 12, runSpacing: 8, children: actions)
                        ])
                  : Row(spacing: 12, children: [
                      Expanded(child: _identity(colors)),
                      ...actions
                    ])),
        ),
      ),
    );
  }

  Widget _identity(MoshColors colors) => InkWell(
      onTap: onOpenConversation,
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(peer, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(status,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontFeatures: statusFontFeatures)),
            if (notice != null) _notice(colors),
          ]));

  Widget _notice(MoshColors colors) => Text(notice!.text,
      style: TextStyle(
          color: notice!.tone == MoshNoticeTone.error
              ? colors.error
              : colors.warning),
      softWrap: true);
}
