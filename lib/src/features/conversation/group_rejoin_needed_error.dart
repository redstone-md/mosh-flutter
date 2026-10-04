import 'package:flutter/material.dart';

class GroupRejoinNeededError extends StatelessWidget {
  const GroupRejoinNeededError(
      {super.key, required this.title, required this.body});

  /// The bold title line. The trailing period is appended here, NOT in the
  /// ARB value ("Group out of sync" has no trailing period).
  final String title;

  /// The body paragraph.
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = theme.colorScheme.error;
    return Semantics(
      liveRegion: true,
      container: true,
      label: '$title. $body',
      child: Container(
        margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: error.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: error.withValues(alpha: 0.35), width: 1),
        ),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$title.',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: error,
                  fontSize: 12,
                ),
              ),
              const TextSpan(text: ' '),
              TextSpan(
                text: body,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: error,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
