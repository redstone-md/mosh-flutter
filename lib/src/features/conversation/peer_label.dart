/// Resolves the human-readable label for a private-DM session's peer,
/// displayed in the DM screen AppBar title and the sessions rail row.
///
/// Ports React `peerLabel`
/// (mosh/src/features/private-dm/private-dm-screen.tsx:535-543):
///   function peerLabel(session: SessionSnapshot): string {
///     const peer = session.messages.find(
///       (message) => message.from_device !== session.display_name);
///     if (peer) return peer.from_device;
///     if (session.state === "ready") return "peer";
///     return session.role === "alice" ? "invite sent" : "joining";
///   }
///
/// The Flutter port prepends a `peerDisplayName` short-circuit: when the
/// runtime has already learned the remote peer's display name (populated
/// from inbound frames), it is returned immediately without scanning the
/// message log. This is a Flutter-side optimization over the legacy
/// React message-scan; the message-scan branch below remains as the
/// fallback for snapshots whose `peerDisplayName` has not been populated
/// yet, preserving React's exact branch order.
library;

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';

/// Returns the best-available peer label for [session], localized by [l].
///
/// Branch order (one-to-one with React `peerLabel`, plus the leading
/// `peerDisplayName` short-circuit):
///   1. [SessionSnapshot.peerDisplayName] non-empty -> return it
///      (Flutter runtime optimization; React skips this and scans messages).
///   2. else scan [SessionSnapshot.messages] for the first message whose
///      `fromDevice` differs from [SessionSnapshot.displayName]; return that
///      `fromDevice` (React primary branch, private-dm-screen.tsx:537-539).
///   3. else if [SessionSnapshot.state] is connected -> [AppLocalizations.callPeerFallback]
///      (React `"peer"`; reuses the existing "Peer" call-modal key).
///   4. else if [SessionSnapshot.role] == `"alice"` ->
///      [AppLocalizations.peerLabelInviteSent] (React `"invite sent"`).
///   5. else -> [AppLocalizations.peerLabelJoining] (React `"joining"`).
String peerLabel(AppLocalizations l, SessionSnapshot session) {
  // Flutter optimization: the runtime-populated peer device name short-
  // circuits the legacy message scan.
  if (session.peerDisplayName.isNotEmpty) return session.peerDisplayName;

  // React primary branch (private-dm-screen.tsx:537-539): first message
  // whose from_device differs from the local display_name reveals the peer.
  final peer = session.messages
      .firstWhereOrNull((m) => m.fromDevice != session.displayName);
  if (peer != null) return peer.fromDevice;

  // React ready branch (private-dm-screen.tsx:540-541): "peer".
  if (session.state == DmSessionState.connected) return l.callPeerFallback;

  // React role branch (private-dm-screen.tsx:542): alice -> "invite sent",
  // otherwise "joining".
  return session.role == 'alice' ? l.peerLabelInviteSent : l.peerLabelJoining;
}

// `firstWhereOrNull` is not in the core iterable API used elsewhere in this
// file's import surface; a tiny local extension keeps the helper self-
// contained and avoids pulling in `package:collection`.
extension _FirstWhereOrNull<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}
