import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/settings/voice_settings_section.dart';
import 'package:mosh/src/features/settings/audio_device_picker.dart';
import 'package:mosh/src/state/audio_device_picks_provider.dart';
import 'package:record/record.dart' show InputDevice;

import '../../support/pump.dart';
import '../../support/settings.dart';

Finder get _pickers => find.descendant(
    of: find.byType(AudioDevicePicker), matching: find.byType(OutlinedButton));

void main() {
  testWidgets('unplugged saved devices leave the system default usable',
      (tester) async {
    final picks = MemoryAudioPicks(const AudioDevicePicks(
      inputDeviceId: 'missing-mic',
      outputDeviceId: 'missing-speaker',
    ));
    await pumpScreen(tester, const Scaffold(body: VoiceSettingsSection()),
        overrides: settingsAudioOverrides(picks: picks));
    expect(tester.takeException(), isNull);
    expect(find.text('Device unavailable'), findsWidgets);
    expect(picks.state.inputDeviceId, 'missing-mic');
    expect(picks.state.outputDeviceId, 'missing-speaker');
    await tester.tap(_pickers.last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('System default').last);
    await tester.pumpAndSettle();
    expect(picks.state.outputDeviceId, isNull);
    expect(picks.state.inputDeviceId, 'missing-mic');
  });

  testWidgets('leaving Sound stops the speaker test immediately',
      (tester) async {
    final ringtone = RecordingSettingsRingtone();
    await pumpScreen(tester, const Scaffold(body: VoiceSettingsSection()),
        overrides: settingsAudioOverrides(ringtone: ringtone));
    await tester.tap(find.text('Play test sound'));
    await tester.pump();
    expect(ringtone.starts, 1);
    await tester.pumpWidget(const SizedBox());
    expect(ringtone.stops, 1);
    await tester.pump(kTestRingtoneDuration);
    expect(ringtone.stops, 1);
  });

  testWidgets('each device change preserves the other choice', (tester) async {
    final picks = MemoryAudioPicks();
    await pumpScreen(tester, const Scaffold(body: VoiceSettingsSection()),
        overrides: settingsAudioOverrides(picks: picks));
    await tester.tap(_pickers.last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Desk speakers').last);
    await tester.pumpAndSettle();
    expect(picks.state.outputDeviceId, 'speaker');
    await tester.tap(_pickers.first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('USB microphone').last);
    await tester.pumpAndSettle();
    expect(picks.state.inputDeviceId, 'mic');
    expect(picks.state.outputDeviceId, 'speaker');
  });

  testWidgets('a failed save keeps the persisted selection on screen',
      (tester) async {
    final picks = MemoryAudioPicks()..failWrite = true;
    await pumpScreen(tester, const Scaffold(body: VoiceSettingsSection()),
        overrides: settingsAudioOverrides(picks: picks));
    await tester.tap(_pickers.last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Desk speakers').last);
    await tester.pumpAndSettle();
    expect(picks.state.outputDeviceId, isNull);
    expect(find.text('Could not save the device selection. Try again.'),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(AudioDevicePicker).last,
            matching: find.text('System default')),
        findsOneWidget);
    picks.failWrite = false;
    await tester.tap(_pickers.last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Desk speakers').last);
    await tester.pumpAndSettle();
    expect(picks.state.outputDeviceId, 'speaker');
    expect(find.text('Could not save the device selection. Try again.'),
        findsNothing);
  });

  testWidgets('speaker test can stop, finish, and start again', (tester) async {
    final ringtone = RecordingSettingsRingtone();
    await pumpScreen(tester, const Scaffold(body: VoiceSettingsSection()),
        overrides: settingsAudioOverrides(ringtone: ringtone));
    await tester.tap(find.text('Play test sound'));
    await tester.pump();
    expect(find.text('Stop test sound'), findsOneWidget);
    await tester.tap(find.text('Stop test sound'));
    await tester.pump();
    expect(ringtone.stops, 1);
    await tester.tap(find.text('Play test sound'));
    await tester.pump(kTestRingtoneDuration);
    expect(ringtone.starts, 2);
    expect(ringtone.stops, 2);
    expect(find.text('Play test sound'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(ringtone.stops, 2);
  });

  testWidgets('speaker errors are visible and the test can be retried',
      (tester) async {
    final ringtone = RecordingSettingsRingtone()..failStart = true;
    await pumpScreen(tester, const Scaffold(body: VoiceSettingsSection()),
        overrides: settingsAudioOverrides(ringtone: ringtone));
    await tester.tap(find.text('Play test sound'));
    await tester.pump();
    expect(
        find.text(
            'Could not play test sound. Check your speakers and try again.'),
        findsOneWidget);
    ringtone.failStart = false;
    await tester.tap(find.text('Play test sound'));
    await tester.pump();
    expect(find.text('Stop test sound'), findsOneWidget);
    expect(
        find.text(
            'Could not play test sound. Check your speakers and try again.'),
        findsNothing);
    await tester.pumpWidget(const SizedBox());
    expect(ringtone.stops, 1);
  });

  testWidgets('loading disables the microphone until enumeration completes',
      (tester) async {
    final inputs = Completer<List<InputDevice>>();
    await pumpScreen(tester, const Scaffold(body: VoiceSettingsSection()),
        overrides: [
          ...settingsAudioOverrides(inputs: () => inputs.future),
        ]);
    final picker = tester.widget<OutlinedButton>(_pickers.first);
    expect(picker.onPressed, isNull);
    expect(find.text('Loading devices…'), findsOneWidget);
    inputs.complete([const InputDevice(id: 'mic', label: 'USB microphone')]);
    await tester.pumpAndSettle();
    expect(tester.widget<OutlinedButton>(_pickers.first).onPressed, isNotNull);
    expect(find.text('Loading devices…'), findsNothing);
  });

  testWidgets('failed enumeration offers a working refresh', (tester) async {
    var reads = 0;
    await pumpScreen(tester, const Scaffold(body: VoiceSettingsSection()),
        overrides: [
          ...settingsAudioOverrides(inputs: () async {
            if (reads++ == 0) throw StateError('scripted hardware failure');
            return [const InputDevice(id: 'mic', label: 'USB microphone')];
          }),
        ]);
    expect(find.text('Refresh devices'), findsOneWidget);
    await tester.tap(find.text('Refresh devices'));
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(find.text('Refresh devices'), findsNothing);
    await tester.tap(_pickers.first);
    await tester.pumpAndSettle();
    expect(find.text('USB microphone'), findsOneWidget);
  });
}
