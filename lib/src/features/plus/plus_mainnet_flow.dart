import 'package:mosh/src/rust/plus/types.dart';
import 'plus_billing.dart';
import 'plus_catalog.dart';
import 'plus_commands.dart';
import 'plus_recovery_flow.dart';

/// HTTP coordinates purchases; native owns durable intent, proofs and device sync.
class PlusMainnetFlow {
  PlusMainnetFlow(
      {required this.commands,
      required this.client,
      required this.catalog,
      required this.alive,
      required this.update});
  final PlusCommands commands;
  final PlusBilling client;
  final Future<PlusCatalog> Function() catalog;
  final bool Function() alive;
  final void Function(PlusSnapshot) update;
  String _after = '';

  Future<PlusSnapshot> record(Future<PlusSnapshot> pending) async {
    final snapshot = await pending;
    if (alive()) update(snapshot);
    return snapshot;
  }

  Future<PlusSnapshot> initialize(PlusSnapshot snapshot) async {
    if (snapshot.seriesRegistered || !snapshot.canInitializeSeries) {
      return snapshot;
    }
    final series = await commands.prepareSeries();
    if (!alive()) return snapshot;
    final registered = await client.registerSeries(series);
    if (registered['id'] != series.id ||
        registered['access_token'] != series.accessToken) {
      throw const FormatException('Mosh+ renewal series changed');
    }
    if (!alive()) return snapshot;
    return record(commands.confirmSeries(series.id));
  }

  Future<void> purchase(String asset) async {
    final snapshot = await initialize(await commands.snapshot());
    if (!alive()) return;
    if (!snapshot.checkoutReady || snapshot.series == null) {
      throw StateError('Mosh+ is synchronizing');
    }
    final offer = await catalog();
    if (!alive()) return;
    final intent = await commands.prepareCheckout(asset);
    if (!alive()) return;
    final quote = await client.createMainnet(snapshot.series!, intent);
    offer.validateOrder(quote);
    if (quote['asset'] != intent.asset ||
        quote['request_id'] != intent.requestId ||
        quote['series_id'] != snapshot.series!.id) {
      throw const FormatException('Mosh+ checkout response changed');
    }
    if (alive()) await record(commands.saveOrder(quote));
  }

  Future<void> refresh(PlusSnapshot snapshot) async {
    snapshot = await initialize(snapshot);
    if (!alive() || !snapshot.checkoutReady) return;
    if (snapshot.checkoutIntent case final intent?) {
      await purchase(intent.asset);
      if (!alive()) return;
      snapshot = await commands.snapshot();
    }
    Object? failure;
    final recoveryIds =
        snapshot.recovery?.orders.map((o) => o.id).toSet() ?? {};
    final pending = snapshot.orders
        .where((order) =>
            snapshot.unissuedOrderIds.contains(order.id) &&
            order.accessToken != null &&
            !recoveryIds.contains(order.id))
        .toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    final tail =
        pending.where((order) => order.id.compareTo(_after) > 0).toList();
    for (final order in (tail.isEmpty ? pending : tail).take(4)) {
      if (!alive()) return;
      _after = order.id;
      try {
        await resumeOrder(order);
      } catch (error) {
        failure ??= error;
      }
    }
    if (!alive()) return;
    final current = await commands.snapshot();
    if (current.recovery != null) {
      try {
        await recovery.refresh(current);
      } catch (error) {
        failure ??= error;
      }
    }
    if (alive() &&
        current.series != null &&
        (current.reservedUntilMs == null ||
            pending.isNotEmpty ||
            current.recovery != null)) {
      try {
        await schedule(current.series!);
      } catch (error) {
        failure ??= error;
      }
    }
    if (failure != null) throw failure;
  }

  Future<void> resumeOrder(PlusOrder order) async {
    if (order.status == PlusPaymentStatus.awaitingPayment) {
      final json = await client.refresh(order);
      if (!alive()) return;
      final snapshot = await record(commands.saveOrder(json));
      order = snapshot.orders.firstWhere((o) => o.id == order.id);
    }
    if (!alive() ||
        order.status == PlusPaymentStatus.awaitingPayment ||
        (order.expiresAtMs?.toInt() ?? 0) <=
            DateTime.now().millisecondsSinceEpoch) {
      return;
    }
    final snapshot = await commands.snapshot();
    if (!alive() ||
        !snapshot.unissuedOrderIds.contains(order.id) ||
        !snapshot.issuableOrderIds.contains(order.id)) {
      return;
    }
    final blind = await commands.prepareOrder(order.id);
    if (!alive()) return;
    final issued = await client.issue(order, blind);
    if (alive()) {
      await record(commands.completeOrder(
          order.id, issued['blind_signature_b64'] as String));
    }
  }

  Future<void> schedule(PlusSeries series) async {
    final json = await client.schedule(series);
    if (json['id'] != series.id || json['reserved_until_ms'] is! int) {
      throw const FormatException('Invalid Mosh+ schedule');
    }
    if (alive()) {
      await record(commands.saveSchedule(
          series.id, BigInt.from(json['reserved_until_ms'] as int)));
    }
  }

  late final recovery = PlusRecoveryFlow(this);
}
