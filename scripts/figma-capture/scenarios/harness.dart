// Shared harness for Figma scene capture. One file per area calls
// [figmaScenes]; each scene renders at desktop and phone size and is
// written to build/figma-capture/<area>/<device>/<NN>-<id>/.
//
// Run through the capture script, which also publishes to Figma:
//   node scripts/figma-capture/capture.mjs [area ...]
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/state/locale_preference_store.dart';

import '../../../test/support/first_run_preview.dart';
import '../../../test/support/locale.dart';
import '../recorder/scene_export.dart';

/// Form factors every scene is captured at.
enum FigmaDevice {
  desktop(Size(1280, 800)),
  mobile(Size(390, 844));

  const FigmaDevice(this.size);
  final Size size;
}

/// One screen state. [pump] mounts it at [size] (logical px, DPR 1) and
/// drives it into the state; the harness exports the frame afterwards.
class FigmaScene {
  const FigmaScene(this.id, this.title, this.pump,
      {this.devices = FigmaDevice.values, this.note});
  final String id;
  final String title;
  final Future<void> Function(WidgetTester tester, Size size) pump;
  final List<FigmaDevice> devices;
  final String? note;
}

/// Keeps MoshApp in English for every capture.
final List<Override> figmaLocale = [
  localePreferenceStoreProvider
      .overrideWithValue(MemoryLocalePreferenceStore(const Locale('en'))),
];

/// Sets the test surface to [size] at DPR 1 (pumpShellApp does this itself).
void figmaSurface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void figmaScenes(String area, List<FigmaScene> scenes) {
  const recorder = MethodChannel('com.llfbandit.record/messages');
  TestDefaultBinaryMessenger messenger() =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(
      () => messenger().setMockMethodCallHandler(recorder, (_) async => null));
  tearDown(() => messenger().setMockMethodCallHandler(recorder, null));

  // moshThemeData is built once per isolate with the platform of its first
  // use, so each run captures one form factor: --dart-define=FIGMA_DEVICE=desktop|mobile.
  const only = String.fromEnvironment('FIGMA_DEVICE');
  for (final (index, scene) in scenes.indexed) {
    for (final device in scene.devices) {
      if (only.isNotEmpty && device.name != only) continue;
      testWidgets('$area ${scene.id} ${device.name}', (tester) async {
        await prepareSetupPreview(tester);
        await _loadMonospace(tester);
        figmaSurface(tester, device.size);
        // flutter_test defaults to Android; desktop scenes render as Windows.
        final ownsPlatform = device == FigmaDevice.desktop &&
            debugDefaultTargetPlatformOverride == null;
        if (ownsPlatform) {
          debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        }
        try {
          await _capture(tester, area, index, scene, device);
        } finally {
          if (ownsPlatform) debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  }
}

Future<void> _capture(WidgetTester tester, String area, int index,
    FigmaScene scene, FigmaDevice device) async {
  await scene.pump(tester, device.size);
  final out = 'build/figma-capture/$area/${device.name}/'
      '${index.toString().padLeft(2, '0')}-${scene.id}';
  if (Directory(out).existsSync()) Directory(out).deleteSync(recursive: true);
  await exportScene(tester, '$area.${scene.id}.${device.name}', scene.title,
      note: scene.note, outDir: out);
}

/// 'monospace' has no font in tests; DejaVu Sans Mono stands in for it.
Future<void> _loadMonospace(WidgetTester tester) => tester.runAsync(() async {
      final file = File('/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf');
      if (!file.existsSync()) return;
      final bytes = await file.readAsBytes();
      await (FontLoader('monospace')
            ..addFont(Future.value(ByteData.sublistView(bytes))))
          .load();
    });
