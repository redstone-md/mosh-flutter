/// Pure diagnostics-summary builder for the Diagnostics drawer, 1-в-1 with
/// React's `src/features/private-dm/DiagnosticsDrawerSummary.tsx` for the
/// **DM branch** and the **idle/error (no-active-session) branch** only.
///
/// The React `diagnosticsSummary(session, channel, group, error)` also has
/// `channel` and `group` branches. Those contracts (`ChannelSnapshot`,
/// `GroupSnapshot`) DO NOT EXIST in the Flutter fork yet -- only
/// `SessionSnapshot` and `MeshInfo` are frb-generated. So the channel/group
/// branches are DEFERRED to a later atomic: until those contracts land, the
/// Flutter `diagnosticsSummary` accepts only `SessionSnapshot? session` and
/// `String? error` (no channel/group params), and falls straight through to
/// the idle/error branch when `session` is null -- matching the React
/// fallback when all three of session/channel/group are null.
///
/// Pureness: the function takes `AppLocalizations l` (the localized copy
/// seam) plus the runtime inputs and returns a fully-resolved
/// `DiagnosticSummary`. It is deterministic given `l` -- the same `l` plus
/// the same inputs always produce the same output, so it stays unit-testable
/// (the tests construct an `AppLocalizations` from the en delegate via a
/// localized `MaterialApp` harness and assert on the returned fields). This
/// matches the React `stateLabels` + literal-string resolution shape while
/// keeping all user-facing strings flowing through ARB.
library;

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/diagnostics/diagnostics_helpers.dart';
import 'package:mosh/src/features/diagnostics/state_label.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';

/// Tone of a `DiagnosticSummary`, mirroring React's `SummaryTone`. Drives
/// the `diagnostic-summary-${tone}` color: ready = green, waiting = amber,
/// idle = grey, error = red.
enum DiagnosticSummaryTone { ready, waiting, idle, error }

/// One row of the summary facts grid: a localized label plus a data value.
/// The value is NOT localized (it mirrors React's literal fact values like
/// "booting", "unknown", "none", "paused", or a numeric relay status).
class DiagnosticSummaryFact {
  const DiagnosticSummaryFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiagnosticSummaryFact &&
          label == other.label &&
          value == other.value;

  @override
  int get hashCode => Object.hash(label, value);

  @override
  String toString() => 'DiagnosticSummaryFact($label: $value)';
}

/// The full summary payload rendered by `SummaryCard`. 1-в-1 with the React
/// `DiagnosticSummary` interface: tone, kicker, title, state (the localized
/// state-badge text), description, and the facts grid.
class DiagnosticSummary {
  const DiagnosticSummary({
    required this.tone,
    required this.kicker,
    required this.title,
    required this.state,
    required this.description,
    required this.facts,
  });

  final DiagnosticSummaryTone tone;
  final String kicker;
  final String title;
  final String state;
  final String description;
  final List<DiagnosticSummaryFact> facts;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiagnosticSummary &&
          tone == other.tone &&
          kicker == other.kicker &&
          title == other.title &&
          state == other.state &&
          description == other.description &&
          _listEquals(facts, other.facts);

  @override
  int get hashCode => Object.hash(tone, kicker, title, state, description,
      Object.hashAll(facts));

  @override
  String toString() => 'DiagnosticSummary($tone, $kicker, $title, $state)';
}

bool _listEquals(List<DiagnosticSummaryFact> a, List<DiagnosticSummaryFact> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Builds the diagnostics summary for the DM branch + the idle/error
/// branch, 1-в-1 with React `diagnosticsSummary(session, channel, group,
/// error)` for those two branches. Channel/group branches are deferred
/// (no contracts yet) -- callers that would have passed a channel/group in
/// React simply pass `session: null` here and get the idle/error fallback,
/// matching the React no-active-session path.
///
/// `l` is the localized copy seam: the function is pure (deterministic
/// given `l`). The DM-branch state badge uses the existing `stateReady` /
/// `stateWaiting` / `stateIdle` keys via the shared `stateLabel` mapper
/// (mirrors React's `stateLabels[session.state] ?? session.state` with the
/// raw-state fallback used by `sessions_screen.dart`). The idle/error state
/// badges use the new `summaryStateWaiting` / `summaryStateError` keys.
DiagnosticSummary diagnosticsSummary({
  required AppLocalizations l,
  SessionSnapshot? session,
  String? error,
}) {
  if (session != null) {
    final mesh = session.mesh;
    return DiagnosticSummary(
      tone: error != null ? DiagnosticSummaryTone.error : _summaryTone(session.state),
      kicker: l.summaryDmKicker,
      title: session.peerDisplayName.isNotEmpty
          ? session.peerDisplayName
          : (session.displayName.isNotEmpty
              ? session.displayName
              : 'Private session'),
      state: stateLabel(l, session.state),
      description: _sessionDescription(l, session.state, mesh),
      facts: [
        DiagnosticSummaryFact(label: l.summaryFactPeers, value: peerCount(mesh)),
        DiagnosticSummaryFact(label: l.summaryFactNat, value: natType(mesh)),
        DiagnosticSummaryFact(
            label: l.summaryFactRelay,
            value: mesh != null ? relayStatus(mesh) : 'booting'),
      ],
    );
  }
  // channel / group branches -- DEFERRED (no ChannelSnapshot / GroupSnapshot
  // contracts in the Flutter fork yet). React falls through to the idle/error
  // fallback when all three of session/channel/group are null, which is
  // exactly what this branch implements.
  return DiagnosticSummary(
    tone: error != null ? DiagnosticSummaryTone.error : DiagnosticSummaryTone.idle,
    kicker: l.summaryIdleKicker,
    title: l.summaryNoSessionTitle,
    state: error != null ? l.summaryStateError : l.summaryStateWaiting,
    description: l.summaryNoSessionDescription,
    facts: [
      DiagnosticSummaryFact(label: l.summaryFactSession, value: 'none'),
      DiagnosticSummaryFact(label: l.summaryFactMesh, value: 'paused'),
      DiagnosticSummaryFact(label: l.summaryFactEvents, value: 'none'),
    ],
  );
}

/// Mirrors React `summaryTone(state)`: ready -> ready, waiting -> waiting,
/// any other state -> idle.
DiagnosticSummaryTone _summaryTone(String state) {
  switch (state) {
    case 'ready':
      return DiagnosticSummaryTone.ready;
    case 'waiting':
      return DiagnosticSummaryTone.waiting;
    default:
      return DiagnosticSummaryTone.idle;
  }
}

/// Mirrors React `sessionDescription(state, mesh)`: ready+peers -> ready-with-
/// peers, ready+no-peers -> ready-no-peers, waiting -> waiting, else idle.
/// The strings are localized via ARB (`summaryReadyWithPeers` etc.).
String _sessionDescription(AppLocalizations l, String state, MeshInfo? mesh) {
  if (state == 'ready') {
    return mesh != null && mesh.peerCount > 0
        ? l.summaryReadyWithPeers
        : l.summaryReadyNoPeers;
  }
  if (state == 'waiting') {
    return l.summaryWaiting;
  }
  return l.summaryIdle;
}
