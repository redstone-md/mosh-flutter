/// The line above the first message of a block: who sent it, their
/// fingerprint where there is one, the MLS badge, and the time. Tapping
/// someone else's name offers to start a DM with them.
library;

import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'package:mosh/src/features/conversation/conversation_helpers.dart';
import 'package:mosh/src/features/shared/modal_focus_trap.dart';
import 'package:mosh/src/util/format.dart' show shorten;

/// The shortened fingerprint chip in a multi-party sender meta: mono 10px
/// fg-4 text on a bg-2 rounded-4 background.
class DeviceFingerprintChip extends StatelessWidget {
  const DeviceFingerprintChip({super.key, required this.fingerprint});

  final String fingerprint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: MoshColors.bg2,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        shorten(fingerprint, 6),
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 10,
          color: MoshColors.fg4,
        ),
      ),
    );
  }
}

/// The meta row above the first message of a group of messages: the sender
/// name in bold, then the shortened fingerprint, the [MlsBadge] and the
/// local HH:mm time. Hovering the time shows the full date.
///
/// The three kinds differ only in which parts show:
///
/// - a DM has no per-message fingerprint, so [fromFingerprint] is null and
///   the chip is left out;
/// - a channel hides the MLS badge ([showMlsBadge] false), a group and a DM
///   show it.
///
/// Callers render this only on non-grouped rows: a continuation row omits
/// the whole meta.
class ConversationSenderMeta extends StatelessWidget {
  const ConversationSenderMeta({
    super.key,
    required this.fromDevice,
    required this.sentAtMs,
    this.fromFingerprint,
    this.peer,
    this.showMlsBadge = true,
  });

  final String fromDevice;

  /// The sender's device fingerprint, or null in a DM. When set, a
  /// [DeviceFingerprintChip] follows the name: a channel or a group can hold
  /// two members with the same display name, never with the same
  /// fingerprint.
  final String? fromFingerprint;

  final BigInt? sentAtMs;

  /// Turns a peer's name into a tap target that opens the nickname popover,
  /// where the user can start a DM with them. Null (the default) keeps the
  /// name plain bold, and so does the user's own name.
  final PeerActions? peer;

  /// Whether the [MlsBadge] follows the name. A channel hides it; a group
  /// and a DM show it.
  final bool showMlsBadge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locale = AppLocalizations.of(context)?.localeName;
    final clock = formatClock(sentAtMs, locale: locale);
    final full = formatClockFull(sentAtMs, locale: locale);
    final fingerprint = fromFingerprint;
    final nameWidget = _peerName(context, theme);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Flexible(child: nameWidget),
          if (fingerprint != null) ...[
            const SizedBox(width: kMessageMetaGap),
            DeviceFingerprintChip(fingerprint: fingerprint),
          ],
          if (showMlsBadge) ...[
            const SizedBox(width: kMessageMetaGap),
            const MlsBadge(),
          ],
          if (clock != null && full != null) ...[
            const SizedBox(width: kMessageMetaGap),
            Tooltip(
              message: full,
              child: Text(clock, style: kMessageTimeStyle),
            ),
          ],
        ],
      ),
    );
  }

  /// The name. Plain bold when there are no peer actions, when the row has
  /// no fingerprint to act on, or when the sender is the user. Otherwise the
  /// same bold text becomes a tap target that opens the nickname popover.
  Widget _peerName(BuildContext context, ThemeData theme) {
    final text = Text(
      fromDevice,
      style: kMessageMetaNameStyle,
      overflow: TextOverflow.ellipsis,
    );
    final actions = peer;
    final fingerprint = fromFingerprint;
    if (actions == null ||
        fingerprint == null ||
        fingerprint == actions.ownFingerprint) {
      return text;
    }
    return _PeerNickname(
      name: fromDevice,
      fingerprint: fingerprint,
      peer: actions,
      child: text,
    );
  }
}

/// What a sender name can do when the user taps it: whether it is the
/// user's own name, who has already been invited, whether an invite is in
/// flight, and how to start a DM. Built by the conversation screen and read
/// by [ConversationSenderMeta].
///
/// `offered` is the set of fingerprints the user already messaged this
/// session; it is reset when the active host changes (the screen owns that
/// reset). `busy` is the offer-in-flight flag. `onMessage` is the closure
/// that creates a DM invite, sends the offer over the channel/group, marks
/// the fingerprint offered, and navigates to the new DM.
@immutable
class PeerActions {
  const PeerActions({
    required this.ownFingerprint,
    required this.offered,
    required this.busy,
    required this.onMessage,
  });

  /// The user's own device fingerprint -- a name with this fingerprint
  /// renders as plain bold.
  final String ownFingerprint;

  /// Fingerprints already messaged this session -- a name in this set
  /// disables the "Message" button and relabels it "Invite sent".
  final Set<String> offered;

  /// True while a DM-offer send is in flight -- disables the "Message"
  /// button.
  final bool busy;

  /// Opens a 1:1 DM with the named peer. The screen wires this to
  /// `gateway.createInvite` + `sendChannelDmOffer`/`sendGroupDmOffer`,
  /// tracks the fingerprint as offered, and navigates to the new DM
  /// session.
  final Future<void> Function(String peerFingerprint) onMessage;
}

/// The nick-popover anchor + popover. Wraps the bold name `Text` (passed as
/// [child]) in an `InkWell` tap target; tapping opens a small `Dialog`
/// titled with the peer's name and a "Message" button that is disabled when
/// the peer is already offered OR the screen is busy, labelled "Invite
/// sent" when already offered, and otherwise calls
/// [PeerActions.onMessage] then closes the popover.
///
/// The visible name is the SAME bold `Text` the plain-bold branch renders
/// (passed in as [child]) so the meta row's typography is byte-identical
/// whether the name is tappable or plain -- the only delta is the tap
/// target wrapper.
class _PeerNickname extends StatelessWidget {
  const _PeerNickname({
    required this.name,
    required this.fingerprint,
    required this.peer,
    required this.child,
  });

  final String name;
  final String fingerprint;
  final PeerActions peer;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final alreadyOffered = peer.offered.contains(fingerprint);
    return InkWell(
      onTap: () => _show(context, l, alreadyOffered),
      borderRadius: BorderRadius.circular(4),
      child: child,
    );
  }

  // Opens the Dialog popover. `showDialog` with an `AlertDialog` handles
  // the backdrop + Esc dismiss.
  Future<void> _show(
      BuildContext context, AppLocalizations l, bool alreadyOffered) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => ModalFocusTrap(
        child: AlertDialog(
          title: Text(name),
          // The Message button: disabled when alreadyOffered || busy,
          // labelled "Invite sent" when already offered, otherwise
          // "Message". Tapping it closes the popover, then calls
          // `peer.onMessage(fingerprint)`.
          actions: [
            TextButton(
              onPressed: (alreadyOffered || peer.busy)
                  ? null
                  : () {
                      Navigator.of(dialogContext).pop();
                      peer.onMessage(fingerprint);
                    },
              child:
                  Text(alreadyOffered ? l.peerInviteSent : l.peerMessageAction),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l.dialogCancel),
            ),
          ],
        ),
      ),
    );
  }
}
