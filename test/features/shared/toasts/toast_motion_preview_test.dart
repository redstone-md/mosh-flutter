// Scratch preview: renders the toast motion frame by frame for review.
// Runs only with --dart-define=TOAST_PREVIEW=<dir>.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/features/shared/toasts/toast_host.dart';
import 'package:mosh/src/features/shared/toasts/toaster.dart';

const _dir = String.fromEnvironment('TOAST_PREVIEW');
const _boundary = ValueKey('toast-preview');

void main() {
  testWidgets('captured frames release their native images', (tester) async {
    final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('mosh-toast-capture-')))!;
    addTearDown(() => directory.delete(recursive: true));
    await tester.pumpWidget(const RepaintBoundary(
      key: _boundary,
      child:
          SizedBox(width: 32, height: 32, child: ColoredBox(color: Colors.red)),
    ));
    final images = <ui.Image>[];
    final onCreate = ui.Image.onCreate;
    ui.Image.onCreate = (image) {
      images.add(image);
      onCreate?.call(image);
    };
    addTearDown(() {
      ui.Image.onCreate = onCreate;
      for (final image in images) {
        if (!image.debugDisposed) image.dispose();
      }
    });
    for (var frame = 0; frame < 3; frame++) {
      await _capture(tester, frame, directory: directory.path);
    }
    expect(images, hasLength(3));
    expect(images.every((image) => image.debugDisposed), isTrue);
  });

  testWidgets('toast motion preview', (tester) async {
    if (_dir.isEmpty) return;
    await tester.runAsync(() async {
      final inter = FontLoader('Inter');
      for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
        inter.addFont(_read('assets/fonts/Inter-$w.ttf'));
      }
      await inter.load();
      await (FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
          .load();
    });
    tester.view
      ..physicalSize = const Size(1280, 720)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final toaster = Toaster();
    await tester.pumpWidget(ProviderScope(
      overrides: [toasterProvider.overrideWithValue(toaster)],
      child: MaterialApp(
        theme: moshThemeData,
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        debugShowCheckedModeBanner: false,
        home: RepaintBoundary(
            key: _boundary, child: ToastHost(child: _fakeShell())),
      ),
    ));
    var frame = 0;
    Future<void> film(int ms) async {
      for (var t = 0; t < ms; t += 20) {
        await tester.pump(const Duration(milliseconds: 20));
        await _capture(tester, frame++);
      }
    }

    await film(300);
    toaster.show('Скопировано', kind: ToastKind.success);
    await film(900);
    toaster.show('Не удалось удалить сообщения', kind: ToastKind.error);
    await film(900);
    toaster.show('Вложение больше 50 МБ — выберите файл поменьше');
    await film(1200);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(640, 700));
    await mouse.moveTo(const Offset(640, 80));
    await film(1300);
    await mouse.moveTo(const Offset(640, 700));
    await film(1000);
    toaster.show('Скопировано', kind: ToastKind.success);
    await film(900);
    final drag = await tester.startGesture(const Offset(560, 80));
    for (var i = 0; i < 6; i++) {
      await drag.moveBy(const Offset(0, -10));
      await tester.pump(const Duration(milliseconds: 20));
      await _capture(tester, frame++);
    }
    await drag.up();
    await film(900);
    await film(5000);
    await mouse.removePointer();
  });
}

Future<ByteData> _read(String path) async =>
    ByteData.sublistView(await File(path).readAsBytes());

Future<void> _capture(WidgetTester tester, int frame,
    {String directory = _dir}) async {
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_boundary));
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('$directory/f${frame.toString().padLeft(4, '0')}.png')
          .writeAsBytes(png!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

/// A titlebar, a chat list and a chat, enough to judge placement.
Widget _fakeShell() => Builder(builder: (context) {
      final text = Theme.of(context).textTheme;
      Widget bubble(String s, {bool mine = false}) => Align(
            alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: mine ? const Color(0xFF273D2D) : const Color(0xFF1D2024),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(s, style: text.bodyMedium),
            ),
          );
      return ColoredBox(
        color: const Color(0xFF0B0C0D),
        child: Column(children: [
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            alignment: Alignment.centerLeft,
            decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0x1AFFFFFF)))),
            child: Text('MOSH   OpenMLS поверх Moss', style: text.titleSmall),
          ),
          Expanded(
            child: Row(children: [
              Container(
                width: 348,
                color: const Color(0xFF111315),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Начать разговор', style: text.titleMedium),
                    const SizedBox(height: 16),
                    Text('test', style: text.bodyLarge),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(children: [
                    Align(
                        alignment: Alignment.centerLeft,
                        child: Text('test', style: text.titleMedium)),
                    const Spacer(),
                    bubble('сами всё проверим', mine: true),
                    bubble('mosh://group?mesh=groupmesh-312847ac4d134a83'),
                    const SizedBox(height: 12),
                    Container(
                      height: 52,
                      decoration: BoxDecoration(
                        color: const Color(0xFF16181B),
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ]),
                ),
              ),
            ]),
          ),
        ]),
      );
    });
