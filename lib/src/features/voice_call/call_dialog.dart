// Which call dialog a session is asking for, derived from that session's
// snapshot -- and from nothing else.
//
// mosh-core builds all three call fields of `SessionSnapshot` from one
// `CallState` phase (private_dm_runtime.rs), so a session carries at most
// one of them: pending (inbound, ringing), active (connected) or outgoing
// (dialled, unanswered). Which dialog the UI owes the user is therefore a
// pure function of one snapshot -- no phase machine, no timers, and no
// "which modal did I open last" bookkeeping on the widget that draws it.
library;

import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';

/// The call dialog a session wants shown. Sealed so the renderer must
/// handle every shape, and a value so a re-poll that changes nothing
/// produces an equal dialog and no re-mount.
sealed class CallDialog {
  const CallDialog();

  /// The call this dialog belongs to. A re-poll for the same call must
  /// not re-mount the dialog, so this is the dialog's identity.
  String get callId;

  /// The peer's name as the snapshot knows it -- empty until the runtime
  /// learns it. The renderer decides the fallback, because only it has
  /// localizations.
  String get peerName;
}

/// No call at all: the session's snapshot carries no call, so the UI owes
/// the user no dialog.
final class NoCallDialog extends CallDialog {
  const NoCallDialog();

  @override
  String get callId => '';

  @override
  String get peerName => '';

  @override
  bool operator ==(Object other) => other is NoCallDialog;

  @override
  int get hashCode => (NoCallDialog).hashCode;

  @override
  String toString() => 'NoCallDialog()';
}

/// An inbound call waiting for the local user to answer or decline.
final class IncomingCallDialog extends CallDialog {
  const IncomingCallDialog({required this.pending, required this.peerName});

  /// The pending call the modal renders (React `pendingCall`).
  final PendingCall pending;

  @override
  final String peerName;

  @override
  String get callId => pending.callId;

  @override
  bool operator ==(Object other) =>
      other is IncomingCallDialog &&
      other.pending == pending &&
      other.peerName == peerName;

  @override
  int get hashCode => Object.hash(IncomingCallDialog, pending, peerName);

  @override
  String toString() => 'IncomingCallDialog($callId, $peerName)';
}

/// A call the local user placed, waiting for the peer to pick up.
final class OutgoingCallDialog extends CallDialog {
  const OutgoingCallDialog({required this.call, required this.peerName});

  /// The outgoing call the modal renders (React `outgoingCall`).
  final OutgoingCall call;

  @override
  final String peerName;

  @override
  String get callId => call.callId;

  @override
  bool operator ==(Object other) =>
      other is OutgoingCallDialog &&
      other.call == call &&
      other.peerName == peerName;

  @override
  int get hashCode => Object.hash(OutgoingCallDialog, call, peerName);

  @override
  String toString() => 'OutgoingCallDialog($callId, $peerName)';
}

/// A connected call: the running overlay with the duration and controls.
final class ActiveCallDialog extends CallDialog {
  const ActiveCallDialog({required this.active, required this.peerName});

  /// The active call the overlay renders (React `activeCall`).
  final ActiveCall active;

  @override
  final String peerName;

  @override
  String get callId => active.callId;

  @override
  bool operator ==(Object other) =>
      other is ActiveCallDialog &&
      other.active == active &&
      other.peerName == peerName;

  @override
  int get hashCode => Object.hash(ActiveCallDialog, active, peerName);

  @override
  String toString() => 'ActiveCallDialog($callId, $peerName)';
}

/// The one derivation: a session snapshot -> the dialog it asks for.
///
/// Order matters only if a snapshot ever carried two calls at once, which
/// mosh-core cannot produce; it is written so a connected call outranks a
/// dialled one, matching the "an active call hides the outgoing modal"
/// rule the layer has always had.
CallDialog callDialogFor(SessionSnapshot? snapshot) {
  if (snapshot == null) return const NoCallDialog();
  final pending = snapshot.pendingCall;
  if (pending != null) {
    return IncomingCallDialog(pending: pending, peerName: pending.fromDevice);
  }
  final active = snapshot.activeCall;
  if (active != null) {
    return ActiveCallDialog(active: active, peerName: snapshot.peerDisplayName);
  }
  final outgoing = snapshot.outgoingCall;
  if (outgoing != null) {
    return OutgoingCallDialog(
        call: outgoing, peerName: snapshot.peerDisplayName);
  }
  return const NoCallDialog();
}
