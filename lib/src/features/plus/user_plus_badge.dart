import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'plus_provider.dart';

/// Every surface reads the same native-verified, unexpired evidence.
class UserPlusBadge extends ConsumerWidget {
  const UserPlusBadge({super.key, this.identity, this.own = false});
  final String? identity;
  final bool own;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if ((!own && identity == null) || !ref.watch(plusConfigProvider).enabled) {
      return const SizedBox.shrink();
    }
    final visible = ref.watch(plusProvider.select((value) {
      final snapshot = value.value?.snapshot;
      if (snapshot == null) return false;
      if (own) {
        return snapshot.active &&
            snapshot.visible &&
            (snapshot.expiresAtMs?.toInt() ?? 0) >
                DateTime.now().millisecondsSinceEpoch;
      }
      return snapshot.peerBadges.any((badge) =>
          badge.identity == identity &&
          badge.expiresAtMs.toInt() > DateTime.now().millisecondsSinceEpoch);
    }));
    if (!visible) return const SizedBox.shrink();
    final label = AppLocalizations.of(context)!.plusBadgeLabel;
    return Tooltip(
        message: label,
        child: Semantics(
            label: label,
            image: true,
            child: const Icon(Icons.workspace_premium, size: 15)));
  }
}

/// Mount after setup so verification and unfinished purchases stay live.
class PlusHost extends ConsumerWidget {
  const PlusHost({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(plusConfigProvider).enabled) ref.watch(plusProvider);
    return child;
  }
}
