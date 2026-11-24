import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_shapes.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;

import 'package:mosh/src/features/diagnostics/diagnostics_summary.dart';

/// The Summary card of connection status: the state in one word on its
/// badge, a headline and a sentence a person can read, and three facts.
class SummaryCard extends StatelessWidget {
  const SummaryCard({super.key, required this.summary});

  final DiagnosticSummary summary;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = MoshColors.of(context);
    return Container(
      padding: const EdgeInsets.all(MoshSpace.s4),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: const BorderRadius.all(Radius.circular(MoshRadius.large)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatusBadge(state: summary.state, tone: summary.tone),
          const SizedBox(height: MoshSpace.s3),
          Text(summary.title, style: text.titleMedium),
          const SizedBox(height: MoshSpace.s1),
          Text(summary.description, style: text.bodySmall),
          const SizedBox(height: MoshSpace.s3),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final (i, fact) in summary.facts.indexed) ...[
              if (i > 0) const SizedBox(width: MoshSpace.s4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(fact.label, style: text.labelSmall),
                    Text(fact.value, style: text.titleSmall),
                  ],
                ),
              ),
            ],
          ]),
        ],
      ),
    );
  }
}

/// The Status badge card: a tone dot and the state's word on a plate.
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.state, required this.tone});

  final String state;
  final DiagnosticSummaryTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = MoshColors.of(context);
    // The word carries the meaning; the plate and the dot repeat it.
    final (mark, plate, ink) = switch (tone) {
      DiagnosticSummaryTone.error => (
          colors.error,
          colors.errorContainer,
          colors.onErrorContainer
        ),
      DiagnosticSummaryTone.waiting => (
          colors.warning,
          colors.warningContainer,
          colors.onWarningContainer
        ),
      DiagnosticSummaryTone.ready => (
          colors.success,
          colors.surfaceContainerHighest,
          colors.onSurface
        ),
      DiagnosticSummaryTone.idle => (
          colors.outline,
          colors.surfaceContainerHighest,
          colors.onSurface
        ),
    };
    return Container(
      constraints: const BoxConstraints(minHeight: MoshSpace.s6),
      padding: const EdgeInsetsDirectional.only(
          start: MoshSpace.s2, end: MoshSpace.s3),
      decoration: ShapeDecoration(color: plate, shape: MoshShapes.pill),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: MoshSpace.s2,
            height: MoshSpace.s2,
            decoration: BoxDecoration(color: mark, shape: BoxShape.circle),
          ),
          const SizedBox(width: MoshSpace.s2),
          Text(
            state,
            style:
                Theme.of(context).textTheme.labelMedium!.copyWith(color: ink),
          ),
        ],
      ),
    );
  }
}
