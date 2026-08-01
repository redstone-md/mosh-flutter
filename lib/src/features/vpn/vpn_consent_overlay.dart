// VpnConsentOverlay -- mounts the [VpnConsentModal] once at the app-shell
// level so it can show above any route. React renders
// `<VpnConsentModal gateway={gateway} />` near the root of
// `private-dm-screen.tsx`; the modal itself decides whether to show (it
// fetches consent + detectVpn + interfaces on mount and renders a scrim
// only when it should ask). Here the overlay wraps the router child in a
// `Stack` and lays the modal on top, so the consent prompt appears above
// onboarding / sessions / dm / channel / group alike.
//
// `onAccept` (the relaunch) is a slice-3 native concern; for now it is a
// no-op so the modal is fully wired on the desktop build without a native
// restart hook -- once the relaunch lands, this is the single call site
// to swap it.

library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/vpn/vpn_consent_modal.dart';
import 'package:mosh/src/state/gateway_provider.dart';

/// Wraps [child] with a top-level [VpnConsentModal] overlay. Place via
/// `MaterialApp.router(builder: ...)` so the prompt sits above every route.
class VpnConsentOverlay extends ConsumerWidget {
  const VpnConsentOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    // The modal returns `SizedBox.shrink()` when it has nothing to ask, so
    // the Stack is effectively pass-through except while a prompt is up.
    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        child,
        if (l != null)
          VpnConsentModal(
            gateway: ref.watch(gatewayProvider),
            l: l,
            // Slice-3: swap for a native relaunch (e.g. a Tauri-equivalent
            // `process relaunch` via `dart:io` / window_manager).
            onAccept: () async {},
          ),
      ],
    );
  }
}
