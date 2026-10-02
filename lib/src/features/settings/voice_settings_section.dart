import 'dart:async' show Timer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/voice_call/ringtone_player.dart';
import 'package:mosh/src/state/audio_device_picks_provider.dart';
import 'package:mosh/src/state/voice_call_orchestrator_provider.dart'
    show ringtonePlayerProvider;

import 'audio_device_picker.dart';
import 'settings_card.dart';

const Duration kTestRingtoneDuration = Duration(milliseconds: 1500);

class VoiceSettingsSection extends ConsumerStatefulWidget {
  const VoiceSettingsSection({super.key});

  @override
  ConsumerState<VoiceSettingsSection> createState() =>
      _VoiceSettingsSectionState();
}

class _VoiceSettingsSectionState extends ConsumerState<VoiceSettingsSection> {
  Timer? _stopTimer;
  RingtoneHandle? _ringtone;
  String? _error;

  @override
  void dispose() {
    _stopTest();
    super.dispose();
  }

  void _stopTest() {
    _stopTimer?.cancel();
    _stopTimer = null;
    _ringtone?.stop();
    _ringtone = null;
  }

  void _toggleTest() {
    if (_ringtone != null) {
      setState(_stopTest);
      return;
    }
    try {
      final handle = ref.read(ringtonePlayerProvider).start();
      setState(() {
        _error = null;
        _ringtone = handle;
      });
      _stopTimer = Timer(kTestRingtoneDuration, () => setState(_stopTest));
    } catch (_) {
      setState(
          () => _error = AppLocalizations.of(context)!.settingsSoundTestError);
    }
  }

  void _save({String? input, String? output}) {
    try {
      ref
          .read(audioDevicePicksProvider.notifier)
          .set(inputDeviceId: input, outputDeviceId: output);
      setState(() => _error = null);
    } catch (_) {
      setState(
          () => _error = AppLocalizations.of(context)!.settingsAudioSaveError);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final picks = ref.watch(audioDevicePicksProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _microphone(l, picks),
        const SizedBox(height: 16),
        _speakers(l, picks),
        const SizedBox(height: 24),
        _testButton(l),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Semantics(
              liveRegion: true,
              child:
                  Text(_error!, style: Theme.of(context).textTheme.bodySmall)),
        ],
        const SizedBox(height: 24),
        Text(l.settingsAudioAppliesAutomatically,
            style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  Widget _microphone(AppLocalizations l, AudioDevicePicks picks) {
    final inputs = ref.watch(inputDevicesProvider).whenData((devices) => [
          for (final device in devices) (id: device.id, label: device.label),
        ]);
    return SettingsCard(
      icon: Icons.mic_none_outlined,
      title: l.settingsInputDeviceLabel,
      hint: l.settingsInputDeviceHint,
      child: AudioDevicePicker(
        label: l.settingsInputDeviceLabel,
        devices: inputs,
        preferredId: picks.inputDeviceId,
        onChanged: (id) => _save(input: id, output: picks.outputDeviceId),
        onRefresh: () => ref.invalidate(inputDevicesProvider),
      ),
    );
  }

  Widget _speakers(AppLocalizations l, AudioDevicePicks picks) {
    final outputs = ref.watch(outputDevicesProvider).whenData((devices) => [
          for (final device in devices) (id: device.id, label: device.name),
        ]);
    return SettingsCard(
      icon: Icons.volume_up_outlined,
      title: l.settingsOutputDeviceLabel,
      hint: l.settingsOutputDeviceHint,
      child: AudioDevicePicker(
        label: l.settingsOutputDeviceLabel,
        devices: outputs,
        preferredId: picks.outputDeviceId,
        onChanged: (id) => _save(input: picks.inputDeviceId, output: id),
        onRefresh: () => ref.invalidate(outputDevicesProvider),
      ),
    );
  }

  Widget _testButton(AppLocalizations l) => FilledButton.icon(
        onPressed: _toggleTest,
        icon: Icon(
            _ringtone == null ? Icons.volume_up_outlined : Icons.stop_outlined,
            size: 20),
        label: Text(_ringtone == null
            ? l.settingsTestRingtone
            : l.settingsStopTestRingtone),
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(44),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      );
}
