// BindInterfaceField: the Advanced-section control that changes the
// VPN-bypass answer after the fact. Writes the same stored answer the
// startup question does (so the two cannot disagree) + relaunches: a
// node's bind is fixed when the node is built, so nothing already running
// would pick the change up otherwise.
//
// Structure: a bordered card (border tinted green when a bind is active)
// with a header row (shield/plug icon + title + body text), then either a
// "no connected physical NIC" hint or an adapter dropdown + Bind/Release
// button, an active-bind confirmation line, the LAN-IP exposure hint,
// and an optional error line.
//
// On mount fetch listNetworkInterfaces + getBindInterface, defaulting
// `picked` to the current bind or `defaultBypassAdapter(list)`.
// apply(enabled ? null : picked) -> setVpnBypassConsent(value) +
// restartApp(). `restartApp` is an injectable callback (`onAccept`) so
// the field remains testable. Production supplies the Windows-only
// desktop relauncher; unsupported platforms use a safe no-op.

library;

import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/vpn/bypass_adapter.dart';
import 'package:mosh/src/gateway/bridge_facade.dart' show BridgeFacade;
import 'package:mosh/src/rust/network_inventory.dart' show NetworkInterfaceInfo;

/// The bind-interface field.
class BindInterfaceField extends StatefulWidget {
  const BindInterfaceField({
    super.key,
    required this.bridge,
    required this.l,
    required this.onAccept,
  });

  /// The bridge facade (listInterfaces/getBindInterface/setVpnBypassConsent).
  final BridgeFacade bridge;

  /// Localizations (bindAdapter*).
  final AppLocalizations l;

  /// Invoked after `setVpnBypassConsent` succeeds, to relaunch. Production
  /// wires the Windows-only desktop relauncher; unsupported platforms use
  /// a safe no-op.
  final Future<void> Function() onAccept;

  @override
  State<BindInterfaceField> createState() => _BindInterfaceFieldState();
}

class _BindInterfaceFieldState extends State<BindInterfaceField> {
  List<NetworkInterfaceInfo> _interfaces = const [];
  String? _current;
  String _picked = '';
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  // Fetch the interface list + current bind; default `picked` to the
  // current bind or `defaultBypassAdapter(list)`.
  Future<void> _refresh() async {
    try {
      final results = await Future.wait([
        widget.bridge.listInterfaces(),
        widget.bridge.getBindInterface(),
      ]);
      final list = results[0] as List<NetworkInterfaceInfo>;
      final bind = results[1] as String?;
      if (!mounted) return;
      setState(() {
        _interfaces = list;
        _current = bind;
        _picked =
            bind != null && bind.isNotEmpty ? bind : defaultBypassAdapter(list);
        _error = null;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _error =
            err is Exception ? err.toString() : widget.l.bindAdapterReadError;
      });
    }
  }

  // apply(enabled ? null : picked) -> setVpnBypassConsent + restart.
  Future<void> _apply() async {
    final enabled = _current != null && _current!.isNotEmpty;
    final value = enabled ? null : (_picked.isEmpty ? null : _picked);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.bridge.setVpnBypassConsent(interfaceName: value);
      await widget.onAccept();
      // onAccept relaunches; if it returns (test), refresh the local state
      // so the field reflects the new bind without a real restart.
      await _refresh();
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error =
            err is Exception ? err.toString() : widget.l.bindAdapterApplyError;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = widget.l;
    final candidates = bypassCandidates(_interfaces);
    final enabled = _current != null && _current!.isNotEmpty;
    // Card: 12px padding, 1px hairline border, 12px radius, bg-1 fill;
    // a moss-tinted border + moss-glow fill when a bind is active.
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(
          color: enabled
              ? MoshColors.moss.withValues(alpha: 0.3)
              : MoshColors.line,
        ),
        borderRadius: BorderRadius.circular(12),
        color: enabled ? MoshColors.mossGlow : MoshColors.bg1,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: icon + strong title + p body.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HeadIcon(enabled: enabled),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title: 12.5px, fg-1; body: 11px/1.35, fg-3.
                    Text(
                      l.bindAdapterTitle,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: MoshColors.fg1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      enabled
                          ? l.bindAdapterBoundBody(_current ?? '')
                          : l.bindAdapterUnboundBody,
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1.35,
                        color: MoshColors.fg3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (candidates.isEmpty)
            Text(l.bindAdapterNoNic,
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 11))
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Adapter dropdown.
                Expanded(
                  child: DropdownButton<String>(
                    value: candidates.any((i) => i.name == _picked)
                        ? _picked
                        : candidates.first.name,
                    items: candidates
                        .map((iface) => DropdownMenuItem(
                              value: iface.name,
                              child: Text(adapterLabel(iface),
                                  overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: _busy
                        ? null
                        : (v) {
                            if (v != null) setState(() => _picked = v);
                          },
                    isExpanded: true,
                  ),
                ),
                const SizedBox(width: 8),
                // Bind / Release / Restarting...
                enabled
                    ? TextButton(
                        onPressed: _busy ? null : _apply,
                        child: Text(
                            _busy ? l.bindAdapterSaving : l.bindAdapterRelease),
                      )
                    : FilledButton(
                        onPressed: (_busy || _picked.isEmpty) ? null : _apply,
                        child: Text(
                            _busy ? l.bindAdapterSaving : l.bindAdapterBind),
                      ),
              ],
            ),
          if (enabled) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Active-bind line: check icon + text, moss, 11px.
                const Icon(Icons.check, size: 13, color: MoshColors.moss),
                const SizedBox(width: 5),
                Text(
                  l.bindAdapterActive(_current!),
                  style: const TextStyle(
                    fontSize: 11,
                    color: MoshColors.moss,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          // LAN-IP exposure hint.
          Text(l.bindAdapterHint,
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontSize: 11, height: 1.4)),
          if (_error != null) ...[
            const SizedBox(height: 6),
            Text(_error!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: const Color(0xFFE5484D), fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

/// Head icon: shield when on, power plug when off (15px, moss tint).
class _HeadIcon extends StatelessWidget {
  const _HeadIcon({required this.enabled});
  final bool enabled;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: MoshColors.moss.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        enabled ? Icons.shield : Icons.power,
        size: 15,
        color: MoshColors.moss,
      ),
    );
  }
}
