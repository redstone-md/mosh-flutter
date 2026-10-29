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
  await savePreviewPng(
      tester, find.byKey(const ValueKey('setup-preview')), 'build/$name.png');
}

/// Writes the repaint boundary at [boundary] to [path] as a PNG, after its
/// images have decoded. Preview scripts use it to export documentation and
/// store screenshots.
Future<void> savePreviewPng(WidgetTester tester, Finder boundary, String path,
    {double pixelRatio = 1}) async {
  for (final element in find.byType(Image).evaluate()) {
    await tester.runAsync(
        () => precacheImage((element.widget as Image).image, element));
  }
  await tester.pump();
  final render = tester.firstRenderObject<RenderRepaintBoundary>(boundary);
  await tester.runAsync(() async {
    final image = await render.toImage(pixelRatio: pixelRatio);
    try {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(png!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
