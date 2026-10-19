import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/plus/plus_catalog.dart';
import 'package:mosh/src/features/plus/plus_mainnet_flow.dart';
import 'package:mosh/src/rust/plus/checkout.dart';
import 'package:mosh/src/rust/plus/recovery_types.dart';
import 'package:mosh/src/rust/plus/types.dart';
import '../../support/plus/mainnet_fakes.dart';

void main() {
  test(
      'paid fulfillment resumes independently of a failed checkout and catalog outage',
      () async {
    final native = FulfillmentCommands()..pending = payment('awaiting_payment');
    final billing = FulfillmentBilling()..failCheckout = true;
    final flow = makeFlow(native, billing);
    await native.prepareCheckout('CLXAI');
    await native.bindCheckoutOffer(
        PlusCatalog.fromJson(mainnetCatalog, 'pin', mainnet: true)
            .orderTerms('CLXAI'));
    await expectLater(flow.refresh(native.current), throwsA(isA<StateError>()));
    expect(billing.refreshed, 1);
    expect(native.completed, true);
    expect(billing.blinds, ['durable-blind']);
    expect(native.current.active, true);
  });

  test(
      'issuance retries its durable request and a disposed flow cannot complete it',
      () async {
    final native = FulfillmentCommands()..pending = payment('paid');
    final billing = FulfillmentBilling()..failIssue = true;
    await expectLater(makeFlow(native, billing).refresh(native.current),
        throwsA(isA<StateError>()));
    expect(native.completed, false);
    billing.failIssue = false;
    await makeFlow(native, billing).refresh(native.current);
    expect(billing.blinds, ['durable-blind', 'durable-blind']);
    expect(native.completed, true);
    native.completed = false;
    var alive = true;
    billing.onIssue = () => alive = false;
    await makeFlow(native, billing, alive: () => alive).refresh(native.current);
    expect(native.completed, false);
  });

  test(
      'initial registration is checked and cannot enable an unacknowledged series',
      () async {
    final native = FulfillmentCommands()..registered = false;
    final billing = FulfillmentBilling();
    await makeFlow(native, billing).initialize(native.current);
    expect(native.registered, true);
    native.ready = false;
    await expectLater(makeFlow(native, billing).purchase('CLXAI'),
        throwsA(isA<StateError>()));
    native.registered = false;
    billing.wrongSeries = true;
    await expectLater(makeFlow(native, billing).initialize(native.current),
        throwsA(isA<FormatException>()));
    expect(native.registered, false);
  });

  test(
      'recovery resumes an unpublished pairing session, imports pages and completes its original interval',
      () async {
    final native = FulfillmentCommands();
    final billing = FulfillmentBilling();
    await native.prepareRecovery();
    await makeFlow(native, billing).refresh(native.current);
    expect(billing.recoveryPages, [null, 'page-two']);
    expect(native.recovered, ['renewal']);
    expect(native.completed, true);
    expect(billing.blinds, ['recovery-blind']);
    expect(native.current.active, true);
  });
}

PlusMainnetFlow makeFlow(FulfillmentCommands native, FulfillmentBilling billing,
        {bool Function()? alive}) =>
    PlusMainnetFlow(
        commands: native,
        client: billing,
        catalog: () async => throw StateError('catalog offline'),
        alive: alive ?? () => true,
        update: (_) {});

PlusOrder payment(String status) => PlusOrder(
    id: 'renewal',
    network: 'solana-mainnet',
    product: 'mosh-plus-supporter-30d',
    mint: mainnetOrder['mint'] as String,
    recipient: mainnetOrder['recipient'] as String,
    amountAtomic: mainnetOrder['amount_atomic'] as String,
    reference: mainnetOrder['reference'] as String,
    paymentUri: mainnetOrder['payment_uri'] as String,
    status: status == 'paid'
        ? PlusPaymentStatus.paid
        : PlusPaymentStatus.awaitingPayment,
    accessToken: 'private-order-token',
    asset: 'CLXAI',
    tokenDecimals: 9,
    expiresAtMs:
        BigInt.from(DateTime.now().millisecondsSinceEpoch + 2592000000));

class FulfillmentCommands extends MainnetTestCommands {
  bool registered = true;
  bool completed = false;
  final recovered = <String>[];
  @override
  PlusSnapshot get current => PlusSnapshot(
      active: completed,
      visible: false,
      peerBadges: const [],
      orders: pending == null ? const [] : [pending!],
      unissuedOrderIds: pending == null || completed ? const [] : [pending!.id],
      issuableOrderIds: pending == null || completed ? const [] : [pending!.id],
      checkoutReady: ready,
      seriesRegistered: registered,
      canInitializeSeries: !registered,
      series: mainnetSeries,
      checkoutIntent: intent,
      recovery: recovery);
  @override
  Future<PlusSeries> prepareSeries() async => mainnetSeries;
  @override
  Future<PlusSnapshot> confirmSeries(String id) async {
    registered = true;
    return current;
  }

  @override
  Future<PlusSnapshot> saveOrder(Map<String, dynamic> order) async {
    pending = payment(order['status'] as String);
    return current;
  }

  @override
  Future<String> prepareOrder(String id) async => 'durable-blind';
  @override
  Future<PlusSnapshot> completeOrder(String id, String signature) async {
    expect(signature, 'signed');
    completed = true;
    return current;
  }

  @override
  Future<PlusSnapshot> saveRecoveryStatus(Map<String, dynamic> status) async {
    final orders = (status['orders'] as List?) ?? const [];
    if (orders.isNotEmpty) pending = payment('paid');
    recovery = PlusRecoverySession(
        id: recovery!.id,
        code: recovery!.code,
        publicKeyB64: recovery!.publicKeyB64,
        pollToken: recovery!.pollToken,
        expiresAtMs: recovery!.expiresAtMs,
        url: status['url'] as String,
        orders: pending == null ? const [] : [pending!],
        completedOrders: 0);
    return current;
  }

  @override
  Future<PlusRecoveryIssuance> prepareRecoveryIssuance(String id) async {
    recovered.add(id);
    return const PlusRecoveryIssuance(
        blindedMessageB64: 'recovery-blind',
        destinationSignatureB64: 'destination-proof');
  }
}

class FulfillmentBilling extends MainnetTestBilling {
  bool failCheckout = false;
  bool failIssue = false;
  bool wrongSeries = false;
  int refreshed = 0;
  void Function()? onIssue;
  final blinds = <String>[];
  final recoveryPages = <String?>[];
  @override
  Future<Map<String, dynamic>> registerSeries(PlusSeries series) async => {
        'id': wrongSeries ? 'other' : series.id,
        'access_token': series.accessToken
      };
  @override
  Future<Map<String, dynamic>> createMainnet(
      PlusSeries series, PlusCheckoutIntent intent) async {
    if (failCheckout) throw StateError('checkout offline');
    return super.createMainnet(series, intent);
  }

  @override
  Future<Map<String, dynamic>> refresh(PlusOrder order) async {
    refreshed++;
    return {...mainnetOrder, 'status': 'paid'};
  }

  @override
  Future<Map<String, dynamic>> issue(PlusOrder order, String blinded) async {
    blinds.add(blinded);
    onIssue?.call();
    if (failIssue) throw StateError('issuance response lost');
    return {'blind_signature_b64': 'signed'};
  }

  @override
  Future<Map<String, dynamic>> recoveryStatus(PlusRecoverySession session,
      {String? after}) async {
    recoveryPages.add(after);
    return {
      ...await startRecovery(mainnetSeries, session),
      'orders': [mainnetOrder],
      'next': after == null ? 'page-two' : null
    };
  }

  @override
  Future<Map<String, dynamic>> recover(PlusRecoverySession session,
      String orderId, PlusRecoveryIssuance request) async {
    expect(request.destinationSignatureB64, 'destination-proof');
    return issue(payment('paid'), request.blindedMessageB64);
  }
}
