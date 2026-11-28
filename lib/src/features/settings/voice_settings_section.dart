import 'dart:async' show Timer;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/features/voice_call/ringtone_player.dart';
import 'package:mosh/src/state/audio_device_picks_provider.dart';
import 'package:mosh/src/state/native_call_owner_provider.dart';
import 'package:mosh/src/state/voice_call_orchestrator_provider.dart'
    show ringtonePlayerProvider;

import 'audio_device_picker.dart';
import 'camera_settings_card.dart';
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
      final handle =
          ref.read(ringtonePlayerProvider).start(RingtoneKind.incoming);
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
        if (!kIsWeb &&
            (defaultTargetPlatform == TargetPlatform.macOS ||
                defaultTargetPlatform == TargetPlatform.windows ||
                defaultTargetPlatform == TargetPlatform.linux)) ...[
          const SizedBox(height: SettingsSurface.gap),
          const CameraSettingsCard(),
        ],
        const SizedBox(height: SettingsSurface.gap),
        _speakers(l, picks),
        const SizedBox(height: MoshSpace.s6),
        Align(
            alignment: AlignmentDirectional.centerStart, child: _testButton(l)),
        if (_error != null) ...[
          const SizedBox(height: MoshSpace.s3),
          Semantics(
              liveRegion: true,
              child:
                  Text(_error!, style: Theme.of(context).textTheme.bodySmall)),
        ],
      ],
    );
  }

  Widget _microphone(AppLocalizations l, AudioDevicePicks picks) {
    final pairedRoute = defaultTargetPlatform == TargetPlatform.android &&
        ref.watch(nativeCallOwnerProvider) != null;
    final inputs = ref.watch(inputDevicesProvider).whenData((devices) => [
          for (final device in devices) (id: device.id, label: device.label),
        ]);
    return SettingsCard(
      icon: MoshIcons.mic,
      title: l.settingsInputDeviceLabel,
      hint: pairedRoute
          ? l.settingsInputDeviceHintAndroid
          : l.settingsInputDeviceHint,
      child: AudioDevicePicker(
        label: l.settingsInputDevicePickerLabel,
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
      icon: MoshIcons.speaker,
      title: l.settingsOutputDeviceLabel,
      hint: l.settingsOutputDeviceHint,
      child: AudioDevicePicker(
        label: l.settingsOutputDevicePickerLabel,
        devices: outputs,
        preferredId: picks.outputDeviceId,
        onChanged: (id) => _save(input: picks.inputDeviceId, output: id),
        onRefresh: () => ref.invalidate(outputDevicesProvider),
      ),
    );
  }

  Widget _testButton(AppLocalizations l) => OutlinedButton.icon(
        onPressed: _toggleTest,
        icon: Icon(_ringtone == null ? MoshIcons.speaker : MoshIcons.stop),
        label: Text(_ringtone == null
            ? l.settingsTestRingtone
            : l.settingsStopTestRingtone),
      );
}
