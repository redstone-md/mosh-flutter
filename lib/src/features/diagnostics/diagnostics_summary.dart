/// Pure diagnostics-summary builder for the Diagnostics drawer, 1-в-1 with
/// React's `src/features/private-dm/DiagnosticsDrawerSummary.tsx`.
///
/// The React `diagnosticsSummary(session, channel, group, error)` has four
/// branches: `session` (private DM), `channel` (public channel), `group`
/// (private group), and the idle/error fallback. The channel and group
/// branches are now implemented (1-в-1 with React), now that the
/// `ChannelSnapshot` / `GroupSnapshot` contracts exist in the Flutter fork
/// (they landed earlier in `lib/src/rust/channel_runtime.dart` and
/// `lib/src/rust/private_group_runtime.dart`). The Flutter
/// `diagnosticsSummary` accepts the same four optional inputs
/// (`session?`, `channel?`, `group?`, `error?`) and resolves them in the
/// same branch order: session -> channel -> group -> idle/error.
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
import 'package:mosh/src/rust/channel_runtime.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/rust/conversation/mesh.dart';
import 'package:mosh/src/rust/private_group_runtime.dart';

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
  int get hashCode => Object.hash(
      tone, kicker, title, state, description, Object.hashAll(facts));

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

/// Builds the diagnostics summary, 1-в-1 with React
/// `diagnosticsSummary(session, channel, group, error)`. Resolves the four
/// branches in React order: `session` (private DM), `channel` (public
/// channel), `group` (private group), then the idle/error fallback when
/// all three are null.
///
/// `l` is the localized copy seam: the function is pure (deterministic
/// given `l`). The DM- and group-branch state badges use the existing
/// `stateReady` / `stateWaiting` / `stateIdle` keys via the shared
/// `stateLabel` mapper (mirrors React's `stateLabels[session.state] ??
/// session.state` with the raw-state fallback used by
/// `sessions_screen.dart`). The channel state badge ("Broadcast") and
/// the idle/error state badges use the `summaryChannelState` /
/// `summaryStateWaiting` / `summaryStateError` keys.
DiagnosticSummary diagnosticsSummary({
  required AppLocalizations l,
  SessionSnapshot? session,
  ChannelSnapshot? channel,
  GroupSnapshot? group,
  String? error,
}) {
  if (session != null) {
    final mesh = session.mesh;
    return DiagnosticSummary(
      tone: error != null
          ? DiagnosticSummaryTone.error
          : _summaryTone(session.state),
      kicker: l.summaryDmKicker,
      title: session.peerDisplayName.isNotEmpty
          ? session.peerDisplayName
          : (session.displayName.isNotEmpty
              ? session.displayName
              : 'Private session'),
      state: stateLabel(l, session.state),
      description: _sessionDescription(l, session.state, mesh),
      facts: [
        DiagnosticSummaryFact(
            label: l.summaryFactPeers, value: peerCount(mesh)),
        DiagnosticSummaryFact(label: l.summaryFactNat, value: natType(mesh)),
        DiagnosticSummaryFact(
            label: l.summaryFactRelay,
            value: mesh != null ? relayStatus(mesh) : 'booting'),
      ],
    );
  }
  // Channel branch -- mirrors React `if (channel)`. Channels are always
  // "ready" tone (no state-driven tone): tone is error -> error, else ready.
  // The title `#${channel.name}` is a literal (NOT localized), matching React.
  // The state badge ("Broadcast") and the description ARE localized via ARB.
  if (channel != null) {
    final mesh = channel.mesh;
    return DiagnosticSummary(
      tone: error != null
          ? DiagnosticSummaryTone.error
          : DiagnosticSummaryTone.ready,
      kicker: l.summaryChannelKicker,
      title: '#${channel.name}',
      state: l.summaryChannelState,
      description: l.summaryChannelDescription,
      facts: [
        DiagnosticSummaryFact(
            label: l.summaryFactPeers, value: peerCount(mesh)),
        DiagnosticSummaryFact(label: l.summaryFactNat, value: natType(mesh)),
        DiagnosticSummaryFact(
            label: l.summaryFactRelay,
            value: mesh != null ? relayStatus(mesh) : 'booting'),
      ],
    );
  }
  // Group branch -- mirrors React `if (group)`. Tone is error -> error, else
  // `summaryTone(group.state)` (the same state->tone mapping the DM branch
  // uses). The title falls back to the localized "Encrypted group" when the
  // group has no label; the state badge uses the shared `stateLabel` mapper
  // (like the DM branch); the description interpolates the member count. The
  // Members fact value is `group.memberCount.toString()` (BigInt -> decimal
  // string), matching React's `String(group.member_count)`.
  if (group != null) {
    final mesh = group.mesh;
    return DiagnosticSummary(
      tone: error != null
          ? DiagnosticSummaryTone.error
          : _summaryTone(group.state),
      kicker: l.summaryGroupKicker,
      title: group.label ?? l.summaryGroupFallbackTitle,
      state: stateLabel(l, group.state),
      description: l.summaryGroupDescription(group.memberCount.toString()),
      facts: [
        DiagnosticSummaryFact(
            label: l.summaryFactMembers, value: group.memberCount.toString()),
        DiagnosticSummaryFact(
            label: l.summaryFactPeers, value: peerCount(mesh)),
        DiagnosticSummaryFact(
            label: l.summaryFactRelay,
            value: mesh != null ? relayStatus(mesh) : 'booting'),
      ],
    );
  }
  // Idle/error fallback -- mirrors React's final `return` when all three of
  // session/channel/group are null. Tone is error -> error, else idle.
  return DiagnosticSummary(
    tone: error != null
        ? DiagnosticSummaryTone.error
        : DiagnosticSummaryTone.idle,
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
