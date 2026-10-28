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

class _AndroidAppLockGateState extends ConsumerState<AndroidAppLockGate>
    with WidgetsBindingObserver {
  AndroidAppAccess? _access;
  bool _mountedContent = false;
  bool _validatingVisibility = false;
  int _visibilityRequest = 0;
  int _authenticationEntry = 0;
  bool _authenticating = false, _promptOnResume = false;
  bool get _covered =>
      _access?.covered == true || _validatingVisibility || !widget.interactive;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _access = ref.read(androidAppAccessProvider);
    _access?.addListener(_changed);
    _updateVisibility();
    if (_access != null) appLockRouteObserver.setLocked(_covered);
  }

  @override
  void didUpdateWidget(covariant AndroidAppLockGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.interactive != widget.interactive) {
      if (widget.interactive && !_authenticating) _authenticationEntry++;
      _updateVisibility();
      // Removing Navigator routes during its parent's build is unsafe.
      scheduleMicrotask(() {
        if (mounted) appLockRouteObserver.setLocked(_covered);
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _promptOnResume = !_authenticating;
    } else if (state == AppLifecycleState.resumed) {
      setState(() {
        if (_promptOnResume) _authenticationEntry++;
        _promptOnResume = false;
      });
    }
  }

  Future<void> _authenticate(String reason) async {
    _authenticating = true;
    try {
      await _access!.authenticate(reason);
    } finally {
      _authenticating = false;
    }
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
      appLockRouteObserver.setLocked(_covered);
    }));
  }

  void _changed() {
    appLockRouteObserver.setLocked(_covered);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _access?.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final access = _access;
    if (access == null) return widget.child;
    final covered = _covered;
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
            key: ValueKey(_authenticationEntry),
            automaticallyAuthenticate: !access.failed,
            authenticationReady: access.state?.deviceInteractive == true &&
                access.state?.callOnly != true &&
                (WidgetsBinding.instance.lifecycleState == null ||
                    WidgetsBinding.instance.lifecycleState ==
                        AppLifecycleState.resumed),
            retry: () =>
                _authenticate(AppLocalizations.of(context)!.appLockReason),
            swapTo: (_) {},
            nextApp: const SizedBox(),
            initialState: access.failed
                ? lock.LockState.failed
                : lock.LockState.canceled),
    ]);
  }
}
