import 'package:flutter/material.dart';

import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_spinner.dart';
import 'package:mosh/src/app/mosh_switch.dart';
import 'package:mosh/src/features/settings/settings_card_header.dart';
import 'package:mosh/src/features/shared/inline_error.dart';

/// The header of a Settings card whose switch is read and saved on its own:
/// a spinner stands beside the switch while a change is being saved, and a
/// failure is said under the header.
class AsyncSwitchTile extends StatefulWidget {
  const AsyncSwitchTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.read,
    required this.write,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Future<bool> Function() read;
  final Future<void> Function(bool value) write;

  /// False turns the switch off regardless of the stored value.
  final bool enabled;

  @override
  State<AsyncSwitchTile> createState() => _AsyncSwitchTileState();
}

class _AsyncSwitchTileState extends State<AsyncSwitchTile> {
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // One node for a screen reader: the switch under the card's words.
        MergeSemantics(
          child: SettingsCardHeader(
            icon: widget.icon,
            title: widget.title,
            subtitle: widget.subtitle,
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              if (_writing) ...[
                const MoshSpinner(),
                const SizedBox(width: MoshSpace.s3),
              ],
              MoshSwitch(
                  value: value ?? false,
                  onChanged: widget.enabled && value != null ? _set : null),
            ]),
          ),
        ),
        if (_error case final error?) ...[
          const SizedBox(height: MoshSpace.s2),
          InlineError(message: error),
        ],
      ],
    );
  }
}
