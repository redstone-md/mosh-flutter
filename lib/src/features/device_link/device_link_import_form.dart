import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_field.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_icons.dart';

class DeviceLinkImportForm extends StatefulWidget {
  const DeviceLinkImportForm({
    super.key,
    required this.busy,
    required this.onSubmit,
    required this.onImage,
    this.onScan,
  });

  final bool busy;
  final ValueChanged<String> onSubmit;
  final VoidCallback onImage;
  final VoidCallback? onScan;

  @override
  State<DeviceLinkImportForm> createState() => _DeviceLinkImportFormState();
}

class _DeviceLinkImportFormState extends State<DeviceLinkImportForm> {
  final _uri = TextEditingController();

  @override
  void dispose() {
    _uri.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (widget.onScan != null) ...[
        FilledButton.icon(
          onPressed: widget.busy ? null : widget.onScan,
          icon: const Icon(MoshIcons.scan, size: 20),
          label: Text(l.deviceLinkScan),
        ),
        const SizedBox(height: 12),
      ],
      OutlinedButton.icon(
        onPressed: widget.busy ? null : widget.onImage,
        icon: const Icon(MoshIcons.image, size: 20),
        label: Text(l.deviceLinkImportImage),
      ),
      const SizedBox(height: 16),
      MoshField(
        label: l.deviceLinkPasteLabel,
        child: TextField(
          controller: _uri,
          maxLength: 2048,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.go,
          onSubmitted: widget.busy ? null : widget.onSubmit,
          decoration: InputDecoration(
            counterText: '',
            suffixIcon: IconButton(
              tooltip: l.deviceLinkImport,
              onPressed:
                  widget.busy ? null : () => widget.onSubmit(_uri.text.trim()),
              icon: const Icon(MoshIcons.forward),
            ),
          ),
        ),
      ),
    ]);
  }
}
