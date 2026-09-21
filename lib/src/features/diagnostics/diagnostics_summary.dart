/// Pure diagnostics-summary builder for the Diagnostics drawer.
///
/// `diagnosticsSummary` has four branches: `session` (private DM),
/// `channel` (public channel), `group` (private group), and the
/// idle/error fallback. It accepts the four optional inputs (`session?`,
/// `channel?`, `group?`, `error?`) and resolves them in that branch
/// order: session -> channel -> group -> idle/error.
///
/// Pureness: the function takes `AppLocalizations l` (the localized copy
/// seam) plus the runtime inputs and returns a fully-resolved
/// `DiagnosticSummary`. It is deterministic given `l` -- the same `l` plus
/// the same inputs always produce the same output, so it stays unit-testable
/// (the tests construct an `AppLocalizations` from the en delegate via a
/// localized `MaterialApp` harness and assert on the returned fields) --
/// while keeping all user-facing strings flowing through ARB.
library;

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/diagnostics/diagnostics_helpers.dart';
import 'package:mosh/src/features/conversation/dm_state.dart';
import 'package:mosh/src/features/diagnostics/state_label.dart';
import 'package:mosh/src/rust/channel_runtime.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/rust/conversation/mesh.dart';
import 'package:mosh/src/rust/private_group_runtime.dart';

/// Tone of a `DiagnosticSummary`. Drives the summary's color: ready =
/// green, waiting = amber, idle = grey, error = red.
enum DiagnosticSummaryTone { ready, waiting, idle, error }

/// One row of the summary facts grid: a localized label plus a data value.
/// The value is NOT localized (it is a data token like "booting",
/// "unknown", "none", "paused", or a numeric relay status).
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

/// The full summary payload rendered by `SummaryCard`: tone, kicker,
/// title, state (the localized state-badge text), description, and the
/// facts grid.
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

/// Builds the diagnostics summary. Resolves the four branches in order:
/// `session` (private DM), `channel` (public channel), `group` (private
/// group), then the idle/error fallback when all three are null.
///
/// `l` is the localized copy seam: the function is pure (deterministic
/// given `l`). The DM- and group-branch state badges use the existing
/// `stateReady` / `stateWaiting` / `stateIdle` keys via the shared
/// `stateLabel` mapper (with the raw-state fallback used by
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
          : _summaryTone(dmPillState(session.state)),
      kicker: l.summaryDmKicker,
      title: session.peerDisplayName.isNotEmpty
          ? session.peerDisplayName
          : (session.displayName.isNotEmpty
              ? session.displayName
              : 'Private session'),
      state: dmStateLabel(l, session.state),
      description: _dmDescription(l, session.state, mesh),
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
  // Channel branch. Channels are always "ready" tone (no state-driven
  // tone): tone is error -> error, else ready. The title `#${channel.name}`
  // is a literal (NOT localized). The state badge ("Broadcast") and the
  // description ARE localized via ARB.
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
  // Group branch. Tone is error -> error, else `_summaryTone(group.state)`
  // (the same state->tone mapping the DM branch uses). The title falls
  // back to the localized "Encrypted group" when the group has no label;
  // the state badge uses the shared `stateLabel` mapper (like the DM
  // branch); the description interpolates the member count. The Members
  // fact value is `group.memberCount.toString()` (BigInt -> decimal
  // string).
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
  // Idle/error fallback when all three of session/channel/group are null.
  // Tone is error -> error, else idle.
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

/// Maps a state to a tone: ready -> ready, waiting -> waiting, any other
/// state -> idle.
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

/// One line on what the DM's state means: connected with or without peers
/// in the mesh report, waiting for the contact, or the contact is offline.
String _dmDescription(
    AppLocalizations l, DmSessionState state, MeshInfo? mesh) {
  switch (state) {
    case DmSessionState.connected:
      return mesh != null && mesh.peerCount > 0
          ? l.summaryReadyWithPeers
          : l.summaryReadyNoPeers;
    case DmSessionState.pending:
      return l.summaryWaiting;
    case DmSessionState.handshaking:
      return l.stateOfflineSentence;
  }
}
