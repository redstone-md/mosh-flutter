import 'package:flutter/material.dart';
import 'package:mosh/src/features/plus/user_plus_badge.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_shapes.dart';
import 'package:mosh/src/app/mosh_theme.dart'
    show MoshColors, MoshEmphasizedText;
import 'package:mosh/src/features/conversation/conversation_helpers.dart';
import 'package:mosh/src/features/shared/conversation_action_error.dart';
import 'package:mosh/src/features/shared/mosh_dialog.dart';
import 'package:mosh/src/features/shared/mosh_dialog_route.dart';
import 'package:mosh/src/util/format.dart' show shorten;

/// The shortened fingerprint beside a sender's name in a group or a
/// channel: a small plate that tells two members of one name apart.
class DeviceFingerprintChip extends StatelessWidget {
  const DeviceFingerprintChip({super.key, required this.fingerprint});

  final String fingerprint;

  @override
  Widget build(BuildContext context) {
    final colors = MoshColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: MoshSpace.s1),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: MoshShapes.embedded,
      ),
      child: Text(
        shorten(fingerprint, 6),
        style: Theme.of(context)
            .textTheme
            .labelSmall!
            .copyWith(color: colors.onSurfaceVariant),
      ),
    );
  }
}

/// The sender line inside the first bubble of a run in a group or a
/// channel: the name, emphasized, then the shortened fingerprint.
///
/// A DM has no per-message fingerprint, so [fromFingerprint] is null and the
/// chip is left out.
///
/// Callers render this only on non-grouped rows: a continuation row omits
/// the whole line.
class ConversationSenderMeta extends StatelessWidget {
  const ConversationSenderMeta({
    super.key,
    required this.fromDevice,
    this.fromFingerprint,
    this.peer,
    this.plusIdentity,
  });

  final String fromDevice;
  final String? plusIdentity;

  /// The sender's device fingerprint, or null in a DM. When set, a
  /// [DeviceFingerprintChip] follows the name: a channel or a group can hold
  /// two members with the same display name, never with the same
  /// fingerprint.
  final String? fromFingerprint;

  /// Turns a peer's name into a tap target that opens the nickname popover,
  /// where the user can start a DM with them. Null (the default) keeps the
  /// name plain, and so does the user's own name.
  final PeerActions? peer;

  @override
  Widget build(BuildContext context) {
    final fingerprint = fromFingerprint;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: _peerName(context)),
        UserPlusBadge(identity: plusIdentity),
        if (fingerprint != null) ...[
          const SizedBox(width: kMessageMetaGap),
          DeviceFingerprintChip(fingerprint: fingerprint),
        ],
      ],
    );
  }

  /// The name. Plain bold when there are no peer actions, when the row has
  /// no fingerprint to act on, or when the sender is the user. Otherwise the
  /// same bold text becomes a tap target that opens the nickname popover.
  Widget _peerName(BuildContext context) {
    final text = Text(
      fromDevice,
      style: MoshEmphasizedText.labelLarge
          .copyWith(color: MoshColors.of(context).onSurface),
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
/// sent" when already offered. Otherwise it closes the popover, calls
/// [PeerActions.onMessage], and reports any failure as an error toast.
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
      borderRadius: MoshShapes.embedded,
      child: child,
    );
  }

  Future<void> _show(
    BuildContext context,
    AppLocalizations l,
    bool alreadyOffered,
  ) async {
    final reportError = actionErrorReporter(context);
    await showMoshDialog<void>(
      context: context,
      builder: (dialogContext) => MoshDialog(
        title: name,
        closeLabel: l.dialogCancel,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l.dialogCancel),
          ),
          FilledButton(
            onPressed: (alreadyOffered || peer.busy)
                ? null
                : () async {
                    Navigator.of(dialogContext).pop();
                    try {
                      await peer.onMessage(fingerprint);
                    } catch (error) {
                      reportError(error);
                    }
                  },
            child: Text(
              alreadyOffered ? l.peerInviteSent : l.peerMessageAction,
            ),
          ),
        ],
      ),
    );
  }
}
