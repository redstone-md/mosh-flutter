/// Diagnostics-drawer section widgets, 1-в-1 with React's
/// `src/features/private-dm/DiagnosticsDrawerSections.tsx`.
///
/// In scope (this atomic): the `SessionDiagnostics` "Conversation details"
/// group ONLY (the first `<div className="diagnostic-group">` inside
/// `SessionDiagnostics`), plus the shared primitives it needs:
///   - `DiagnosticsGroup`  -- the `diagnostic-group` + `diagnostic-group-label`
///     shell (reused by `NoActiveSession` here, and by the later
///     `MeshDiagnostics` / `EventLog` atomics).
///   - `DiagnosticsRow`     -- the `Row({ k, v })` primitive (a label span +
///     a strong value). Named `DiagnosticsRow` to avoid clashing with
///     Flutter's `Row`.
///   - `NoActiveSession`    -- the React `NoActiveSession` (a `Session`
///     group with an empty-state).
///
/// DEFERRED (separate atomics -- they need more helpers + the event
/// rendering, and `MeshDiagnostics` reuses helpers already ported but its
/// `Metric` grid + event rows are a larger surface): `MeshDiagnostics`,
/// `EventLog`, and the `ChannelDiagnostics` / `GroupDiagnostics` sections
/// (the latter two need `ChannelSnapshot` / `GroupSnapshot` contracts that
/// do not exist in the Flutter fork yet). Wiring `SessionDiagnostics` into
/// `DiagnosticsScreen` is also a later atomic.
library;

import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/diagnostics/diagnostics_helpers.dart';
import 'package:mosh/src/features/diagnostics/state_label.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/util/format.dart';

/// The `diagnostic-group` shell: a bordered, rounded container with an
/// uppercase group-label header on a slightly different surface, then the
/// group's children in a column. Mirrors React's `.diagnostic-group` +
/// `.diagnostic-group-label` (middle-column.css): the group has a 1px line
/// border, 8px radius, and `overflow: hidden` so the label's bottom border
/// sits flush with the rows; the label is 9.5px, weight 700, uppercase, with
/// 0.08em letter-spacing, on the bg-1 surface with a bottom line.
///
/// Reusable by `SessionDiagnostics`, `NoActiveSession`, and the later
/// `MeshDiagnostics` / `EventLog` sections, so each section is the same shell
/// + a label + children.
class DiagnosticsGroup extends StatelessWidget {
  const DiagnosticsGroup({
    super.key,
    required this.label,
    required this.children,
  });

  /// The uppercase group-label header text (already localized by the
  /// caller, e.g. `l.diagConversationDetails`).
  final String label;

  /// The group body (rows, an empty-state, a mesh grid, etc.).
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _GroupLabel(label: label),
          ...children,
        ],
      ),
    );
  }
}

/// The `.diagnostic-group-label` header: uppercase, weight 700, on the
/// bg-1 surface with a bottom line. Mirrors React's CSS (9.5px, 0.08em
/// letter-spacing, 6/10 padding, fg-3 color).
class _GroupLabel extends StatelessWidget {
  const _GroupLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Text(
        label.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          fontSize: 9.5,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// The `Row({ k, v })` primitive -- a `.diagnostic-row`: a label span on the
/// left (fg-3) and a strong value on the right (fg-1, mono, right-aligned,
/// word-break). Mirrors React's `Row`. Named `DiagnosticsRow` to avoid
/// clashing with Flutter's `Row` widget.
///
/// Each row draws its own bottom divider (React's `.diagnostic-row` rule);
/// the group's `clipBehavior: Clip.antiAlias` + the label's bottom border
/// keep the visual seams clean, and the container's rounded clip hides the
/// last row's trailing line at the bottom edge, matching React's
/// `overflow: hidden`.
class DiagnosticsRow extends StatelessWidget {
  const DiagnosticsRow({super.key, required this.label, required this.value});

  /// The row key (`k` in React). Already localized by the caller.
  final String label;

  /// The row value (`v` in React). May be data (e.g. a transport-path
  /// label) or localized copy.
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 10.5,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 7,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The React `NoActiveSession`: a `Session` group with an empty-state
/// (a bold title + a description span). Mirrors React's
/// `.diagnostic-empty-state` (flex column, 4px gap, 13/10 padding, fg-3,
/// 11px / 1.4 line-height; the `strong` is fg-2, 11.5px, weight 700).
class NoActiveSession extends StatelessWidget {
  const NoActiveSession({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return DiagnosticsGroup(
      label: l.diagSessionLabel,
      children: const [_EmptyState()],
    );
  }
}

/// The `.diagnostic-empty-state` body: a bold title + a description span.
/// Mirrors React's `.diagnostic-empty-state` (used by `NoActiveSession`
/// here, and by the later `MeshDiagnostics` / `EventLog` empty states).
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l.diagNoActiveTitle,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l.diagNoActiveBody,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 11,
              height: 1.4,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// The React `SessionDiagnostics`, Conversation-details group ONLY.
///
/// Renders the first `.diagnostic-group` from React's `SessionDiagnostics`:
/// the "Conversation details" label, then the Peer / MLS state / Path /
/// (Encryption, only when `path == "relayed"`) / Role / Display / Session
/// rows. The MLS-state value uses the shared `stateLabel` mapper (the same
/// `stateLabels[session.state] ?? session.state` lookup the summary card
/// and the sessions rail use). The Path value uses `pathLabel` (data, not
/// localized). The Session value uses `shorten(session.sessionId, 14)` from
/// `lib/src/util/format.dart`.
///
/// `MeshDiagnostics` and `EventLog` (the second and third groups in the
/// React `SessionDiagnostics`) are DEFERRED to separate atomics -- this
/// widget returns only the Conversation-details group for now. The later
/// atomic will compose all three groups into one `SessionDiagnostics`
/// column; until then the drawer wiring (also a later atomic) renders this
/// group directly.
class SessionDiagnostics extends StatelessWidget {
  const SessionDiagnostics({super.key, required this.session});

  final SessionSnapshot session;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final rows = <DiagnosticsRow>[
      DiagnosticsRow(
        label: l.diagRowPeer,
        value: session.peerDisplayName.isNotEmpty
            ? session.peerDisplayName
            : l.diagPeerUnknown,
      ),
      DiagnosticsRow(
        label: l.diagRowMlsState,
        value: stateLabel(l, session.state),
      ),
      DiagnosticsRow(
        label: l.diagRowPath,
        value: pathLabel(session.path, session.relayReady),
      ),
      if (session.path == 'relayed')
        DiagnosticsRow(
          label: l.diagRowEncryption,
          value: l.diagEncryptionRelayed,
        ),
      DiagnosticsRow(label: l.diagRowRole, value: session.role),
      DiagnosticsRow(label: l.diagRowDisplay, value: session.displayName),
      DiagnosticsRow(
        label: l.diagSessionLabel,
        value: shorten(session.sessionId, 14),
      ),
    ];
    return DiagnosticsGroup(
      label: l.diagConversationDetails,
      children: rows,
    );
  }
}
