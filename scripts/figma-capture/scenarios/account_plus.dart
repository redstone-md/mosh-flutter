// Mosh+ scenes: the Settings > Profile card in each membership and checkout
// state, and the Plus badge on a contact.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/app/distribution_channel.dart';
import 'package:mosh/src/app/distribution_channel_provider.dart';
import 'package:mosh/src/features/plus/plus_billing.dart';
import 'package:mosh/src/features/plus/plus_commands.dart';
import 'package:mosh/src/features/plus/plus_provider.dart';
import 'package:mosh/src/features/plus/plus_settings_card.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/rust/plus/checkout.dart';
import 'package:mosh/src/rust/plus/recovery_types.dart';
import 'package:mosh/src/rust/plus/types.dart';

import '../../../test/support/plus/fakes.dart';
import '../../../test/support/plus/mainnet_fakes.dart';
import 'account_shell.dart';
import 'harness.dart';

BigInt _inDays(int days) => BigInt.from(
    DateTime.now().add(Duration(days: days)).millisecondsSinceEpoch);

/// Native Mosh+ state as a fixed snapshot; [pending] holds the first read.
class _Native extends PlusCommands {
  _Native(this.current, {this.pending});
  final PlusSnapshot current;
  final Completer<PlusSnapshot>? pending;
  Future<PlusSnapshot> _read() => pending?.future ?? Future.value(current);
  @override
  Future<PlusSnapshot> configure(String key) => _read();
  @override
  Future<PlusSnapshot> configureMainnet(String key) => _read();
  @override
  Future<PlusSnapshot> snapshot() => _read();
}

class _FailingNative extends PlusCommands {
  @override
  Future<PlusSnapshot> configureMainnet(String key) =>
      Future.error(StateError('storage locked'));
}

/// Billing whose catalog is held or fails, for the catalog states.
class _Catalog extends MainnetTestBilling {
  _Catalog({this.hold = false, this.fail = false});
  final bool hold;
  final bool fail;
  @override
  Future<Map<String, dynamic>> catalog() {
    if (hold) return Completer<Map<String, dynamic>>().future;
    if (fail) return Future.error(StateError('offline'));
    return super.catalog();
  }
}

/// A synced, registered series: what a ready checkout needs.
PlusSnapshot _mainnet({
  bool active = false,
  bool visible = true,
  bool ready = true,
  List<PlusOrder> orders = const [],
  PlusCheckoutIntent? intent,
  PlusRecoverySession? recovery,
  BigInt? nextActiveFrom,
  BigInt? reservedUntil,
  List<PlusPeerBadge> badges = const [],
}) =>
    PlusSnapshot(
      active: active,
      visible: visible,
      expiresAtMs: active ? _inDays(23) : null,
      peerBadges: badges,
      series: mainnetSeries,
      seriesRegistered: true,
      checkoutReady: ready,
      orders: orders,
      checkoutIntent: intent,
      recovery: recovery,
      nextActiveFromMs: nextActiveFrom,
      reservedUntilMs: reservedUntil,
      unissuedOrderIds: [for (final order in orders) order.id],
    );

PlusOrder _order(PlusPaymentStatus status) => PlusOrder(
    id: 'order-7c21',
    network: 'solana-mainnet',
    product: 'mosh-plus-supporter-30d',
    mint: 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v',
    recipient: mainnetCatalog['recipient'] as String,
    amountAtomic: '5000000',
    reference: 'So11111111111111111111111111111111111111112',
    status: status,
    paymentUri: 'solana:11111111111111111111111111111111?amount=5'
        '&spl-token=EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v'
        '&reference=So11111111111111111111111111111111111111112',
    asset: 'USDC',
    tokenDecimals: 6,
    accessToken: 'private-order-token');

PlusRecoverySession _recovery({bool url = true, bool expired = false}) =>
    PlusRecoverySession(
        id: 'session',
        pollToken: 'private-poll-token',
        publicKeyB64: 'public-key',
        code: 'R4KD-92QX',
        expiresAtMs: _inDays(expired ? -1 : 1),
        url: url ? 'https://billing.example/recover/session' : null,
        orders: const [],
        completedOrders: 0);

List<Override> _plusOverrides(PlusCommands native,
        {PlusBilling? billing,
        PlusConfigOverride config = PlusConfigOverride.mainnet,
        DistributionChannel channel = DistributionChannel.github}) =>
    [
      plusConfigProvider.overrideWithValue(config.value),
      plusCommandsProvider.overrideWithValue(native),
      plusBillingProvider.overrideWithValue(billing ??
          (config == PlusConfigOverride.pilot
              ? TestBilling()
              : MainnetTestBilling())),
      plusPollIntervalProvider.overrideWithValue(null),
      distributionChannelProvider.overrideWithValue(channel),
    ];

enum PlusConfigOverride {
  mainnet,
  pilot,
  noServer;

  PlusConfig get value => switch (this) {
        mainnet => mainnetConfig,
        pilot => testPlusConfig,
        noServer => const PlusConfig(issuerKey: 'pin', mainnet: true),
      };
}

/// Settings > Profile scrolled to the Mosh+ card.
Future<void> _card(WidgetTester tester, Size size, List<Override> overrides,
    {bool settle = true}) async {
  await openSettingsSection(tester, size, 'Profile',
      overrides: overrides, settle: settle);
  await tester.ensureVisible(find.byType(PlusSettingsCard));
  settle ? await tester.pumpAndSettle() : await frames(tester, 3);
}

FigmaScene _scene(String id, String title, PlusSnapshot snapshot,
        {PlusBilling? billing,
        PlusConfigOverride config = PlusConfigOverride.mainnet,
        DistributionChannel channel = DistributionChannel.github,
        bool settle = true}) =>
    FigmaScene(
        id,
        title,
        (tester, size) => _card(
            tester,
            size,
            _plusOverrides(_Native(snapshot),
                billing: billing, config: config, channel: channel),
            settle: settle));

final List<FigmaScene> plusScenes = [
  FigmaScene('plus-loading', 'Plus / Card / Loading', (tester, size) async {
    await _card(
        tester, size, _plusOverrides(_Native(_mainnet(), pending: Completer())),
        settle: false);
  }),
  FigmaScene('plus-error', 'Plus / Card / Load error',
      (tester, size) => _card(tester, size, _plusOverrides(_FailingNative()))),
  _scene('plus-buy', 'Plus / Checkout / Buy (USDC)', _mainnet()),
  FigmaScene('plus-buy-details', 'Plus / Checkout / Payment details open',
      (tester, size) async {
    await _card(tester, size, _plusOverrides(_Native(_mainnet())));
    await tester.tap(find.text('CLXAI'));
    await tester.pumpAndSettle();
    final details = find.text('Payment details & terms');
    await tester.ensureVisible(details);
    await tester.tap(details);
    await tester.pumpAndSettle();
    await tester.ensureVisible(details);
    await tester.pumpAndSettle();
  }),
  _scene('plus-catalog-loading', 'Plus / Checkout / Prices loading', _mainnet(),
      billing: _Catalog(hold: true), settle: false),
  _scene('plus-catalog-error', 'Plus / Checkout / Prices failed', _mainnet(),
      billing: _Catalog(fail: true)),
  _scene('plus-sales-paused', 'Plus / Checkout / Sales paused', _mainnet(),
      billing: MainnetTestBilling()..enabled = false),
  _scene('plus-syncing', 'Plus / Checkout / Waiting for device sync',
      _mainnet(ready: false)),
  _scene(
      'plus-checkout-setup',
      'Plus / Checkout / Setup in progress',
      _mainnet(
          intent:
              const PlusCheckoutIntent(requestId: 'request', asset: 'USDC'))),
  _scene('plus-awaiting-payment', 'Plus / Payment / Awaiting payment',
      _mainnet(orders: [_order(PlusPaymentStatus.awaitingPayment)])),
  _scene('plus-issuing', 'Plus / Payment / Paid, issuing membership',
      _mainnet(orders: [_order(PlusPaymentStatus.paid)])),
  _scene('plus-active', 'Plus / Membership / Active', _mainnet(active: true)),
  _scene('plus-next-period', 'Plus / Membership / Next period booked',
      _mainnet(nextActiveFrom: _inDays(2), reservedUntil: _inDays(32))),
  _scene('plus-recovery-code', 'Plus / Recovery / Pairing code',
      _mainnet(recovery: _recovery(url: false))),
  _scene('plus-recovery-qr', 'Plus / Recovery / Waiting for wallet',
      _mainnet(recovery: _recovery())),
  _scene('plus-recovery-expired', 'Plus / Recovery / Expired',
      _mainnet(recovery: _recovery(expired: true))),
  _scene('plus-unavailable', 'Plus / Card / Checkout unavailable', _mainnet(),
      config: PlusConfigOverride.noServer),
  _scene('plus-store-inactive', 'Plus / Store build / Not active', _mainnet(),
      channel: DistributionChannel.play),
  _scene('plus-store-member', 'Plus / Store build / Synced membership',
      _mainnet(active: true),
      channel: DistributionChannel.play),
  _scene('plus-pilot-buy', 'Plus / Devnet pilot / Create payment', emptyPlus,
      config: PlusConfigOverride.pilot),
  FigmaScene('plus-badge', 'Plus / Badge / Contact with Mosh+',
      (tester, size) async {
    final badge = PlusPeerBadge(identity: 'dm:maya', expiresAtMs: _inDays(20));
    await pumpAccountApp(tester, size,
        location: AppRoutes.dmFor('maya'),
        overrides: _plusOverrides(_Native(_mainnet(badges: [badge]))));
  }),
];
