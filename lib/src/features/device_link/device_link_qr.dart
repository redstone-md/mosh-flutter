import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

const _padding = 16.0;
const _preferredModulePixels = 4;

/// Whole pixel modules keep dense pairing screenshots readable.
class DeviceLinkQr extends StatelessWidget {
  const DeviceLinkQr({required this.uri, required this.label, super.key});
  final String uri;
  final String label;

  @override
  Widget build(BuildContext context) {
    final qr = QrValidator.validate(
            data: uri,
            version: QrVersions.auto,
            errorCorrectionLevel: QrErrorCorrectLevel.L)
        .qrCode!;
    return LayoutBuilder(builder: (context, constraints) {
      final modulePixels =
          ((constraints.maxWidth - 2 * _padding) / qr.moduleCount)
              .floor()
              .clamp(1, _preferredModulePixels);
      final size = qr.moduleCount * modulePixels + 2 * _padding;
      final left = ((constraints.maxWidth - size) / 2).floorToDouble();
      return Padding(
          padding: EdgeInsets.only(left: left),
          child: Align(
              alignment: Alignment.topLeft,
              heightFactor: 1,
              child: QrImageView.withQr(
                  qr: qr,
                  size: size,
                  padding: const EdgeInsets.all(_padding),
                  backgroundColor: Colors.white,
                  semanticsLabel: label)));
    });
  }
}
