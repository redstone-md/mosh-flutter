// When the VoiceComposer asks for the microphone, driven through the real
// `record` plugin seam (VoiceRecorderProbe).
//
//  1. Mounting the composer must NOT probe the mic: the 0.9.1 macOS crash
//     died in TCC because the probe fired at chat open, before the plist
//     had a usage string. The mic button renders regardless.
//  2. A press with permission refused tells the localized denial through
//     onError and keeps the mic button (a later grant can retry).
import 'package:flutter_test/flutter_test.dart';

import '../../support/voice_recorder.dart';

void main() {
  testWidgets('mount probes nothing; the mic button renders', (tester) async {
    final recorder = VoiceRecorderProbe(tester);
    await pumpVoiceComposer(tester);

    expect(recorder.calls, isNot(contains('hasPermission')),
        reason: 'the 0.9.1 macOS TCC crash fired the probe at chat open');
    expect(find.byTooltip('Record'), findsOneWidget);
  });

  testWidgets(
      'a press with permission refused tells the denial and keeps '
      'the mic button', (tester) async {
    final recorder = VoiceRecorderProbe(tester)..allowed = false;
    final errors = <String>[];
    await pumpVoiceComposer(tester, errors: errors);

    await tester.tap(find.byTooltip('Record'));
    await tester.pumpAndSettle();

    expect(errors, ['mic denied']);
    expect(recorder.started, isEmpty,
        reason: 'no recording may start on a refusal');
    expect(find.byTooltip('Record'), findsOneWidget,
        reason: 'a later grant must be able to retry from the button');
  });
}
