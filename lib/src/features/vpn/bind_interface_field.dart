// BindInterfaceField -- 1-в-1 port of React `src/features/private-dm/vpn/
// BindInterfaceField.tsx`. The Advanced-section control that changes the
// VPN-bypass answer after the fact. Writes the same stored answer the
// startup question does (so the two cannot disagree) + relaunches: a
// node's bind is fixed when the node is built, so nothing already running
// would pick the change up otherwise.
//
// React structure (BindInterfaceField.tsx):
//   .bind-interface-field[.bind-interface-on] (border tinted green when on)
//     -> .bind-interface-head (row)
//        -> span.bind-interface-icon (IconShieldLock when on /
//           IconPlugConnected when off, 15px, moss tint)
//        -> strong "Network adapter" + p body (bound -> "Moss is bound to
//           ${current}." / unbound -> "Use a physical NIC when a VPN
//           blocks peer discovery.")
//     -> if no candidates: p.bind-interface-hint "No connected physical
//        NIC detected."
//     -> else .bind-interface-controls (grid: select + button)
//        -> select.bind-interface-select (adapterLabel per option,
//           value=picked, disabled when busy)
//        -> button (ghost "Release" when on / primary "Bind" when off;
//           "Restarting..." when busy)
//     -> if on: p.bind-interface-active (IconCheck + "Every conversation
//        uses ${current}.")
//     -> p.bind-interface-hint (the LAN-IP exposure warning)
//     -> p.bind-interface-error (if error)
//
// On mount React `Promise.all([listNetworkInterfaces, getBindInterface])`,
// defaulting `picked` to the current bind or `defaultBypassAdapter(list)`.
// apply(enabled ? null : picked) -> setVpnBypassConsent(value) +
// restartApp(). `restartApp` is an injectable callback (`onAccept`) so the
// field is parity-first + testable without a native relaunch (slice-3).

library;

import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/vpn/bypass_adapter.dart';
import 'package:mosh/src/gateway/gateway.dart' show Gateway;
import 'package:mosh/src/rust/network_inventory.dart' show NetworkInterfaceInfo;

/// The bind-interface field -- 1-в-1 with React's `BindInterfaceField`.
class BindInterfaceField extends StatefulWidget {
  const BindInterfaceField({
    super.key,
    required this.gateway,
    required this.l,
    required this.onAccept,
  });

  /// The gateway seam (listInterfaces/getBindInterface/setVpnBypassConsent).
  final Gateway gateway;

  /// Localizations (bindAdapter*).
  final AppLocalizations l;

  /// Invoked after `setVpnBypassConsent` succeeds, to relaunch (React
  /// `gateway.restartApp()`). The real native relaunch is a slice-3
  /// concern; tests pass a no-op.
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

  // React: `Promise.all([listNetworkInterfaces, getBindInterface])`; default
  // `picked` to the current bind or `defaultBypassAdapter(list)`.
  Future<void> _refresh() async {
    try {
      final results = await Future.wait([
        widget.gateway.listInterfaces(),
        widget.gateway.getBindInterface(),
      ]);
      final list = results[0] as List<NetworkInterfaceInfo>;
      final bind = results[1] as String?;
      if (!mounted) return;
      setState(() {
        _interfaces = list;
        _current = bind;
        _picked = bind != null && bind.isNotEmpty
            ? bind
            : defaultBypassAdapter(list);
        _error = null;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _error = err is Exception
            ? err.toString()
            : widget.l.bindAdapterReadError;
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
      await widget.gateway.setVpnBypassConsent(interfaceName: value);
      await widget.onAccept();
      // onAccept relaunches; if it returns (test), refresh the local state
      // so the field reflects the new bind without a real restart.
      await _refresh();
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = err is Exception
            ? err.toString()
            : widget.l.bindAdapterApplyError;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = widget.l;
    final candidates = bypassCandidates(_interfaces);
    final enabled = _current != null && _current!.isNotEmpty;
    final moss = const Color(0xFFB7D84A);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(
          // React .bind-interface-on: green-tinted border.
          color: enabled ? moss.withValues(alpha: 0.3) : theme.dividerColor,
        ),
        borderRadius: BorderRadius.circular(12),
        color: enabled ? moss.withValues(alpha: 0.08) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // .bind-interface-head: icon + strong title + p body.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HeadIcon(enabled: enabled),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.bindAdapterTitle,
                        style: theme.textTheme.labelSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      enabled
                          ? l.bindAdapterBoundBody(_current ?? '')
                          : l.bindAdapterUnboundBody,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(fontSize: 11, height: 1.35),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (candidates.isEmpty)
            Text(l.bindAdapterNoNic,
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontSize: 11))
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // .bind-interface-select (DropdownButton in Flutter).
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
                        onPressed:
                            (_busy || _picked.isEmpty) ? null : _apply,
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
                Icon(Icons.check, size: 13, color: moss),
                const SizedBox(width: 5),
                Text(l.bindAdapterActive(_current!),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(fontSize: 11, color: moss)),
              ],
            ),
          ],
          const SizedBox(height: 10),
          // .bind-interface-hint (LAN-IP exposure warning).
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

/// .bind-interface-icon: IconShieldLock when on, IconPlugConnected when off
/// (Material's Icons.shield / Icons.power closest to tabler's glyphs).
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
        color: const Color(0xFFB7D84A).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        enabled ? Icons.shield : Icons.power,
        size: 15,
        color: const Color(0xFFB7D84A),
      ),
    );
  }
}
