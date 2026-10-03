import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/gateway/bridge_facade.dart' show BridgeFacade;
import 'package:mosh/src/rust/network_inventory.dart' show NetworkInterfaceInfo;

import 'bind_interface_controls.dart';
import 'bypass_adapter.dart';
import 'network_choice_provider.dart';

class BindInterfaceField extends ConsumerStatefulWidget {
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
  ConsumerState<BindInterfaceField> createState() => _BindInterfaceFieldState();
}

class _BindInterfaceFieldState extends ConsumerState<BindInterfaceField> {
  List<NetworkInterfaceInfo> _interfaces = const [];
  String _picked = '';
  bool _loading = true;
  bool _stateKnown = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
    });
    try {
      final saved = await ref
          .read(networkChoiceProvider(widget.bridge).notifier)
          .readSaved();
      if (!mounted) return;
      setState(() {
        _interfaces = saved.interfaces;
        _error = null;
        _stateKnown = true;
        _picked = saved.adapter ?? defaultBypassAdapter(saved.interfaces);
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _stateKnown = false;
          _error = widget.l.bindAdapterReadError;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setEnabled(bool enabled) async {
    final value = enabled ? _picked : null;
    setState(() => _error = null);
    final choice = ref.read(networkChoiceProvider(widget.bridge).notifier);
    try {
      await choice.apply(value, restart: widget.onAccept,
          complete: (restart) async {
        if (mounted) {
          setState(() => _picked = value ?? defaultBypassAdapter(_interfaces));
        }
        await restart();
      });
    } on NetworkChoiceError catch (error) {
      if (mounted) {
        setState(() => _error = error.kind == NetworkChoiceFailure.restart
            ? widget.l.bindAdapterRestartError
            : widget.l.bindAdapterApplyError);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final choice = ref.watch(networkChoiceProvider(widget.bridge));
    return BindInterfaceControls(
      l: widget.l,
      interfaces: _interfaces,
      current: choice.savedAdapter,
      picked: _picked,
      loading: _loading,
      stateKnown: _stateKnown,
      busy: choice.busy,
      error: _error,
      needsRestart: choice.needsRestart,
      canRelaunch: widget.canRelaunch,
      onPick: (value) => setState(() => _picked = value),
      onToggle: _setEnabled,
      onRefresh: _refresh,
    );
  }
}
