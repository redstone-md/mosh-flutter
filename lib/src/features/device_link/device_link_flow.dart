import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/features/shared/toasts/toaster.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/features/settings/settings_card.dart';
import 'package:mosh/src/rust/device_link/types.dart';

import 'device_link_approval_form.dart';
import 'device_link_copy.dart';
import 'device_link_qr.dart';
import 'device_link_steps.dart';

/// Displays runtime proof and progress; the controller owns protocol decisions.
class DeviceLinkFlow extends StatelessWidget {
  const DeviceLinkFlow({
    super.key,
    required this.snapshot,
    required this.role,
    required this.busy,
    required this.onApprove,
    required this.onCancel,
    this.importForm,
  });

  final DeviceLinkSnapshot snapshot;
  final DeviceLinkRole role;
  final bool busy;
  final ValueChanged<String> onApprove;
  final VoidCallback onCancel;
  final Widget? importForm;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final joining = role == DeviceLinkRole.joining;
    return SettingsCard(
      icon: joining ? MoshIcons.qr : MoshIcons.devices,
      title: joining ? l.deviceLinkConnectThis : l.deviceLinkLinkOther,
      hint: importForm != null
          ? l.deviceLinkJoinHelp
          : deviceLinkPhase(l, snapshot.phase),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: MoshSpace.s1),
        DeviceLinkSteps(role: role, phase: snapshot.phase),
        const SizedBox(height: MoshSpace.s4),
        ..._content(context, l),
        const SizedBox(height: MoshSpace.s4),
        if (snapshot.phase != DeviceLinkPhase.delivering)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
                onPressed: busy ? null : onCancel,
                child: Text(l.deviceLinkDecline)),
          ),
      ]),
    );
  }

  List<Widget> _content(BuildContext context, AppLocalizations l) => [
        if (importForm != null) importForm!,
        if (snapshot.qrUri != null) ...[
          DeviceLinkQr(uri: snapshot.qrUri!, label: l.deviceLinkQrLabel),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () async {
              final toaster = context.toaster;
              await Clipboard.setData(ClipboardData(text: snapshot.qrUri!));
              toaster.show(l.messageCopied, kind: ToastKind.success);
            },
            icon: const Icon(MoshIcons.copy),
            label: Text(l.deviceLinkCopy),
          ),
          Text(l.deviceLinkExpires,
              style: Theme.of(context).textTheme.bodySmall),
        ],
        if (snapshot.pendingDevice != null) ...[
          Text(snapshot.pendingDevice!.name,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
        ],
        if (snapshot.confirmationCode case final code?)
          // A plate set into the card to hold the code apart.
          Container(
            padding: const EdgeInsets.symmetric(vertical: MoshSpace.s4),
            decoration: BoxDecoration(
              color: MoshColors.of(context).surfaceContainer,
              borderRadius:
                  const BorderRadius.all(Radius.circular(MoshRadius.small)),
            ),
            child: Column(children: [
              Text(l.deviceLinkConfirmationCode,
                  style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: MoshSpace.s1),
              SelectableText(code,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .displaySmall!
                      .copyWith(fontFeatures: kLiveNumberFontFeatures)),
            ]),
          ),
        if (snapshot.phase == DeviceLinkPhase.awaitingApproval)
          DeviceLinkApprovalForm(busy: busy, onApprove: onApprove),
        if (snapshot.phase == DeviceLinkPhase.connecting ||
            snapshot.phase == DeviceLinkPhase.delivering)
          const LinearProgressIndicator(),
      ];
}
