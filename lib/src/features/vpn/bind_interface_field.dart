/// Existing persisted VPN-bypass choice. A running node picks up changes
/// only after restart; saved settings are never presented as live binding.
library;

import 'package:flutter/material.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/gateway/bridge_facade.dart' show BridgeFacade;
import 'package:mosh/src/rust/network_inventory.dart' show NetworkInterfaceInfo;

import 'bind_interface_controls.dart';
import 'bypass_adapter.dart';

class BindInterfaceField extends StatefulWidget {
  const BindInterfaceField({
    super.key,
    required this.bridge,
    required this.l,
    required this.onAccept,
    this.canRelaunch = true,
  });

  final BridgeFacade bridge;
  final AppLocalizations l;
  final Future<void> Function() onAccept;
  final bool canRelaunch;

  @override
  State<BindInterfaceField> createState() => _BindInterfaceFieldState();
}

class _BindInterfaceFieldState extends State<BindInterfaceField> {
  List<NetworkInterfaceInfo> _interfaces = const [];
  String? _current;
  String _picked = '';
  bool _loading = true;
  bool _busy = false;
  bool _needsRestart = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.bridge.listInterfaces(),
        widget.bridge.getBindInterface(),
      ]);
      if (!mounted) return;
      final list = results[0] as List<NetworkInterfaceInfo>;
      final bind = results[1] as String?;
      setState(() {
        _interfaces = list;
        _current = bind != null && bind.isNotEmpty ? bind : null;
        _picked = _current ?? defaultBypassAdapter(list);
      });
    } catch (_) {
      if (mounted) setState(() => _error = widget.l.bindAdapterReadError);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _apply() async {
    final value = _current != null ? null : _picked;
    var saved = false;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.bridge.setVpnBypassConsent(interfaceName: value);
      saved = true;
      if (mounted) {
        setState(() {
          _current = value;
          _picked = value ?? defaultBypassAdapter(_interfaces);
          _needsRestart = true;
        });
      }
      await widget.onAccept();
    } catch (_) {
      if (mounted) {
        setState(() => _error = saved
            ? widget.l.bindAdapterRestartError
            : widget.l.bindAdapterApplyError);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => BindInterfaceControls(
        l: widget.l,
        interfaces: _interfaces,
        current: _current,
        picked: _picked,
        loading: _loading,
        busy: _busy,
        error: _error,
        needsRestart: _needsRestart,
        canRelaunch: widget.canRelaunch,
        onPick: (value) => setState(() => _picked = value),
        onApply: _apply,
        onRefresh: _refresh,
      );
}
