import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _enabled = bool.fromEnvironment('SETUP_PREVIEW');

Future<void> prepareSetupPreview(WidgetTester tester) async {
  if (!_enabled) return;
  await tester.runAsync(() async {
    const fonts = {
      'Inter Tight': String.fromEnvironment('SETUP_FONT'),
      'MaterialIcons': String.fromEnvironment('SETUP_ICONS'),
    };
    for (final entry in fonts.entries) {
      if (entry.value.isEmpty) continue;
      final loader = FontLoader(entry.key)
        ..addFont(Future.value(
            ByteData.sublistView(await File(entry.value).readAsBytes())));
      await loader.load();
    }
  });
}

/// Capture the real Flutter tree only when the optional preview is requested.
Future<void> saveSetupPreview(WidgetTester tester, String name) async {
  if (!_enabled) return;
  final scene = find.byType(Image);
  await tester.runAsync(() =>
      precacheImage(tester.widget<Image>(scene).image, tester.element(scene)));
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
