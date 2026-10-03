import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/vpn/vpn_consent_overlay.dart';
import 'package:mosh/src/state/auto_poll_provider.dart';

import 'first_run_provider.dart';
import 'first_run_wizard.dart';

/// Keep conversation routes unmounted until local setup is durable. The router
/// retains a deep link received during setup and mounts it on completion.
class FirstRunGate extends ConsumerWidget {
  const FirstRunGate({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(firstRunEnabledProvider)) return _ready(ref);
    final profile = ref.watch(firstRunProfileProvider);
    return profile.when(
      loading: () =>
          const Material(child: Center(child: CircularProgressIndicator())),
      error: (_, __) => _error(context, ref),
      data: (profile) => profile.completed
          ? _ready(ref)
          : Navigator(
              pages: [
                MaterialPage<void>(child: FirstRunWizard(profile: profile))
              ],
              onDidRemovePage: (_) {},
            ),
    );
  }

  Widget _ready(WidgetRef ref) {
    ref.watch(autoPollProvider);
    return ref.watch(firstRunShownProvider)
        ? child
        : VpnConsentOverlay(child: child);
  }

  Widget _error(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    return Material(
        child: Center(
            child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(l.firstRunLoadError, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        OutlinedButton(
            onPressed: () => ref.invalidate(firstRunProfileProvider),
            child: Text(l.deviceLinkRetry)),
      ]),
    )));
  }
}
