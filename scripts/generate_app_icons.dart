// Export docs/assets/mosh-mark.svg to a transparent 1024px PNG at
// assets/branding/mosh-mark.png, then run: dart run scripts/generate_app_icons.dart
import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;

const _source = 'assets/branding/mosh-mark.png';
final _lime = img.ColorRgb8(183, 216, 74);

Future<void> main() async {
  final logo = img.decodePng(await File(_source).readAsBytes());
  if (logo == null || logo.width != 1024 || logo.height != 1024) {
    throw StateError('Export the SVG to a 1024 × 1024 PNG at $_source.');
  }
  final corners = [(0, 0), (1023, 0), (0, 1023), (1023, 1023)];
  if (logo.numChannels != 4 ||
      corners.any((point) => logo.getPixel(point.$1, point.$2).a != 0)) {
    throw StateError('The source PNG must have transparent corners.');
  }
  await _windows(logo);
  await _apple(logo, 'macos/Runner/Assets.xcassets/AppIcon.appiconset',
      inset: true);
  await _apple(logo, 'ios/Runner/Assets.xcassets/AppIcon.appiconset',
      opaque: true);
  await _android(logo);
  stdout.writeln('Generated Windows, macOS, iOS and Android app icons.');
}

img.Image _resize(img.Image logo, int size) => img.copyResize(logo,
    width: size, height: size, interpolation: img.Interpolation.average);

Future<void> _writePng(String path, img.Image image) async =>
    File(path).writeAsBytes(img.encodePng(image));

Future<void> _windows(img.Image logo) async {
  final frames = [
    for (final size in [16, 24, 32, 48, 64, 128, 256]) _resize(logo, size)
  ];
  await File('windows/runner/resources/app_icon.ico')
      .writeAsBytes(img.IcoEncoder().encodeImages(frames));
}

Future<void> _apple(img.Image logo, String directory,
    {bool opaque = false, bool inset = false}) async {
  final manifest =
      jsonDecode(await File('$directory/Contents.json').readAsString())
          as Map<String, dynamic>;
  final written = <String>{};
  for (final entry in manifest['images'] as List) {
    final filename = entry['filename'] as String;
    if (!written.add(filename)) continue;
    final logicalSize = double.parse((entry['size'] as String).split('x')[0]);
    final scale = double.parse((entry['scale'] as String).replaceAll('x', ''));
    final size = (logicalSize * scale).round();
    final canvas =
        img.Image(width: size, height: size, numChannels: opaque ? 3 : 4);
    if (opaque) img.fill(canvas, color: _lime);
    final mark = _resize(logo, inset ? (size * .8).round() : size);
    img.compositeImage(canvas, mark, center: true);
    await _writePng('$directory/$filename', canvas);
  }
}

Future<void> _android(img.Image logo) async {
  const sizes = {
    'mdpi': 48,
    'hdpi': 72,
    'xhdpi': 96,
    'xxhdpi': 144,
    'xxxhdpi': 192
  };
  for (final MapEntry(:key, :value) in sizes.entries) {
    await _writePng('android/app/src/main/res/mipmap-$key/ic_launcher.png',
        _resize(logo, value));
  }
}
