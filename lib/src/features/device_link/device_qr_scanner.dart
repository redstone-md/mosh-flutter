import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:mosh/l10n/app_localizations.dart';

/// The scanner owns camera lifecycle and permissions. URI validation stays native.
class DeviceQrScanner extends StatefulWidget {
  const DeviceQrScanner({super.key});

  @override
  State<DeviceQrScanner> createState() => _DeviceQrScannerState();
}

class _DeviceQrScannerState extends State<DeviceQrScanner> {
  bool _returned = false;

  void _detected(BarcodeCapture capture) {
    if (_returned) return;
    for (final barcode in capture.barcodes) {
      final uri = barcode.rawValue;
      if (uri == null || uri.isEmpty) continue;
      _returned = true;
      Navigator.of(context).pop(uri);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l.deviceLinkScan)),
      body: Column(children: [
        Expanded(
            child: MobileScanner(
          onDetect: _detected,
          errorBuilder: (context, error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                error.errorCode == MobileScannerErrorCode.permissionDenied
                    ? l.deviceLinkCameraDenied
                    : l.deviceLinkCameraUnavailable,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        )),
        _help(l),
      ]),
    );
  }

  Widget _help(AppLocalizations l) => Align(
        alignment: Alignment.bottomCenter,
        child: SafeArea(
          minimum: const EdgeInsets.all(16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(l.deviceLinkScanHint, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l.deviceLinkCameraFallback)),
              ]),
            ),
          ),
        ),
      );
}
