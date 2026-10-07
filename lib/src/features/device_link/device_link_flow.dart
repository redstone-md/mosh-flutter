import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mosh/src/features/shared/toasts/toaster.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_shapes.dart';
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
      icon: joining ? Icons.qr_code_scanner : Icons.add_link,
      title: joining ? l.deviceLinkConnectThis : l.deviceLinkLinkOther,
      hint: importForm != null
          ? l.deviceLinkJoinHelp
          : deviceLinkPhase(l, snapshot.phase),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DeviceLinkSteps(role: role, phase: snapshot.phase),
        const SizedBox(height: 20),
        ..._content(context, l),
        const SizedBox(height: 16),
        if (snapshot.phase != DeviceLinkPhase.delivering)
          TextButton(
              onPressed: busy ? null : onCancel,
              child: Text(l.deviceLinkDecline)),
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
            icon: const Icon(Icons.copy, size: 18),
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
        if (snapshot.confirmationCode != null)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: MoshColors.bg0,
              borderRadius: MoshShapes.conversationRow,
              border: Border.all(color: MoshColors.lineStrong),
            ),
            child: SelectableText(snapshot.confirmationCode!,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontFamily: 'monospace', letterSpacing: 2)),
          ),
        if (snapshot.phase == DeviceLinkPhase.awaitingApproval)
          DeviceLinkApprovalForm(busy: busy, onApprove: onApprove),
        if (snapshot.phase == DeviceLinkPhase.connecting ||
            snapshot.phase == DeviceLinkPhase.delivering)
          const LinearProgressIndicator(),
      ];
}
