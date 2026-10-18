import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/state/camera_device_picks_provider.dart';

import 'audio_device_picker.dart';
import 'settings_card.dart';

class CameraSettingsCard extends ConsumerStatefulWidget {
  const CameraSettingsCard({super.key});

  @override
  ConsumerState<CameraSettingsCard> createState() => _CameraSettingsCardState();
}

class _CameraSettingsCardState extends ConsumerState<CameraSettingsCard> {
  bool _saveFailed = false;

  void _save(String? id) {
    try {
      ref.read(defaultCameraProvider.notifier).set(id);
      setState(() => _saveFailed = false);
    } catch (_) {
      setState(() => _saveFailed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final devices = ref.watch(cameraDevicesProvider).whenData((devices) => [
          for (final device in devices) (id: device.id, label: device.name),
        ]);
    return SettingsCard(
      icon: Icons.videocam_outlined,
      title: l.callCamera,
      hint: l.settingsCameraDeviceHint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AudioDevicePicker(
            label: l.callCamera,
            devices: devices,
            preferredId: ref.watch(defaultCameraProvider),
            onChanged: _save,
            onRefresh: () => ref.invalidate(cameraDevicesProvider),
          ),
          if (_saveFailed) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(l.settingsAudioSaveError,
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          ],
        ],
      ),
    );
  }
}
