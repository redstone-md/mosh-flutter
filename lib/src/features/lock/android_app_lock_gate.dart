import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'android_app_access.dart';
import 'app_lock_route_observer.dart';
import 'mosh_lock_screen.dart' hide LockState;
import 'mosh_lock_screen.dart' as lock;

/// Protects chat routes without disposing their drafts or the enclosing call owner.
class AndroidAppLockGate extends ConsumerStatefulWidget {
  const AndroidAppLockGate(
      {super.key, required this.child, this.interactive = true});
  final Widget child;
  final bool interactive;

  @override
  ConsumerState<AndroidAppLockGate> createState() => _AndroidAppLockGateState();
}

class _AndroidAppLockGateState extends ConsumerState<AndroidAppLockGate> {
  AndroidAppAccess? _access;
  bool _mountedContent = false;
  bool _validatingVisibility = false;
  int _visibilityRequest = 0;

  @override
  void initState() {
    super.initState();
    _access = ref.read(androidAppAccessProvider);
    _access?.addListener(_changed);
    _updateVisibility();
    if (_access != null) appLockRouteObserver.setLocked(_access!.covered);
  }

  @override
  void didUpdateWidget(covariant AndroidAppLockGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.interactive != widget.interactive) _updateVisibility();
  }

  void _updateVisibility() {
    final access = _access;
    if (access == null) return;
    final request = ++_visibilityRequest;
    _validatingVisibility = widget.interactive;
    if (!_validatingVisibility) {
      access.setChatVisible(widget.interactive);
      return;
    }
    // Returning from call-only UI is another resume boundary. Never paint an
    // old grace snapshot while its expiry check is still in flight.
    unawaited(access.refresh().whenComplete(() {
      if (!mounted || request != _visibilityRequest) return;
      access.setChatVisible(widget.interactive);
      setState(() => _validatingVisibility = false);
    }));
  }

  void _changed() {
    appLockRouteObserver.setLocked(_access!.covered);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _access?.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final access = _access;
    if (access == null) return widget.child;
    final covered =
        access.covered || _validatingVisibility || !widget.interactive;
    _mountedContent |= !covered;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) access.protectedFrameReady();
    });
    return Stack(fit: StackFit.expand, children: [
      if (_mountedContent)
        Offstage(
            offstage: covered,
            child: TickerMode(
                enabled: !covered,
                child: FocusScope(
                    canRequestFocus: !covered, child: widget.child))),
      if (!widget.interactive) const Material(),
      if (widget.interactive && _validatingVisibility)
        const Material(child: Center(child: CircularProgressIndicator())),
      if (widget.interactive && covered && !_validatingVisibility)
        MoshLockScreen(
            retry: () => access
                .authenticate(AppLocalizations.of(context)!.appLockReason),
            swapTo: (_) {},
            nextApp: const SizedBox(),
            initialState: access.failed
                ? lock.LockState.failed
                : lock.LockState.canceled),
    ]);
  }
}
