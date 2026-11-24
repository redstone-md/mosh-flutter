import 'package:flutter/material.dart';

import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_switch.dart';

/// A [MoshSwitchRow] whose setting is read and saved on its own: a spinner
/// stands beside the switch while a change is being saved, and a failure
/// is said under the row.
class AsyncSwitchTile extends StatefulWidget {
  const AsyncSwitchTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.read,
    required this.write,
    this.enabled = true,
    this.secondary,
  });

  final String title;
  final String subtitle;
  final Future<bool> Function() read;
  final Future<void> Function(bool value) write;

  /// False greys the row out regardless of the stored value.
  final bool enabled;
  final Widget? secondary;

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

  Future<void> _set(bool value) async {
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
    final text = Theme.of(context).textTheme;
    return LayoutBuilder(builder: (context, constraints) {
      final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final separateSummary =
          widget.secondary == null && constraints.maxWidth < 360 * textScale;
      // What stands under the row lines up with the row's own words.
      const inset = EdgeInsets.symmetric(horizontal: MoshSpace.s3);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _tile(separateSummary),
          if (separateSummary)
            Padding(
              padding: inset,
              child: Text(widget.subtitle, style: text.bodySmall),
            ),
          if (_error != null)
            Padding(
              padding: inset,
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: text.bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
        ],
      );
    });
  }

  Widget _tile(bool separateSummary) => MoshSwitchRow(
        leading: widget.secondary,
        title: widget.title,
        subtitle: separateSummary ? null : widget.subtitle,
        value: _value ?? false,
        saving: _writing,
        onChanged: widget.enabled && _value != null && !_writing ? _set : null,
      );
}
