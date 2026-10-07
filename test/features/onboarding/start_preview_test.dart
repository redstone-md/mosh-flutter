// Scratch preview: renders the start menu for review.
// Runs only with --dart-define=START_PREVIEW=<dir>.
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
import 'package:mosh/src/routing/mosh_shell.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/persistence_warning_provider.dart';

import '../../support/scriptable_bridge.dart';
import '../../support/scriptable_gateway.dart';

const _dir = String.fromEnvironment('START_PREVIEW');
const _boundary = ValueKey('start-preview');

void main() {
  testWidgets('start menu preview', (tester) async {
    if (_dir.isEmpty) return;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform, (call) async => null);
    await tester.runAsync(() async {
      final inter = FontLoader('Inter');
      for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
        inter.addFont(_read('assets/fonts/Inter-$w.ttf'));
      }
      await inter.load();
      await (FontLoader('monospace')
            ..addFont(
                _read('/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf')))
          .load();
      await (FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
          .load();
    });
    for (final (name, size) in [
      ('wide', const Size(1300, 900)),
      ('mid', const Size(860, 1100)),
      ('phone', const Size(390, 1500)),
    ]) {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      await tester.pumpWidget(ProviderScope(
        key: ValueKey(name),
        overrides: [
          gatewayProvider.overrideWithValue(ScriptableGateway()),
          bridgeFacadeProvider.overrideWithValue(ScriptableBridge()),
          persistenceWarningProvider.overrideWith((ref) async => null),
        ],
        child: MaterialApp(
          theme: moshThemeData,
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          debugShowCheckedModeBanner: false,
          home: const RepaintBoundary(key: _boundary, child: ChatPaneWelcome()),
        ),
      ));
      await _precache(tester);
      await tester.pumpAndSettle();
      await _capture(tester, '$name-menu');
    }
    tester.view.physicalSize = const Size(1300, 900);
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('Начать приватный чат')) +
        const Offset(40, 30));
    await tester.pumpAndSettle();
    await _capture(tester, 'wide-hover');
    Future<void> open(String title) async {
      await tester.tap(find.text(title).first);
      await tester.pumpAndSettle();
    }

    Future<void> back() async {
      await tester.tap(find.text('Назад').hitTestable());
      await tester.pumpAndSettle();
    }

    await tester.tap(find.text('Начать приватный чат').first);
    for (var t = 0; t < 5; t++) {
      await tester.pump(const Duration(milliseconds: 50));
      await _capture(tester, 'slide-$t');
    }
    await tester.pumpAndSettle();
    await _capture(tester, 'step-chat');
    await tester.tap(find.text('Создать ссылку-приглашение'));
    await tester.pumpAndSettle();
    await _capture(tester, 'step-chat-done');
    await back();
    await open('Создать группу');
    await _capture(tester, 'step-group');
    await tester.enterText(find.byType(TextField).hitTestable(), 'Команда');
    await tester.pump();
    await tester.tap(find.text('Создать группу').hitTestable().last);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await _capture(tester, 'step-group-done');
    await back();
    await open('Присоединиться по ссылке');
    await _capture(tester, 'step-join');
    await tester.enterText(find.byType(TextField).hitTestable(),
        'mosh://group?mesh=mesh-1&group=grp-1234&name=Design#fp=0123456789abcdef0123456789abcdef');
    await tester.pumpAndSettle();
    await _capture(tester, 'step-join-group');
    await back();
    await open('Войти в публичный канал');
    await _capture(tester, 'step-channel');
    await mouse.removePointer();
    tester.view.reset();
  });
}

Future<void> _precache(WidgetTester tester) async {
  final context = tester.element(find.byType(ChatPaneWelcome));
  await tester.runAsync(() async {
    for (final name in ['hero', 'chat', 'group', 'join', 'channel']) {
      await precacheImage(AssetImage('assets/start/$name.png'), context);
    }
  });
}

Future<ByteData> _read(String path) async =>
    ByteData.sublistView(await File(path).readAsBytes());

Future<void> _capture(WidgetTester tester, String name) async {
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_boundary));
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('$_dir/$name.png').writeAsBytes(png!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
