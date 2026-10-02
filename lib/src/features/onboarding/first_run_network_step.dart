import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/l10n/app_localizations.dart';

import 'first_run_network_form.dart';
import 'first_run_network_provider.dart';

class FirstRunNetworkStep extends ConsumerWidget {
  const FirstRunNetworkStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    return ref.watch(setupNetworkProvider).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => Column(children: [
            Text(l.bindAdapterReadError),
            OutlinedButton(
                onPressed: () => ref.invalidate(setupNetworkProvider),
                child: Text(l.deviceLinkRetry)),
          ]),
          data: (network) => FirstRunNetworkForm(network: network),
        );
  }
}
