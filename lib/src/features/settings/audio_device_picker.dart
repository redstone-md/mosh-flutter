import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_select.dart';
import 'package:mosh/src/app/mosh_theme.dart';

typedef AudioDeviceOption = ({String id, String label});

/// A controlled hardware selector. Missing saved ids stay visible; a failed
/// save never leaves the field displaying an unpersisted choice.
class AudioDevicePicker extends StatelessWidget {
  const AudioDevicePicker({
    super.key,
    required this.label,
    required this.devices,
    required this.preferredId,
    required this.onChanged,
    required this.onRefresh,
  });

  final String label;
  final AsyncValue<List<AudioDeviceOption>> devices;
  final String? preferredId;
  final ValueChanged<String?> onChanged;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final options = devices.value ?? const [];
    final missing = preferredId != null &&
        !options.any((device) => device.id == preferredId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MoshSelect<String?>(
          label: label,
          value: preferredId,
          options: _items(l, options, missing),
          onChanged: devices.isLoading ? null : onChanged,
        ),
        if (devices.isLoading) _hint(context, l.settingsDevicesLoading),
        if (devices.hasError) _retry(context, l),
        if (missing && !devices.isLoading && !devices.hasError)
          _hint(context, l.settingsDeviceUnavailableHint),
      ],
    );
  }

  List<MoshSelectOption<String?>> _items(
          AppLocalizations l, List<AudioDeviceOption> options, bool missing) =>
      [
        MoshSelectOption(null, l.settingsDeviceDefault),
        if (missing)
          MoshSelectOption(
            preferredId,
            l.settingsDeviceUnavailable,
            enabled: false,
          ),
        for (final device in options) MoshSelectOption(device.id, device.label),
      ];

  Widget _hint(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(text, style: Theme.of(context).textTheme.bodySmall),
      );

  Widget _retry(BuildContext context, AppLocalizations l) => Semantics(
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _hint(context, l.settingsDevicesLoadError),
            TextButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(l.settingsRefreshDevices),
              style: TextButton.styleFrom(foregroundColor: MoshColors.moss),
            ),
          ],
        ),
      );
}
