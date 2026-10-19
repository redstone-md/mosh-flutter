import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/plus/plus_mainnet_flow.dart';
import 'package:mosh/src/rust/plus/types.dart';
import '../../support/plus/mainnet_fakes.dart';

void main() {
  test('a fresh visible checkout registers its series before enabling purchase',
      () async {
    final native = FreshCheckoutCommands();
    final billing = BudgetBilling();
    final updates = <PlusSnapshot>[];
    final flow = PlusMainnetFlow(
        commands: native,
        client: billing,
        catalog: () async => throw StateError('catalog not needed'),
        alive: () => true,
        update: updates.add);
    await flow.refresh(native.current, automatic: true);
    expect(billing.registrations, 1);
    expect(updates.last.checkoutReady, true);
    await flow.refresh(native.current, automatic: true);
    expect(billing.registrations, 1);
  });

  test('automatic billing checks require a visible checkout, back off and stop',
      () async {
    final native = MainnetTestCommands();
    await native.saveOrder(mainnetOrder);
    final billing = BudgetBilling();
    var now = DateTime.utc(2026, 10, 19);
    var visible = false;
    final flow = PlusMainnetFlow(
        commands: native,
        client: billing,
        catalog: () async => throw StateError('catalog not needed'),
        alive: () => true,
        update: (_) {},
        now: () => now,
        checkoutVisible: () => visible);
    Future<void> tick() => flow.refresh(native.current, automatic: true);
    await tick();
    expect(billing.checks, 0);
    visible = true;
    await tick();
    await tick();
    expect(billing.checks, 1);
    now = now.add(const Duration(seconds: 5));
    await tick();
    expect(billing.checks, 2);
    now = now.add(const Duration(minutes: 2));
    await tick();
    now = now.add(const Duration(seconds: 5));
    await tick();
    expect(billing.checks, 3);
    now = now.add(const Duration(seconds: 30));
    await tick();
    expect(billing.checks, 4);
    expect(billing.schedules, 1);
    now = now.add(const Duration(minutes: 20));
    await tick();
    expect(billing.checks, 4);
    // A user can still check a late payment after automatic polling stops.
    await flow.refresh(native.current);
    expect(billing.checks, 5);
    expect(billing.schedules, 2);
  });

  test('an idle subscriber refreshes native state without calling billing',
      () async {
    final native = MainnetTestCommands()..reservedUntil = BigInt.zero;
    final billing = BudgetBilling();
    final flow = PlusMainnetFlow(
        commands: native,
        client: billing,
        catalog: () async => throw StateError('catalog not needed'),
        alive: () => true,
        update: (_) {});
    await flow.refresh(native.current, automatic: true);
    expect(billing.checks, 0);
    expect(billing.schedules, 0);
  });

  for (final cachedTail in [null, BigInt.one]) {
    test(
        'synced issued purchases refresh a missing or outdated reserved tail ($cachedTail)',
        () async {
      final native = SyncedCheckoutCommands()..reservedUntil = cachedTail;
      final billing = BudgetBilling()..reservedUntil = native.expiry.toInt();
      var visible = false;
      final flow = PlusMainnetFlow(
          commands: native,
          client: billing,
          catalog: () async => throw StateError('catalog not needed'),
          alive: () => true,
          update: (_) {},
          checkoutVisible: () => visible);
      await flow.refresh(native.current, automatic: true);
      expect(billing.schedules, 0);
      visible = true;
      await flow.refresh(native.current, automatic: true);
      expect(native.current.reservedUntilMs, native.expiry);
      expect(billing.schedules, 1);
      await flow.refresh(native.current, automatic: true);
      expect(billing.schedules, 1);
      expect(billing.checks, 0);
    });
  }
}

class BudgetBilling extends MainnetTestBilling {
  int registrations = 0;
  int checks = 0;
  int schedules = 0;
  int reservedUntil = 0;
  @override
  Future<Map<String, dynamic>> registerSeries(PlusSeries series) async {
    registrations++;
    return {'id': series.id, 'access_token': series.accessToken};
  }

  @override
  Future<Map<String, dynamic>> refresh(PlusOrder order) async {
    checks++;
    return mainnetOrder;
  }

  @override
  Future<Map<String, dynamic>> schedule(PlusSeries series) async {
    schedules++;
    return {'id': series.id, 'reserved_until_ms': reservedUntil};
  }
}

class SyncedCheckoutCommands extends MainnetTestCommands {
  @override
  PlusSnapshot get current => PlusSnapshot(
      active: true,
      visible: true,
      peerBadges: const [],
      series: mainnetSeries,
      seriesRegistered: true,
      checkoutReady: true,
      reservedUntilMs: reservedUntil,
      orders: [
        PlusOrder(
            id: 'synced-issued',
            network: 'solana-mainnet',
            product: 'mosh-plus-supporter-30d',
            mint: mainnetOrder['mint'] as String,
            recipient: mainnetOrder['recipient'] as String,
            amountAtomic: mainnetOrder['amount_atomic'] as String,
            reference: mainnetOrder['reference'] as String,
            status: PlusPaymentStatus.issued,
            paymentUri: mainnetOrder['payment_uri'] as String,
            expiresAtMs: expiry),
      ]);
}

class FreshCheckoutCommands extends MainnetTestCommands {
  bool registered = false;
  @override
  PlusSnapshot get current => PlusSnapshot(
      active: false,
      visible: false,
      peerBadges: const [],
      canInitializeSeries: !registered,
      seriesRegistered: registered,
      checkoutReady: registered,
      series: registered ? mainnetSeries : null,
      reservedUntilMs: reservedUntil);
  @override
  Future<PlusSeries> prepareSeries() async => mainnetSeries;
  @override
  Future<PlusSnapshot> confirmSeries(String id) async {
    registered = true;
    return current;
  }
}
