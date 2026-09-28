import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/device_link/device_link_qr.dart';
import 'package:mosh/src/features/device_link/qr_image.dart';

import '../../support/pump.dart';

void main() {
  testWidgets('a real rendered pairing QR can be imported from a desktop image',
      (tester) async {
    final link = 'mosh://device-link/${base64Url.encode(utf8.encode(jsonEncode({
              'version': 1,
              'id': 'a' * 32,
              'expires_at': 1790555000,
              'device': {
                'device_id': 'b' * 64,
                'signing_public_key': 'c' * 64,
                'moss_peer_id': 'd' * 64,
                'name': 'Second desktop',
              },
              'secret': List.generate(32, (index) => index + 1),
            }))).replaceAll('=', '')}';
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

  test('invalid and oversized images fail before QR import', () async {
    await expectLater(
        decodeDeviceQr(Uint8List.fromList([1, 2, 3])), throwsFormatException);
    await expectLater(
        decodeDeviceQr(Uint8List(10 * 1024 * 1024 + 1)), throwsFormatException);
  });
}
