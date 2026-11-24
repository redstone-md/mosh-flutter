import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_shapes.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/diagnostics/diagnostics_summary.dart';

/// Renders a `DiagnosticSummary` as a bordered section with a heading
/// (kicker + title + a status badge with a tone dot + state), a
/// description paragraph, and a facts grid.
class SummaryCard extends StatelessWidget {
  const SummaryCard({super.key, required this.summary});

  final DiagnosticSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final toneColor = _toneColor(summary.tone, MoshColors.of(context));
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border.all(color: toneColor.withValues(alpha: 0.24)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Heading(summary: summary, toneColor: toneColor),
          const SizedBox(height: 9),
          Text(
            summary.description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 9),
          _FactsGrid(facts: summary.facts),
        ],
      ),
    );
  }
}

/// The heading row: kicker + title on the left, status badge (dot + state)
/// on the right.
class _Heading extends StatelessWidget {
  const _Heading({required this.summary, required this.toneColor});

  final DiagnosticSummary summary;
  final Color toneColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                summary.kicker.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 9.5,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                summary.title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  height: 1.15,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        _StatusBadge(state: summary.state, tone: summary.tone),
      ],
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

/// The facts grid: each fact is a small bordered cell with an uppercase
/// label and a mono value.
class _FactsGrid extends StatelessWidget {
  const _FactsGrid({required this.facts});

  final List<DiagnosticSummaryFact> facts;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final fact in facts)
          _FactCell(label: fact.label, value: fact.value),
      ],
    );
  }
}

/// A single fact cell. Sized to at least 92px wide via `ConstrainedBox`;
/// `Wrap` lays the cells out left-to-right wrapping.
class _FactCell extends StatelessWidget {
  const _FactCell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = MoshColors.of(context);
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 92),
      child: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHigh,
          border: Border.all(color: colors.outlineVariant),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                fontSize: 9.5,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              value,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Renders a runtime-error alert row with an alert-triangle icon + the
/// localized "Runtime error" label + the message.
class RuntimeError extends StatelessWidget {
  const RuntimeError({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final danger = MoshColors.of(context).error;
    // Live region: screen readers announce the error when it appears in
    // the drawer.
    return Semantics(
      liveRegion: true,
      container: true,
      label: '${l.runtimeError.toUpperCase()}: $message',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: danger.withValues(alpha: 0.06),
          border: Border.all(color: danger.withValues(alpha: 0.32)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(MoshIcons.warning, size: 18, color: danger),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l.runtimeError.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      fontSize: 9.5,
                      color: danger,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    message,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      height: 1.45,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Maps a `DiagnosticSummaryTone` to its color token.
Color _toneColor(DiagnosticSummaryTone tone, MoshColors colors) {
  switch (tone) {
    case DiagnosticSummaryTone.ready:
      return colors.primary;
    case DiagnosticSummaryTone.waiting:
      return colors.warning;
    case DiagnosticSummaryTone.error:
      return colors.error;
    case DiagnosticSummaryTone.idle:
      return colors.onSurfaceMuted;
  }
}
