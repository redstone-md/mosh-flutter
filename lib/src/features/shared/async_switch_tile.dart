import 'package:flutter/material.dart';

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
    // Settings cards paint their own background, so the tile gets a
    // transparent Material of its own — ListTile's ink splashes would
    // otherwise be invisible under it.
    return LayoutBuilder(builder: (context, constraints) {
      final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final separateSummary =
          widget.secondary == null && constraints.maxWidth < 360 * textScale;
      return Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _tile(context, separateSummary),
            if (separateSummary)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(widget.subtitle, style: text.bodySmall),
              ),
            if (_error != null)
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: text.bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      );
    });
  }

  Widget _tile(BuildContext context, bool separateSummary) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        secondary: widget.secondary,
        title:
            Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
        subtitle: separateSummary
            ? null
            : Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(widget.subtitle,
                    style: Theme.of(context).textTheme.bodySmall),
              ),
        value: _value ?? false,
        onChanged: widget.enabled && _value != null && !_writing ? _set : null,
      );
}
