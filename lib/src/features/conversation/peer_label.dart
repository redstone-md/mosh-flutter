/// Resolves the human-readable label for a private-DM session's peer,
/// displayed in the DM screen AppBar title and the sessions rail row.
///
/// Resolution order: when the runtime has already learned the remote
/// peer's display name (populated from inbound frames), it is returned
/// immediately without scanning the message log. Otherwise the message
/// scan below is the fallback for snapshots whose `peerDisplayName` has
/// not been populated yet.
library;

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';

/// Returns the best-available peer label for [session], localized by [l].
///
/// Branch order:
///   1. [SessionSnapshot.peerDisplayName] non-empty -> return it.
///   2. else scan [SessionSnapshot.messages] for the first message whose
///      `fromDevice` differs from [SessionSnapshot.displayName]; return that
///      `fromDevice`.
///   3. else if [SessionSnapshot.state] is connected -> [AppLocalizations.callPeerFallback]
///      (reuses the existing "Peer" call-modal key).
///   4. else if [SessionSnapshot.role] == `"alice"` ->
///      [AppLocalizations.peerLabelInviteSent].
///   5. else -> [AppLocalizations.peerLabelJoining].
String peerLabel(AppLocalizations l, SessionSnapshot session) {
  // The runtime-populated peer device name short-circuits the message scan.
  if (session.peerDisplayName.isNotEmpty) return session.peerDisplayName;

  // The first message whose fromDevice differs from the local displayName
  // reveals the peer.
  final peer = session.messages
      .firstWhereOrNull((m) => m.fromDevice != session.displayName);
  if (peer != null) return peer.fromDevice;

  if (session.state == DmSessionState.connected) return l.callPeerFallback;

  // Alice has not been answered yet -> "invite sent", otherwise "joining".
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
