import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/src/platform/foreground_poller.dart';
import 'package:mosh/src/rust/plus/types.dart';
import 'plus_billing.dart';
import 'plus_catalog.dart';
import 'plus_commands.dart';
import 'plus_config.dart';
import 'plus_state.dart';

export 'plus_config.dart';

final plusConfigProvider = Provider((ref) => const PlusConfig(
    issuerKey: String.fromEnvironment('MOSH_PLUS_ISSUER_KEY'),
    serverUrl: String.fromEnvironment('MOSH_PLUS_SERVER_URL')));
final plusCommandsProvider = Provider((ref) => PlusCommands());
final plusPollIntervalProvider =
    Provider<Duration?>((ref) => const Duration(seconds: 5));
final plusBillingProvider = Provider((ref) {
  final client = PlusBilling(ref.watch(plusConfigProvider));
  ref.onDispose(client.close);
  return client;
});
final plusCatalogProvider = FutureProvider((ref) async {
  final json = await ref.watch(plusBillingProvider).catalog();
  return PlusCatalog.fromJson(json, ref.read(plusConfigProvider).issuerKey);
});
final plusProvider =
    AsyncNotifierProvider<PlusController, PlusState>(PlusController.new);

class PlusController extends AsyncNotifier<PlusState> {
  bool _running = false;

  @override
  Future<PlusState> build() async {
    final config = ref.watch(plusConfigProvider);
    final snapshot =
        await ref.watch(plusCommandsProvider).configure(config.issuerKey);
    if (!ref.mounted) return PlusState(snapshot: snapshot);
    final interval = ref.watch(plusPollIntervalProvider);
    if (interval != null) {
      final poller = ForegroundPoller(interval, refresh);
      ref.onDispose(poller.dispose);
    }
    return PlusState(snapshot: snapshot);
  }

  Future<void> _run(Future<void> Function(PlusCommands) action,
      {bool busy = false}) async {
    if (_running || state.isLoading || state.value == null) return;
    _running = true;
    final startedUnder = ref;
    state =
        AsyncData(PlusState(snapshot: state.requireValue.snapshot, busy: busy));
    try {
      await action(startedUnder.read(plusCommandsProvider));
    } catch (error) {
      if (startedUnder.mounted) {
        state = AsyncData(
            PlusState(snapshot: state.requireValue.snapshot, error: error));
      }
    } finally {
      if (startedUnder.mounted) {
        final current = state.requireValue;
        state = AsyncData(
            PlusState(snapshot: current.snapshot, error: current.error));
      }
      _running = false;
    }
  }

  void _update(PlusSnapshot snapshot) {
    if (ref.mounted) {
      state = AsyncData(
          PlusState(snapshot: snapshot, busy: state.value?.busy ?? false));
    }
  }

  Future<void> purchase() => _run((commands) async {
        final catalog = await ref.read(plusCatalogProvider.future);
        if (!ref.mounted) return;
        final order = await ref.read(plusBillingProvider).create();
        catalog.validateOrder(order);
        _update(await commands.saveOrder(order));
      }, busy: true);

  Future<void> visibility(bool visible) =>
      _run((commands) async => _update(await commands.visibility(visible)),
          busy: true);

  Future<void> refresh() => _run((commands) async {
        final snapshot = await commands.snapshot();
        _update(snapshot);
        if (!ref.mounted ||
            !ref.read(plusConfigProvider).canPurchase ||
            snapshot.active) {
          return;
        }
        var order = snapshot.order;
        if (order == null) return;
        final client = ref.read(plusBillingProvider);
        if (order.status == PlusPaymentStatus.awaitingPayment) {
          final next = await commands.saveOrder(await client.refresh(order));
          _update(next);
          order = next.order!;
        }
        if (!ref.mounted ||
            order.status == PlusPaymentStatus.awaitingPayment ||
            (order.expiresAtMs?.toInt() ?? 0) <=
                DateTime.now().millisecondsSinceEpoch) {
          return;
        }
        final blinded = await commands.prepare();
        final issued = await client.issue(order, blinded);
        _update(
            await commands.complete(issued['blind_signature_b64'] as String));
      }, busy: true);
}
