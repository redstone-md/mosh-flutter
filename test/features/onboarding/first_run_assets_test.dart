import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

void main() {
  for (final name in ['welcome', 'devices', 'network']) {
    test('$name illustration preserves transparency and translucent light', () {
      final decoded = image
          .decodePng(File('assets/onboarding/$name.png').readAsBytesSync())!;
      expect(decoded.numChannels, 4);
      expect(decoded.getPixel(0, 0).a, 0);
      var translucent = false;
      var subject = false;
      for (var y = 0; y < decoded.height; y += 16) {
        for (var x = 0; x < decoded.width; x += 16) {
          final alpha = decoded.getPixel(x, y).a;
          translucent |= alpha > 0 && alpha < 255;
          subject |= alpha > 0;
        }
      }
      expect(subject, isTrue);
      expect(translucent, isTrue);
    });
  }
}
