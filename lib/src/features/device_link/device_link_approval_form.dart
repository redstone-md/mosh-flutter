import 'package:flutter/material.dart';
import 'package:mosh/l10n/app_localizations.dart';

class DeviceLinkApprovalForm extends StatefulWidget {
  const DeviceLinkApprovalForm({
    super.key,
    required this.busy,
    required this.onApprove,
  });

  final bool busy;
  final ValueChanged<String> onApprove;

  @override
  State<DeviceLinkApprovalForm> createState() => _DeviceLinkApprovalFormState();
}

class _DeviceLinkApprovalFormState extends State<DeviceLinkApprovalForm> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller: _code,
        maxLength: 12,
        autocorrect: false,
        enableSuggestions: false,
        textCapitalization: TextCapitalization.characters,
        textInputAction: TextInputAction.done,
        onSubmitted: widget.busy ? null : widget.onApprove,
        decoration: InputDecoration(labelText: l.deviceLinkCodeLabel),
      ),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: widget.busy ? null : () => widget.onApprove(_code.text),
        child: Text(l.deviceLinkApprove),
      ),
    ]);
  }
}
