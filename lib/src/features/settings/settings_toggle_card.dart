import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_spinner.dart';
import 'package:mosh/src/app/mosh_switch.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'package:mosh/src/features/shared/inline_error.dart';

import 'settings_card.dart';
import 'settings_disclosure.dart';

/// The Switch kind of the Settings card: an opt-in in the card's header,
/// read and saved on its own, what explains it folded under a line that
/// opens, and a [notice] that stays in view. A spinner stands beside the
/// switch while a change is being saved, and a failure is said under the
/// header.
class SettingsToggleCard extends StatefulWidget {
  const SettingsToggleCard({
    required PageStorageKey<String> super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.read,
    required this.write,
    required this.detailsTitle,
    required this.details,
    this.enabled = true,
    this.notice,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Future<bool> Function() read;
  final Future<void> Function(bool value) write;
  final String detailsTitle;
  final String details;

  /// False turns the switch off regardless of the stored value.
  final bool enabled;
  final String? notice;

  @override
  State<SettingsToggleCard> createState() => _SettingsToggleCardState();
}

class _SettingsToggleCardState extends State<SettingsToggleCard> {
  bool? _value;
  String? _error;
  bool _writing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final value = await widget.read();
      if (!mounted) return;
      setState(() {
        _value = value;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  /// A change being saved takes the press and does nothing with it: turned
  /// off instead, the switch would drop the keyboard focus that started it.
  Future<void> _set(bool value) async {
    if (_writing) return;
    final previous = _value;
    setState(() {
      _value = value;
      _error = null;
      _writing = true;
    });
    try {
      await widget.write(value);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _value = previous;
        _error = error.toString();
      });
    } finally {
      if (mounted) setState(() => _writing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = _value;
    final text = Theme.of(context).textTheme.bodySmall;
    return SettingsSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsCardHeader(
            icon: widget.icon,
            title: widget.title,
            subtitle: widget.subtitle,
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              if (_writing) ...[
                const MoshSpinner(),
                const SizedBox(width: MoshSpace.s3),
              ],
              // The heading stays a heading; the switch carries its name.
              Semantics(
                label: widget.title,
                child: MoshSwitch(
                    value: widget.enabled && (value ?? false),
                    onChanged: widget.enabled && value != null ? _set : null),
              ),
            ]),
          ),
          if (_error case final error?) ...[
            const SizedBox(height: MoshSpace.s2),
            InlineError(message: error),
          ],
          if (widget.notice case final words?) ...[
            const SizedBox(height: MoshSpace.s3),
            Row(children: [
              Icon(MoshIcons.info,
                  size: MoshSpace.s5,
                  color: MoshColors.of(context).onSurfaceVariant),
              const SizedBox(width: MoshSpace.s3),
              Expanded(child: Text(words, style: text)),
            ]),
          ],
          const SizedBox(height: MoshSpace.s3),
          SettingsFold(
              key: widget.key! as PageStorageKey<String>,
              label: widget.detailsTitle,
              child: Text(widget.details, style: text)),
        ],
      ),
    );
  }
}
