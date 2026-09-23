// The Voice & Video settings section: the input-device (mic) and
// output-device (speaker) pickers plus a test-ringtone button.
//
// The input dropdown enumerates through `record`'s `listInputDevices` (the
// same seam the capture path uses); the output dropdown through mosh-core's
// cpal `list_outputDevices`. Picks persist via the shared
// `audioDevicePicksProvider` (one Rust-side write for both), and the
// capture/playback/ringtone paths read them at start time, so a change takes
// effect on the next call or recording without a restart.
//
// The test button plays the real two-tone ringtone through the picked
// output (the same `voiceCallRingtoneStart` the call modals use) for ~1.5 s,
// so a user can confirm the speaker choice the way Discord's "Test Video"
// does for cameras.
library;

import 'dart:async' show Timer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/shared/field.dart' show Field;
import 'package:mosh/src/features/voice_call/cpal_ringtone.dart'
    show CpalRingtonePlayer;
import 'package:mosh/src/state/audio_device_picks_provider.dart'
    show audioDevicePicksProvider, inputDevicesProvider, outputDevicesProvider;

/// How long the test ringtone plays before it is stopped.
const Duration kTestRingtoneDuration = Duration(milliseconds: 1500);

class VoiceSettingsSection extends ConsumerStatefulWidget {
  const VoiceSettingsSection({super.key});

  @override
  ConsumerState<VoiceSettingsSection> createState() =>
      _VoiceSettingsSectionState();
}

class _VoiceSettingsSectionState extends ConsumerState<VoiceSettingsSection> {
  Timer? _ringtoneStopTimer;

  @override
  void dispose() {
    _ringtoneStopTimer?.cancel();
    super.dispose();
  }

  void _playTestRingtone() {
    _ringtoneStopTimer?.cancel();
    final handle = const CpalRingtonePlayer().start();
    _ringtoneStopTimer = Timer(kTestRingtoneDuration, handle.stop);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final picks = ref.watch(audioDevicePicksProvider);

    // The device lists are server state (hardware sets), read through the
    // two FutureProviders; loading renders a disabled dropdown, an error an
    // empty list with a hint — a broken enumerator must not blank the
    // section.
    final inputs = ref.watch(inputDevicesProvider).value ?? const [];
    final outputs = ref.watch(outputDevicesProvider).value ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Field(
          label: l.settingsInputDeviceLabel,
          hint: l.settingsInputDeviceHint,
          child: DropdownButtonFormField<String?>(
            initialValue: picks.inputDeviceId,
            isExpanded: true,
            items: <DropdownMenuItem<String?>>[
              DropdownMenuItem<String?>(
                value: null,
                child: Text(l.settingsDeviceDefault),
              ),
              for (final device in inputs)
                DropdownMenuItem<String?>(
                  value: device.id,
                  child: Text(
                    device.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (picked) => ref
                .read(audioDevicePicksProvider.notifier)
                .set(
                    inputDeviceId: picked,
                    outputDeviceId: picks.outputDeviceId),
          ),
        ),
        const SizedBox(height: 16),
        Field(
          label: l.settingsOutputDeviceLabel,
          hint: l.settingsOutputDeviceHint,
          child: DropdownButtonFormField<String?>(
            initialValue: picks.outputDeviceId,
            isExpanded: true,
            items: <DropdownMenuItem<String?>>[
              DropdownMenuItem<String?>(
                value: null,
                child: Text(l.settingsDeviceDefault),
              ),
              for (final device in outputs)
                DropdownMenuItem<String?>(
                  value: device.id,
                  child: Text(
                    device.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (picked) => ref
                .read(audioDevicePicksProvider.notifier)
                .set(
                    inputDeviceId: picks.inputDeviceId, outputDeviceId: picked),
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _playTestRingtone,
          icon: const Icon(Icons.volume_up_outlined, size: 18),
          label: Text(l.settingsTestRingtone),
        ),
      ],
    );
  }
}
