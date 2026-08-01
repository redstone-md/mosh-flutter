/// `SummaryCard` + `RuntimeError` widgets for the Diagnostics drawer, 1-в-1
/// with React's `SummaryCard` and `RuntimeError` in
/// `src/features/private-dm/DiagnosticsDrawerSummary.tsx`.
///
/// This atomic only adds the summary primitives -- wiring them into
/// `DiagnosticsScreen` is a LATER atomic. `DiagnosticsScreen` itself is
/// unchanged here.
///
/// Colors mirror the React `diagnostic-summary-${tone}` classes from
/// `middle-column.css`:
///   - ready  -> `--moss`    #b7d84a (green)
///   - waiting -> `--warn`   #e8b65a (amber)
///   - error  -> `--danger`  #e86a5a (red)
///   - idle   -> `--fg-3`    #6b7075 (grey, the default badge dot color)
/// The tone also tints the section border (alpha) like the React CSS does.
library;

import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/diagnostics/diagnostics_summary.dart';

/// Renders a `DiagnosticSummary` as a bordered section with a heading
/// (kicker + title + a status badge with a tone dot + state), a
/// description paragraph, and a facts grid. Mirrors React's `SummaryCard`.
class SummaryCard extends StatelessWidget {
  const SummaryCard({super.key, required this.summary});

  final DiagnosticSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final toneColor = _toneColor(summary.tone);
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
/// on the right. Mirrors React's `.diagnostic-summary-heading`.
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
        _StatusBadge(state: summary.state, tone: summary.tone, toneColor: toneColor),
      ],
    );
  }
}

/// The pill-shaped status badge with a tone dot + the state text. Mirrors
/// React's `.diagnostic-status-badge` + `.diagnostic-status-dot`.
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.state,
    required this.tone,
    required this.toneColor,
  });

  final String state;
  final DiagnosticSummaryTone tone;
  final Color toneColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final badgeBg = tone == DiagnosticSummaryTone.error
        ? toneColor.withValues(alpha: 0.06)
        : (tone == DiagnosticSummaryTone.ready
            ? const Color(0x24B7D84A).withValues(alpha: 0.14)
            : theme.colorScheme.surfaceContainerHighest);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: badgeBg,
        border: Border.all(color: toneColor.withValues(alpha: 0.24)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: toneColor,
              shape: BoxShape.circle,
              boxShadow: tone == DiagnosticSummaryTone.ready
                  ? [BoxShadow(color: toneColor, blurRadius: 4)]
                  : null,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            state,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 10,
              color: toneColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// The facts grid: each fact is a small bordered cell with an uppercase
/// label and a mono value. Mirrors React's `.diagnostic-summary-facts`.
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

/// A single fact cell. Sized to at least 92px wide (React's
/// `minmax(92px, 1fr)`) via `ConstrainedBox`, then grows with `IntrinsicWidth`
/// is unnecessary -- `Wrap` lays them out left-to-right wrapping.
class _FactCell extends StatelessWidget {
  const _FactCell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 92),
      child: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          border: Border.all(color: theme.dividerColor),
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
/// localized "Runtime error" label + the message. Mirrors React's
/// `RuntimeError` (uses `IconAlertTriangle` -> `Icons.warning_amber`).
class RuntimeError extends StatelessWidget {
  const RuntimeError({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    const danger = Color(0xFFE86A5A);
    // `Semantics(liveRegion: true)` mirrors React `role="alert"` -- screen
    // readers announce the error when it appears in the drawer.
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
            const Icon(Icons.warning_amber, size: 18, color: danger),
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

/// Maps a `DiagnosticSummaryTone` to its React-CSS color token.
Color _toneColor(DiagnosticSummaryTone tone) {
  switch (tone) {
    case DiagnosticSummaryTone.ready:
      return const Color(0xFFB7D84A); // --moss
    case DiagnosticSummaryTone.waiting:
      return const Color(0xFFE8B65A); // --warn
    case DiagnosticSummaryTone.error:
      return const Color(0xFFE86A5A); // --danger
    case DiagnosticSummaryTone.idle:
      return const Color(0xFF6B7075); // --fg-3
  }
}
