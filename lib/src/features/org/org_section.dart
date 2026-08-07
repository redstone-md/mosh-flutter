// OrgSection -- 1-в-1 port of React `src/features/private-dm/org/
// OrgSection.tsx`. All 9 callbacks pass through unchanged so the
// host wires them to the Gateway seam.

library;

import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/shared/avatar.dart';
import 'package:mosh/src/rust/org_runtime.dart';
import 'package:mosh/src/util/format.dart' show shorten;

/// The org-roster rail section -- 1-в-1 with React's `OrgSection`.
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
    final theme = Theme.of(context);
    final selfIsAdmin = org.members.any((m) => m.isSelf && m.role == 'admin');
    return Semantics(
      label: 'Organization ${org.orgName}',
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(org: org, busy: busy, onLeave: onLeave, l: l),
          if (!org.inRoster)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    org.confirmationCode,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(l.orgPendingHint, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          for (final offer in org.dmOffers)
            _DmOfferRow(
              offer: offer,
              orgPubkey: org.orgPubkey,
              busy: busy,
              onAccept: onAcceptDmOffer,
              onDismiss: onDismissDmOffer,
              l: l,
            ),
          for (final offer in org.groupOffers)
            _GroupOfferRow(
              offer: offer,
              orgPubkey: org.orgPubkey,
              busy: busy,
              onAccept: onAcceptGroupOffer,
              onDismiss: onDismissGroupOffer,
              l: l,
            ),
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
}

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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.apartment, size: 14),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              org.orgName,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 10),
            tooltip: l.orgLeave,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            onPressed: busy ? null : () => onLeave(org),
          ),
        ],
      ),
    );
  }
}

class _DmOfferRow extends StatelessWidget {
  const _DmOfferRow({
    required this.offer,
    required this.orgPubkey,
    required this.busy,
    required this.onAccept,
    required this.onDismiss,
    required this.l,
  });
  final OrgDmOfferView offer;
  final String orgPubkey;
  final bool busy;
  final void Function(String, String) onAccept;
  final void Function(String, String) onDismiss;
  final AppLocalizations l;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: busy ? null : () => onAccept(orgPubkey, offer.offerId),
              child: Row(
                children: [
                  Avatar(name: offer.fromName, radius: 12),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          offer.fromName,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(l.orgDmOffer, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                  const Icon(Icons.chat_bubble_outline, size: 10),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 10),
            tooltip: l.orgDismissDmAria(offer.fromName),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            onPressed: busy ? null : () => onDismiss(orgPubkey, offer.offerId),
          ),
        ],
      ),
    );
  }
}

class _GroupOfferRow extends StatelessWidget {
  const _GroupOfferRow({
    required this.offer,
    required this.orgPubkey,
    required this.busy,
    required this.onAccept,
    required this.onDismiss,
    required this.l,
  });
  final OrgGroupOfferView offer;
  final String orgPubkey;
  final bool busy;
  final void Function(String, String) onAccept;
  final void Function(String, String) onDismiss;
  final AppLocalizations l;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = (offer.groupLabel == null || offer.groupLabel!.isEmpty)
        ? l.orgGroupOffer
        : offer.groupLabel!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: busy ? null : () => onAccept(orgPubkey, offer.offerId),
              child: Row(
                children: [
                  const Icon(Icons.group, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${l.orgGroupOfferFrom} ${offer.fromName}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 10),
            tooltip: l.orgDismissGroupAria(offer.fromName),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            onPressed: busy ? null : () => onDismiss(orgPubkey, offer.offerId),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              enabled: !widget.busy,
              decoration: InputDecoration(
                hintText: widget.l.orgNewGroupPlaceholder,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submit(),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add, size: 13),
            tooltip: widget.l.orgNewGroup,
            onPressed: widget.busy ? null : _submit,
          ),
        ],
      ),
    );
  }
}

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
    final name = member.isSelf
        ? '${member.name} (${l.orgYouBadge})'
        : member.name;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: InkWell(
        onTap: (busy || member.isSelf) ? null : () => onMember(org, member),
        child: Row(
          children: [
            Avatar(name: member.name, radius: 12),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    shorten(member.mossPeerId, 6),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (member.role == 'admin')
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(
                  Icons.workspace_premium,
                  size: 11,
                  color: theme.colorScheme.primary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
