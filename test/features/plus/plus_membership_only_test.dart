import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/app/distribution_channel.dart';
import 'package:mosh/src/app/distribution_channel_provider.dart';
import 'package:mosh/src/features/plus/plus_commands.dart';
import 'package:mosh/src/features/plus/plus_provider.dart';
import 'package:mosh/src/features/plus/plus_settings_card.dart';
import 'package:mosh/src/features/plus/user_plus_badge.dart';
import 'package:mosh/src/rust/plus/types.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../support/plus/mainnet_fakes.dart';
import '../../support/pump.dart';

// The desktop poller runs without a lifecycle; on Android it waits for a
// resume, so polling would never reach billing there.
final desktop = TargetPlatformVariant.only(TargetPlatform.windows);

void main() {
  testWidgets(
      'a store that does not sell Mosh+ shows no checkout to a non-member',
      (tester) async {
    var billing = 0;
    await card(tester, SyncedCommands(active: false), () => billing++);

    expect(find.text('Mosh+ is not active.'), findsOneWidget);
    expect(find.text('USDC'), findsNothing);
    expect(find.byType(QrImageView), findsNothing);
    expect(find.text('Recover purchase'), findsNothing);
    expect(find.text('Payment details & terms'), findsNothing);
    // The snapshot invites a renewal series; polling must not register it.
    expect(billing, 0);
  }, variant: desktop);

  testWidgets(
      'a store that does not sell Mosh+ shows a membership synced from a linked device',
      (tester) async {
    var billing = 0;
    final native = SyncedCommands(active: true);
    await card(tester, native, () => billing++);

    expect(find.textContaining('Mosh+ valid until'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(native.visible, isFalse);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    expect(find.byType(FilledButton), findsNothing);
    expect(billing, 0);
  }, variant: desktop);

  testWidgets('a store that does not sell Mosh+ still shows peer badges',
      (tester) async {
    await pumpScreen(
        tester, const Scaffold(body: UserPlusBadge(identity: 'paid-peer')),
        overrides: overrides(SyncedCommands(active: false), () {}));
    expect(find.byIcon(Icons.workspace_premium), findsOneWidget);
  });
}

Future<void> card(
    WidgetTester tester, PlusCommands native, VoidCallback onBilling) async {
  await pumpScreen(tester,
      const Scaffold(body: SingleChildScrollView(child: PlusSettingsCard())),
      overrides: overrides(native, onBilling));
  // Several poll intervals pass while the card is open.
  await tester.pump(const Duration(seconds: 3));
}

List<Override> overrides(PlusCommands native, VoidCallback onBilling) => [
      distributionChannelProvider
          .overrideWithValue(DistributionChannel.rustore),
      plusConfigProvider.overrideWithValue(mainnetConfig),
      plusCommandsProvider.overrideWithValue(native),
      plusBillingProvider.overrideWith((ref) {
        onBilling();
        return MainnetTestBilling();
      }),
      plusPollIntervalProvider.overrideWithValue(const Duration(seconds: 1)),
    ];

/// Native state as a linked device's sync leaves it: a series this device may
/// register, a peer's badge, and a membership only when another device bought one.
class SyncedCommands extends PlusCommands {
  SyncedCommands({required this.active});
  final bool active;
  bool visible = true;

  BigInt get _monthAhead => BigInt.from(
      DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch);

  PlusSnapshot get current => PlusSnapshot(
      active: active,
      visible: visible,
      expiresAtMs: active ? _monthAhead : null,
      peerBadges: [
        PlusPeerBadge(identity: 'paid-peer', expiresAtMs: _monthAhead)
      ],
      canInitializeSeries: true);

  @override
  Future<PlusSnapshot> configureMainnet(String key) async => current;
  @override
  Future<PlusSnapshot> snapshot() async => current;
  @override
  Future<PlusSnapshot> visibility(bool visible) async {
    this.visible = visible;
    return current;
  }
}
