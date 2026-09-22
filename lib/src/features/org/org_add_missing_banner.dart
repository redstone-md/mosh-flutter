/// The orgAddPrompt banner: "{count} {missingOne|missingMany}" plus an
/// "Add to group" button the admin taps to invite the missing roster members
/// in one click (spec §5). The button disables while the invite is in flight
/// (busy). Renders nothing when count == 0 (the provider already returns
/// null in that case; this widget is a pure render of the prompt).
library;

import 'package:flutter/material.dart';

/// The banner. [count] is the number of missing roster members; [busy] gates
/// the Add button; [onAdd] fires the invite. [missingOne]/[missingMany] are
/// the localized "roster member(s) not in this group" phrases, singular
/// vs plural picked on count == 1; [addLabel] is "Add to group".
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phrase = count == 1 ? missingOne : missingMany;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: Border(
          top: BorderSide(color: theme.dividerColor, width: 0.5),
          bottom: BorderSide(color: theme.dividerColor, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$count $phrase',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: busy ? null : onAdd,
            child: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(addLabel),
          ),
        ],
      ),
    );
  }
}
