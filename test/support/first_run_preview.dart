import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _enabled = bool.fromEnvironment('SETUP_PREVIEW');

/// Loads the bundled Inter weights and Material icons so previews render
/// real glyphs instead of the test font.
Future<void> prepareSetupPreview(WidgetTester tester) async {
  if (!_enabled) return;
  await tester.runAsync(() async {
    final inter = FontLoader('Inter');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      inter.addFont(_read('assets/fonts/Inter-$weight.ttf'));
    }
    await inter.load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });
}

Future<ByteData> _read(String path) async =>
    ByteData.sublistView(await File(path).readAsBytes());

/// Capture the real Flutter tree only when the optional preview is requested.
Future<void> saveSetupPreview(WidgetTester tester, String name) async {
  if (!_enabled) return;
  for (final element in find.byType(Image).evaluate()) {
    await tester.runAsync(
        () => precacheImage((element.widget as Image).image, element));
  }
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('setup-preview')));
  await tester.runAsync(() async {
    final picture = await boundary.toImage();
    final png = await picture.toByteData(format: ui.ImageByteFormat.png);
    picture.dispose();
    await Directory('build').create();
    await File('build/$name.png').writeAsBytes(png!.buffer.asUint8List());
  });
}
