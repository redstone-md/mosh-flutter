import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/voice_call/cpal_ringtone.dart';
import 'package:mosh/src/features/voice_call/cpal_voice_playback.dart';
import 'package:mosh/src/features/voice_call/record_voice_capture.dart';
import 'package:mosh/src/state/auto_poll_provider.dart';
import 'package:mosh/src/state/production_provider_overrides.dart';
import 'package:mosh/src/state/voice_call_orchestrator_provider.dart';

void main() {
  test('production root binds real voice factories without opening devices',
      () {
    final container = ProviderContainer(overrides: productionOverrides);
    addTearDown(container.dispose);

    expect(
      container.read(voiceCaptureFactoryProvider),
      isA<RecordVoiceCaptureFactory>(),
    );
    expect(
      container.read(voicePlaybackFactoryProvider),
      isA<CpalVoicePlaybackFactory>(),
    );
    expect(
      container.read(ringtonePlayerProvider),
      isA<CpalRingtonePlayer>(),
    );
  });

  test('production root binds the live auto-poll cadence', () {
    final container = ProviderContainer(overrides: productionOverrides);
    addTearDown(container.dispose);

    expect(container.read(autoPollIntervalProvider), kAutoPollInterval);
  });

  test('the default (test) root does not poll', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(autoPollIntervalProvider), isNull);
  });
}
