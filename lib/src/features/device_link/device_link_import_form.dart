import 'package:flutter/material.dart';
import 'package:mosh/l10n/app_localizations.dart';

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
          icon: const Icon(Icons.qr_code_scanner, size: 20),
          label: Text(l.deviceLinkScan),
        ),
        const SizedBox(height: 12),
      ],
      OutlinedButton.icon(
        onPressed: widget.busy ? null : widget.onImage,
        icon: const Icon(Icons.image_outlined, size: 20),
        label: Text(l.deviceLinkImportImage),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _uri,
        maxLength: 2048,
        autocorrect: false,
        enableSuggestions: false,
        textInputAction: TextInputAction.go,
        onSubmitted: widget.busy ? null : widget.onSubmit,
        decoration: InputDecoration(
          labelText: l.deviceLinkPasteLabel,
          counterText: '',
          suffixIcon: IconButton(
            tooltip: l.deviceLinkImport,
            onPressed:
                widget.busy ? null : () => widget.onSubmit(_uri.text.trim()),
            icon: const Icon(Icons.arrow_forward),
          ),
        ),
      ),
    ]);
  }
}
