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
  final pin = ref.watch(plusConfigProvider).issuerKey;
  final json = await ref.watch(plusBillingProvider).catalog();
  return PlusCatalog.fromJson(json, pin);
});
final plusProvider =
    AsyncNotifierProvider<PlusController, PlusState>(PlusController.new);

class PlusController extends AsyncNotifier<PlusState> {
  bool _running = false;

  @override
  Future<PlusState> build() async {
    _running = false;
    final startedUnder = ref;
    final config = startedUnder.watch(plusConfigProvider);
    final interval = startedUnder.watch(plusPollIntervalProvider);
    final snapshot = await startedUnder
        .watch(plusCommandsProvider)
        .configure(config.issuerKey);
    if (!startedUnder.mounted) return PlusState(snapshot: snapshot);
    if (interval != null) {
      final poller = ForegroundPoller(interval, refresh);
      startedUnder.onDispose(poller.dispose);
    }
    return PlusState(snapshot: snapshot);
  }

  Future<void> _run(Future<void> Function(Ref, PlusCommands) action,
      {bool busy = false}) async {
    if (_running || state.isLoading || state.value == null) return;
    _running = true;
    final startedUnder = ref;
    state =
        AsyncData(PlusState(snapshot: state.requireValue.snapshot, busy: busy));
    try {
      await action(startedUnder, startedUnder.read(plusCommandsProvider));
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
        _running = false;
      }
    }
  }

  void _update(Ref scope, PlusSnapshot snapshot) {
    if (scope.mounted) {
      state = AsyncData(
          PlusState(snapshot: snapshot, busy: state.value?.busy ?? false));
    }
  }

  Future<void> purchase() => _run((scope, commands) async {
        final catalog = await scope.read(plusCatalogProvider.future);
        if (!scope.mounted) return;
        final order = await scope.read(plusBillingProvider).create();
        if (!scope.mounted) return;
        catalog.validateOrder(order);
        _update(scope, await commands.saveOrder(order));
      }, busy: true);

  Future<void> visibility(bool visible) => _run((scope, commands) async {
        _update(scope, await commands.visibility(visible));
      }, busy: true);

  Future<void> refresh() => _run((scope, commands) async {
        final snapshot = await commands.snapshot();
        if (!scope.mounted) return;
        _update(scope, snapshot);
        if (!scope.read(plusConfigProvider).canPurchase ||
            snapshot.active ||
            snapshot.order == null) {
          return;
        }
        await _resume(
            scope, commands, scope.read(plusBillingProvider), snapshot.order!);
      }, busy: true);

  Future<void> _resume(Ref scope, PlusCommands commands, PlusBilling client,
      PlusOrder order) async {
    if (order.status == PlusPaymentStatus.awaitingPayment) {
      final json = await client.refresh(order);
      if (!scope.mounted) return;
      final next = await commands.saveOrder(json);
      if (!scope.mounted) return;
      _update(scope, next);
      order = next.order!;
    }
    if (order.status == PlusPaymentStatus.awaitingPayment ||
        (order.expiresAtMs?.toInt() ?? 0) <=
            DateTime.now().millisecondsSinceEpoch) {
      return;
    }
    final blinded = await commands.prepare();
    if (!scope.mounted) return;
    final issued = await client.issue(order, blinded);
    if (!scope.mounted) return;
    _update(scope,
        await commands.complete(issued['blind_signature_b64'] as String));
  }
}
