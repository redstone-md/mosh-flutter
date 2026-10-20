import 'package:flutter/material.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/rust/plus/types.dart';

class PlusMembershipStatus extends StatelessWidget {
  const PlusMembershipStatus(
      {super.key,
      required this.snapshot,
      required this.busy,
      required this.onVisibility});
  final PlusSnapshot snapshot;
  final bool busy;
  final ValueChanged<bool> onVisibility;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(l.plusUntil(formatPlusDate(snapshot.expiresAtMs!))),
      SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: Text(l.plusVisibility),
          subtitle: Text(l.plusVisibilityHint),
          value: snapshot.visible,
          onChanged: busy ? null : onVisibility),
    ]);
  }
}

String formatPlusDate(BigInt milliseconds) =>
    DateTime.fromMillisecondsSinceEpoch(milliseconds.toInt(), isUtc: true)
        .toIso8601String()
        .substring(0, 16)
        .replaceFirst('T', ' ');
