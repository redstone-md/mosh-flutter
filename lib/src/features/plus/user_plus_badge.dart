import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'plus_provider.dart';

/// Every surface reads the same native-verified, unexpired evidence.
class UserPlusBadge extends ConsumerWidget {
  const UserPlusBadge(
      {super.key, this.identity, this.own = false, this.plated = false});

  /// Edge of the mark.
  static const size = MoshSpace.s4;

  final String? identity;
  final bool own;

  /// On an avatar the mark stands on a plate of the surface behind it.
  final bool plated;

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
    final l = AppLocalizations.of(context)!;
    final label = ref.watch(plusConfigProvider).mainnet
        ? l.plusProductionBadgeLabel
        : l.plusBadgeLabel;
    return Tooltip(
        message: label,
        child: Semantics(
            label: label,
            image: true,
            child: DecoratedBox(
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: plated ? MoshColors.of(context).surface : null),
                // The accent tone on an avatar; beside a name it takes the
                // colour of the icons around it.
                child: Icon(MoshIcons.plusBadge,
                    size: size,
                    color: plated ? MoshColors.of(context).primary : null))));
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
