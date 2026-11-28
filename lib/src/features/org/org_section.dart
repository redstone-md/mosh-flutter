import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_shapes.dart';
import 'package:mosh/src/app/mosh_spinner.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'package:mosh/src/features/shared/avatar.dart';
import 'package:mosh/src/features/shared/focus_ring.dart';
import 'package:mosh/src/features/shared/invitation_row.dart';
import 'package:mosh/src/rust/org_runtime.dart';
import 'package:mosh/src/util/format.dart' show shorten;

/// The Organisation card: a member of an organisation sees its people under
/// the chats, who of them wants to talk, and a field to start a group with
/// them. While [busy] a change is on its way and the controls wait.
class OrgSection extends StatelessWidget {
  const OrgSection({
    super.key,
    required this.org,
    required this.busy,
    required this.onMember,
    required this.onAcceptDmOffer,
    required this.onDismissDmOffer,
    required this.onAcceptGroupOffer,
    required this.onDismissGroupOffer,
    required this.onCreateGroup,
    required this.onLeave,
    required this.l,
  });

  final OrgSnapshot org;
  final bool busy;
  final void Function(OrgSnapshot org, OrgMemberView member) onMember;
  final void Function(String orgPubkey, String offerId) onAcceptDmOffer;
  final void Function(String orgPubkey, String offerId) onDismissDmOffer;
  final void Function(String orgPubkey, String offerId) onAcceptGroupOffer;
  final void Function(String orgPubkey, String offerId) onDismissGroupOffer;
  final void Function(OrgSnapshot org, String label) onCreateGroup;
  final void Function(OrgSnapshot org) onLeave;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final selfIsAdmin = org.members.any((m) => m.isSelf && m.role == 'admin');
    return Semantics(
      label: l.orgSectionAria(org.orgName),
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(org: org, busy: busy, onLeave: onLeave, l: l),
          if (!org.inRoster) _RosterNotice(code: org.confirmationCode, l: l),
          for (final offer in org.dmOffers)
            InvitationRow(
              leading: Avatar(
                  name: offer.fromName,
                  radius: 20,
                  plusIdentity: offer.fromPeerId),
              title: offer.fromName,
              detail: l.orgDmOffer,
              acceptLabel: l.orgAcceptDmAria(offer.fromName),
              declineLabel: l.orgDismissDmAria(offer.fromName),
              onAccept: _unlessBusy(
                  () => onAcceptDmOffer(org.orgPubkey, offer.offerId)),
              onDecline: _unlessBusy(
                  () => onDismissDmOffer(org.orgPubkey, offer.offerId)),
            ),
          for (final offer in org.groupOffers) _groupOffer(offer),
          if (org.inRoster && selfIsAdmin)
            _NewGroupForm(org: org, busy: busy, onCreate: onCreateGroup, l: l),
          for (final member in org.members)
            _MemberRow(
              member: member,
              org: org,
              busy: busy,
              onMember: onMember,
              l: l,
            ),
        ],
      ),
    );
  }

  /// While a change is on its way the section's controls wait.
  VoidCallback? _unlessBusy(VoidCallback action) => busy ? null : action;

  Widget _groupOffer(OrgGroupOfferView offer) {
    final label =
        (offer.groupLabel ?? '').isEmpty ? l.orgGroupOffer : offer.groupLabel!;
    return InvitationRow(
      leading: Avatar(name: label, radius: 20, sign: MoshIcons.group),
      title: label,
      detail: l.orgGroupOfferFrom(offer.fromName),
      acceptLabel: l.orgAcceptGroupAria(offer.fromName),
      declineLabel: l.orgDismissGroupAria(offer.fromName),
      onAccept:
          _unlessBusy(() => onAcceptGroupOffer(org.orgPubkey, offer.offerId)),
      onDecline:
          _unlessBusy(() => onDismissGroupOffer(org.orgPubkey, offer.offerId)),
    );
  }
}

/// The Organisation header card: the organisation's glyph and name, and the
/// button that leaves it.
class _Header extends StatelessWidget {
  const _Header({
    required this.org,
    required this.busy,
    required this.onLeave,
    required this.l,
  });
  final OrgSnapshot org;
  final bool busy;
  final void Function(OrgSnapshot) onLeave;
  final AppLocalizations l;
  @override
  Widget build(BuildContext context) {
    final ink = MoshColors.of(context).onSurfaceMuted;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: MoshSpace.s12),
      child: Padding(
        padding: const EdgeInsetsDirectional.only(start: MoshSpace.s3),
        child: Row(
          spacing: MoshSpace.s2,
          children: [
            Icon(MoshIcons.organisation, size: MoshSpace.s4, color: ink),
            Expanded(
              child: Text(
                org.orgName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .labelLarge!
                    .copyWith(color: ink),
              ),
            ),
            IconButton(
              icon: const Icon(MoshIcons.close),
              tooltip: l.orgLeave,
              onPressed: busy ? null : () => onLeave(org),
            ),
          ],
        ),
      ),
    );
  }
}

/// The Roster notice card: the section is waiting for the list of members.
/// It also shows [code], which an admin needs to add this device and which
/// is shown nowhere else.
class _RosterNotice extends StatelessWidget {
  const _RosterNotice({required this.code, required this.l});
  final String code;
  final AppLocalizations l;
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = MoshColors.of(context);
    final quiet = text.bodySmall!.copyWith(color: colors.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.all(MoshSpace.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: MoshSpace.s3,
        children: [
          Row(
            spacing: MoshSpace.s3,
            children: [
              IconTheme.merge(
                  data: IconThemeData(color: colors.primary),
                  child: const MoshSpinner()),
              Expanded(child: Text(l.orgRosterWaiting, style: quiet)),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(code, style: text.titleSmall),
              Text(l.orgPendingHint, style: quiet),
            ],
          ),
        ],
      ),
    );
  }
}

class _NewGroupForm extends StatefulWidget {
  const _NewGroupForm({
    required this.org,
    required this.busy,
    required this.onCreate,
    required this.l,
  });
  final OrgSnapshot org;
  final bool busy;
  final void Function(OrgSnapshot, String) onCreate;
  final AppLocalizations l;
  @override
  State<_NewGroupForm> createState() => _NewGroupFormState();
}

class _NewGroupFormState extends State<_NewGroupForm> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (widget.busy) return;
    final label = _controller.text;
    widget.onCreate(widget.org, label);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: MoshSpace.s12),
      child: Padding(
        padding: const EdgeInsetsDirectional.only(
            start: MoshSpace.s3, top: MoshSpace.s1, bottom: MoshSpace.s1),
        child: Row(
          spacing: MoshSpace.s1,
          children: [
            Expanded(
              // The placeholder names the field for the eye, so it has no
              // label above; a screen reader keeps the name once it is
              // typed over.
              child: Semantics(
                label: widget.l.orgNewGroupLabel,
                // A text field sets its value in bodyLarge, the card in
                // bodyMedium.
                child: Theme(
                  data: theme.copyWith(
                      textTheme: text.copyWith(bodyLarge: text.bodyMedium)),
                  child: TextField(
                    controller: _controller,
                    enabled: !widget.busy,
                    decoration:
                        InputDecoration(hintText: widget.l.orgNewGroupLabel),
                    onSubmitted: (_) => _submit(),
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(MoshIcons.add),
              tooltip: widget.l.orgNewGroup,
              onPressed: widget.busy ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}

/// The Member row card: a member's avatar, name and peer, with the mark of
/// an admin. A tap opens a chat with anyone but ourselves.
class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.org,
    required this.busy,
    required this.onMember,
    required this.l,
  });
  final OrgMemberView member;
  final OrgSnapshot org;
  final bool busy;
  final void Function(OrgSnapshot, OrgMemberView) onMember;
  final AppLocalizations l;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = MoshColors.of(context);
    final name = member.isSelf ? l.ownMemberName(member.name) : member.name;
    return InkWell(
      borderRadius: MoshShapes.conversationRow,
      onTap: (busy || member.isSelf) ? null : () => onMember(org, member),
      child: FocusRing(
        radius: MoshShapes.conversationRow,
        child: Container(
          constraints:
              BoxConstraints(minHeight: MoshControl.height(theme.platform)),
          padding: const EdgeInsets.symmetric(
              vertical: MoshSpace.s1, horizontal: MoshSpace.s3),
          child: Row(
            spacing: MoshSpace.s3,
            children: [
              Avatar(
                  name: member.name,
                  plusIdentity: member.mossPeerId,
                  ownPlus: member.isSelf),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _line(name, theme.textTheme.labelLarge),
                    _line(shorten(member.mossPeerId, 6),
                        theme.textTheme.labelSmall),
                  ],
                ),
              ),
              if (member.role == 'admin')
                // A static role marker, so text ink rather than the accent.
                Icon(
                  MoshIcons.admin,
                  size: MoshSpace.s4,
                  color: colors.onSurfaceVariant,
                  semanticLabel: l.orgAdminBadge,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _line(String value, TextStyle? style) =>
      Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
}
