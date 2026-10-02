import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/features/settings/audio_device_picker.dart';

import '../support/pump.dart';

Future<void> _pumpPicker(WidgetTester tester,
    {required TargetPlatform platform,
    required ValueChanged<String?> onChanged,
    double width = 1200,
    String? preferredId = 'usb',
    String headsetLabel = 'Headset microphone'}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await pumpScreen(
      tester,
      Theme(
        data: buildMoshTheme().copyWith(platform: platform),
        child: Scaffold(
          body: SingleChildScrollView(
              child: Padding(
            padding: const EdgeInsets.all(24),
            child: AudioDevicePicker(
              label: 'Microphone',
              devices: AsyncData([
                (id: 'usb', label: 'USB microphone'),
                (id: 'headset', label: headsetLabel),
              ]),
              preferredId: preferredId,
              onChanged: onChanged,
              onRefresh: () {},
            ),
          )),
        ),
      ));
}

void main() {
  testWidgets(
      'desktop choices open below the field and mark the current device',
      (tester) async {
    String? selected;
    await _pumpPicker(tester,
        platform: TargetPlatform.windows,
        onChanged: (value) => selected = value);
    final fieldBottom = tester.getBottomLeft(find.byType(AudioDevicePicker)).dy;
    await tester.tap(find.text('USB microphone'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Headset microphone')).dy,
        greaterThan(fieldBottom));
    expect(find.byIcon(Icons.check), findsOneWidget);
    await tester.tap(find.text('Headset microphone'));
    await tester.pumpAndSettle();
    expect(selected, 'headset');
    expect(find.text('Headset microphone'), findsNothing);
  });

  testWidgets('Android opens a titled sheet and dismissal keeps the choice',
      (tester) async {
    var changed = false;
    await _pumpPicker(tester,
        platform: TargetPlatform.android, onChanged: (_) => changed = true);
    await tester.tap(find.text('USB microphone'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('Microphone'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(changed, isFalse);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('USB microphone'), findsOneWidget);
  });

  testWidgets(
      'system default is a real nullable choice, distinct from dismissal',
      (tester) async {
    String? selected = 'unchanged';
    await _pumpPicker(tester,
        platform: TargetPlatform.android,
        onChanged: (value) => selected = value);
    await tester.tap(find.text('USB microphone'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('System default'));
    await tester.pumpAndSettle();
    expect(selected, isNull);
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('Escape closes desktop choices and returns focus to the field',
      (tester) async {
    var changed = false;
    String? selected = 'unchanged';
    await _pumpPicker(tester, platform: TargetPlatform.windows,
        onChanged: (value) {
      changed = true;
      selected = value;
    });
    await tester.tap(find.text('USB microphone'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Headset microphone'), findsNothing);
    expect(changed, isFalse);
    expect(
        tester
            .widget<OutlinedButton>(find.byType(OutlinedButton))
            .focusNode!
            .hasFocus,
        isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Headset microphone'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(changed, isTrue);
    expect(selected, isNull);
    expect(find.text('Headset microphone'), findsNothing);
  });

  testWidgets('narrow desktop uses a sheet with readable long device names',
      (tester) async {
    const longName =
        'Headset microphone with a long manufacturer name and USB audio device';
    String? selected;
    await _pumpPicker(tester,
        platform: TargetPlatform.windows,
        width: 320,
        headsetLabel: longName,
        onChanged: (value) => selected = value);
    await tester.tap(find.text('USB microphone'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text(longName));
    await tester.pumpAndSettle();
    expect(selected, 'headset');
  });

  testWidgets('an unavailable saved device stays disabled in the choices',
      (tester) async {
    var changed = false;
    await _pumpPicker(tester,
        platform: TargetPlatform.windows,
        preferredId: 'missing',
        onChanged: (_) => changed = true);
    await tester.tap(find.text('Device unavailable'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Device unavailable').last);
    await tester.pumpAndSettle();
    expect(changed, isFalse);
    expect(find.text('Headset microphone'), findsOneWidget);
    await tester.tapAt(const Offset(1100, 500));
    await tester.pumpAndSettle();
    expect(changed, isFalse);
    expect(find.text('Headset microphone'), findsNothing);
  });
}
