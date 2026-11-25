import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/sessions/rail_compact.dart';
import 'package:mosh/src/features/shared/avatar.dart';
import 'package:mosh/src/features/shared/invitation_row.dart';
import 'package:mosh/src/gateway/conversation_target.dart'
    show ConversationKind;
import 'package:mosh/src/state/dm_offer_providers.dart' show PendingDmOffer;

/// One pending offer of a personal chat, made in a channel or a group: an
/// [InvitationRow] whose two buttons accept and dismiss it. In the collapsed
/// list it is an avatar that expands the list, so a click never accepts.
class DmOfferRow extends StatelessWidget {
  const DmOfferRow({
    super.key,
    required this.pending,
    required this.onAccept,
    required this.onDismiss,
  });

  final PendingDmOffer pending;
  final VoidCallback onAccept;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final offer = pending.offer;
    final compact = RailCompactScope.of(context);
    final avatar = Avatar(
        name: offer.fromDevice,
        radius: compact ? 24 : 20,
        // Only an offer whose sender the runtime proved shows their Mosh+.
        plusIdentity:
            offer.authenticated == true ? offer.fromFingerprint : null);
    final detail = pending.kind == ConversationKind.channel
        ? '#${pending.host}'
        : l.onboardGroupInvite;
    if (compact) {
      return CompactExpandItem(
          leading: avatar, name: offer.fromDevice, detail: detail);
    }
    return InvitationRow(
      leading: avatar,
      title: offer.fromDevice,
      detail: detail,
      acceptLabel: l.railOfferAccept(offer.fromDevice),
      declineLabel: l.railOfferDismiss,
      onAccept: onAccept,
      onDecline: onDismiss,
    );
  }
}
