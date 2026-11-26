import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mosh/src/features/device_link/device_link_qr.dart';
import 'package:mosh/src/features/device_link/qr_image.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../support/pump.dart';
import '../../support/device_link_fixture.dart';

void main() {
  testWidgets('a real rendered pairing QR can be imported from a desktop image',
      (tester) async {
    final link = deviceLinkQrFixture();
    const imageKey = ValueKey('rendered device QR');
    await pumpScreen(
        tester,
        Center(
            child: SizedBox(
                width: 300,
                height: 300,
                child: RepaintBoundary(
                    key: imageKey,
                    child: ColoredBox(
                        color: Colors.white,
                        child: DeviceLinkQr(uri: link, label: 'Device QR'))))));
    final boundary =
        tester.renderObject<RenderRepaintBoundary>(find.byKey(imageKey));
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      expect(await decodeDeviceQr(bytes!.buffer.asUint8List()), link);
      image.dispose();
    });
  });

  // Regression (CodeAnt PR #7): pixels went to the reader in the wrong
  // channel order. Blue on light yellow has one brightness in that order,
  // so the colored code read as blank.
  test('a QR drawn in blue on yellow is imported', () async {
    final link = deviceLinkQrFixture();
    final code = QrImage(QrValidator.validate(
            data: link,
            version: QrVersions.auto,
            errorCorrectionLevel: QrErrorCorrectLevel.L)
        .qrCode!);
    const scale = 6, quiet = 4;
    final side = (code.moduleCount + 2 * quiet) * scale;
    final image = img.Image(width: side, height: side)
      ..clear(img.ColorRgb8(255, 255, 128));
    for (var row = 0; row < code.moduleCount; row++) {
      for (var col = 0; col < code.moduleCount; col++) {
        if (!code.isDark(row, col)) continue;
        img.fillRect(image,
            x1: (col + quiet) * scale,
            y1: (row + quiet) * scale,
            x2: (col + quiet + 1) * scale - 1,
            y2: (row + quiet + 1) * scale - 1,
            color: img.ColorRgb8(0, 0, 255));
      }
    }

    expect(await decodeDeviceQr(img.encodePng(image)), link);
  });

  test('invalid and oversized images fail before QR import', () async {
    await expectLater(
        decodeDeviceQr(Uint8List.fromList([1, 2, 3])), throwsFormatException);
    await expectLater(
        decodeDeviceQr(Uint8List(10 * 1024 * 1024 + 1)), throwsFormatException);
  });
}
