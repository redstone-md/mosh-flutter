import 'package:mosh/src/rust/plus/recovery_types.dart';
import 'package:mosh/src/rust/plus/types.dart';
import 'plus_mainnet_flow.dart';

class PlusRecoveryFlow {
  PlusRecoveryFlow(this.flow);
  final PlusMainnetFlow flow;
  String _after = '';

  Future<void> start() async {
    final snapshot = await flow.initialize(await flow.commands.snapshot());
    if (!flow.alive()) return;
    if (!snapshot.checkoutReady || snapshot.series == null) {
      throw StateError('Mosh+ is synchronizing');
    }
    final session = await flow.commands.prepareRecovery();
    if (!flow.alive()) return;
    final status = await flow.client.startRecovery(snapshot.series!, session);
    if (flow.alive()) {
      await flow.record(flow.commands.saveRecoveryStatus(status));
    }
  }

  Future<void> refresh(PlusSnapshot snapshot) async {
    var session = snapshot.recovery;
    if (session == null ||
        session.expiresAtMs.toInt() <= DateTime.now().millisecondsSinceEpoch) {
      return;
    }
    if (session.url == null) {
      if (snapshot.series == null) return;
      final status = await flow.client.startRecovery(snapshot.series!, session);
      if (!flow.alive()) return;
      session = (await flow.record(flow.commands.saveRecoveryStatus(status)))
          .recovery;
    }
    if (session == null || !flow.alive()) return;
    String? after;
    for (var page = 0; page < 16; page++) {
      final status = await flow.client.recoveryStatus(session, after: after);
      if (!flow.alive()) return;
      snapshot = await flow.record(flow.commands.saveRecoveryStatus(status));
      after = status['next'] as String?;
      if (after == null) break;
    }
    final pending = snapshot.recovery?.orders ?? const <PlusOrder>[];
    final tail =
        pending.where((order) => order.id.compareTo(_after) > 0).toList();
    Object? failure;
    for (final order in (tail.isEmpty ? pending : tail).take(4)) {
      if (!flow.alive()) return;
      _after = order.id;
      try {
        await issue(session, order);
      } catch (error) {
        failure ??= error;
      }
    }
    if (failure != null) throw failure;
  }

  Future<void> issue(PlusRecoverySession session, PlusOrder order) async {
    final request = await flow.commands.prepareRecoveryIssuance(order.id);
    if (!flow.alive()) return;
    final issued = await flow.client.recover(session, order.id, request);
    if (flow.alive()) {
      await flow.record(flow.commands
          .completeOrder(order.id, issued['blind_signature_b64'] as String));
    }
  }
}
