import 'package:mosh/src/rust/plus/types.dart';

/// Bounds automatic HTTP work; manual checks remain available for late payments.
class PlusBillingPoll {
  PlusBillingPoll({DateTime Function()? now}) : _now = now ?? DateTime.now;
  final DateTime Function() _now;
  String? _work;
  DateTime? _started;
  DateTime? _next;

  void reset() {
    _work = null;
    _started = null;
    _next = null;
  }

  bool due(PlusSnapshot snapshot, {required bool visible}) {
    if (!visible) return false;
    final now = _now();
    final pending = [
      if (snapshot.canInitializeSeries && !snapshot.seriesRegistered)
        'bootstrap',
      if (snapshot.checkoutIntent case final intent?) intent.requestId,
      ...snapshot.unissuedOrderIds,
      if (snapshot.recovery case final session?
          when session.expiresAtMs.toInt() > now.millisecondsSinceEpoch)
        session.id,
    ]..sort();
    if (pending.isEmpty &&
        snapshot.checkoutReady &&
        scheduleDue(snapshot, automatic: true)) {
      pending.add('schedule');
    }
    if (pending.isEmpty) return false;
    final work = pending.join('|');
    if (_work != work) {
      _work = work;
      _started = now;
      _next = now;
    }
    final elapsed = now.difference(_started!);
    if (elapsed >= const Duration(minutes: 10) || now.isBefore(_next!)) {
      return false;
    }
    _next = now.add(elapsed < const Duration(minutes: 1)
        ? const Duration(seconds: 5)
        : const Duration(seconds: 30));
    return true;
  }

  bool scheduleDue(PlusSnapshot snapshot, {required bool automatic}) =>
      snapshot.series != null &&
      (!automatic ||
          snapshot.reservedUntilMs == null ||
          snapshot.orders.any((order) =>
              order.expiresAtMs != null &&
              order.expiresAtMs! > snapshot.reservedUntilMs!));
}
