/// The [[Read receipt]] app-level toggle: one answer covering every DM,
/// persisted on the Rust side (read-receipts.json in the data dir).
///
/// Off by default and symmetric — a user who does not send receipts does
/// not see others' — so the row carries the contract in its subtitle and
/// needs no confirmation dialog. Mounted inside the onboarding menu's
/// Advanced disclosure, beside the bind-interface override.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/gateway/bridge_facade.dart';
import 'package:mosh/src/state/gateway_provider.dart' show bridgeFacadeProvider;

/// A SwitchListTile row bound to the bridge's `readReceiptsEnabled` /
/// `setReadReceiptsEnabled` mirrors (ADR 0025: 1:1 facade calls, not the
/// Gateway conversation seam).
///
/// The initial value loads asynchronously; the row stays disabled until
/// the read lands so a default-on flicker cannot fire a write before the
/// stored answer arrives. A write failure rolls the switch back and
/// surfaces the error inline.
class ReadReceiptsToggle extends ConsumerStatefulWidget {
  const ReadReceiptsToggle({super.key, this.bridge});

  /// The facade to read/write through. Defaults to the provider so tests
  /// can hand a ScriptableBridge.
  final BridgeFacade? bridge;

  @override
  ConsumerState<ReadReceiptsToggle> createState() => _ReadReceiptsToggleState();
}

class _ReadReceiptsToggleState extends ConsumerState<ReadReceiptsToggle> {
  bool? _enabled;
  String? _error;

  BridgeFacade get _bridge => widget.bridge ?? ref.read(bridgeFacadeProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final enabled = await _bridge.readReceiptsEnabled();
      if (!mounted) return;
      setState(() {
        _enabled = enabled;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  Future<void> _set(bool enabled) async {
    final previous = _enabled;
    setState(() {
      _enabled = enabled;
      _error = null;
    });
    try {
      await _bridge.setReadReceiptsEnabled(enabled: enabled);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _enabled = previous;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    // The Disclosure card paints its own background, so the tile gets a
    // transparent Material of its own — ListTile's ink splashes would
    // otherwise be invisible under it.
    return Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(l.settingsReadReceiptsTitle),
            subtitle: Text(
              l.settingsReadReceiptsSubtitle,
              style: const TextStyle(fontSize: 11.5, height: 1.5),
            ),
            value: _enabled ?? false,
            // Disabled until the stored answer lands: a default-on flicker
            // would fire a write the user never asked for.
            onChanged: _enabled == null ? null : _set,
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
        ],
      ),
    );
  }
}
