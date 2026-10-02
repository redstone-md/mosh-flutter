import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/features/settings/audio_device_picker.dart';

void main() {
  testWidgets('the opened device menu clips its contents to rounded corners',
      (tester) async {
    String? selected;
    await tester.pumpWidget(MaterialApp(
      theme: buildMoshTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: AudioDevicePicker(
            label: 'Microphone',
            devices: const AsyncData([(id: 'usb', label: 'USB microphone')]),
            preferredId: null,
            onChanged: (value) => selected = value,
            onRefresh: () {},
          ),
        ),
      ),
    ));
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    final popupClip = tester.widget<ClipRRect>(find.ancestor(
        of: find.text('USB microphone'), matching: find.byType(ClipRRect)));
    expect(popupClip.clipBehavior, Clip.antiAlias);
    final corners = popupClip.borderRadius.resolve(TextDirection.ltr);
    expect(corners.topLeft.x, greaterThanOrEqualTo(8));
    expect(corners.bottomRight.x, greaterThanOrEqualTo(8));
    await tester.tap(find.text('USB microphone'));
    await tester.pumpAndSettle();
    expect(selected, 'usb');
  });
}
