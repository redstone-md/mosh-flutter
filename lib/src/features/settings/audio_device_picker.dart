import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_shapes.dart';
import 'package:mosh/src/app/mosh_theme.dart';

typedef AudioDeviceOption = ({String id, String label});

/// A controlled hardware selector. Missing saved ids stay visible; a failed
/// save never leaves the field displaying an unpersisted choice.
class AudioDevicePicker extends StatefulWidget {
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
  State<AudioDevicePicker> createState() => _AudioDevicePickerState();
}

class _AudioDevicePickerState extends State<AudioDevicePicker> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final options = widget.devices.value ?? const [];
    final missing = widget.preferredId != null &&
        !options.any((device) => device.id == widget.preferredId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _dropdown(l, options, missing),
        if (widget.devices.isLoading) _hint(l.settingsDevicesLoading),
        if (widget.devices.hasError) _retry(l),
        if (missing && !widget.devices.isLoading && !widget.devices.hasError)
          _hint(l.settingsDeviceUnavailableHint),
      ],
    );
  }

  Widget _dropdown(
          AppLocalizations l, List<AudioDeviceOption> options, bool missing) =>
      Semantics(
        label: widget.label,
        child: Focus(
          onFocusChange: (focused) => setState(() => _focused = focused),
          child: InputDecorator(
            isFocused: _focused,
            decoration: InputDecoration(
              enabled: !widget.devices.isLoading,
              constraints: const BoxConstraints(minHeight: 44),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: widget.preferredId,
                isExpanded: true,
                isDense: true,
                borderRadius: MoshShapes.menu,
                hint: Text(l.settingsDeviceDefault,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                style: Theme.of(context).textTheme.bodyMedium,
                dropdownColor: Theme.of(context).popupMenuTheme.color,
                items: _items(l, options, missing),
                onChanged: widget.devices.isLoading ? null : widget.onChanged,
              ),
            ),
          ),
        ),
      );

  List<DropdownMenuItem<String>> _items(
          AppLocalizations l, List<AudioDeviceOption> options, bool missing) =>
      [
        DropdownMenuItem(
            value: null,
            child: Text(l.settingsDeviceDefault,
                maxLines: 1, overflow: TextOverflow.ellipsis)),
        if (missing)
          DropdownMenuItem(
            value: widget.preferredId,
            enabled: false,
            child: Text(l.settingsDeviceUnavailable,
                overflow: TextOverflow.ellipsis),
          ),
        for (final device in options)
          DropdownMenuItem(
            value: device.id,
            child: Text(device.label,
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
      ];

  Widget _hint(String text) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(text, style: Theme.of(context).textTheme.bodySmall),
      );

  Widget _retry(AppLocalizations l) => Semantics(
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _hint(l.settingsDevicesLoadError),
            TextButton.icon(
              onPressed: widget.onRefresh,
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(l.settingsRefreshDevices),
              style: TextButton.styleFrom(foregroundColor: MoshColors.moss),
            ),
          ],
        ),
      );
}
