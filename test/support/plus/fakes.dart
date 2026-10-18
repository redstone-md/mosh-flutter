import 'package:mosh/src/features/plus/plus_billing.dart';
import 'package:mosh/src/features/plus/plus_commands.dart';
import 'package:mosh/src/features/plus/plus_config.dart';
import 'package:mosh/src/rust/plus/types.dart';

const testPlusConfig = PlusConfig(
    issuerKey: 'pinned-test-key', serverUrl: 'http://127.0.0.1:8787');
final testOrder = <String, dynamic>{
  'id': 'test-order',
  'network': 'solana-devnet',
  'product': 'mosh-plus-30d',
  'mint': 'test-mint',
  'recipient': 'test-recipient',
  'amount_atomic': '1000000001',
  'reference': 'test-reference',
  'status': 'awaiting_payment',
  'payment_uri':
      'solana:test-recipient?amount=1.000000001&spl-token=test-mint&reference=test-reference',
  'access_token': 'private-order-token',
};
const emptyPlus = PlusSnapshot(active: false, visible: false, peerBadges: []);

class MemoryPlusCommands extends PlusCommands {
  PlusSnapshot current = emptyPlus;
  int preparations = 0;
  bool _prepared = false;
  @override
  Future<PlusSnapshot> configure(String key) async => current;
  @override
  Future<PlusSnapshot> snapshot() async => current;
  @override
  Future<PlusSnapshot> saveOrder(Map<String, dynamic> json) async {
    final status = switch (json['status']) {
      'paid' => PlusPaymentStatus.paid,
      'issued' => PlusPaymentStatus.issued,
      _ => PlusPaymentStatus.awaitingPayment,
    };
    final order = PlusOrder(
        id: json['id'] as String,
        network: json['network'] as String,
        product: json['product'] as String,
        mint: json['mint'] as String,
        recipient: json['recipient'] as String,
        amountAtomic: json['amount_atomic'] as String,
        reference: json['reference'] as String,
        status: status,
        paymentUri: json['payment_uri'] as String,
        accessToken:
            json['access_token'] as String? ?? current.order?.accessToken,
        expiresAtMs: json['expires_at_ms'] == null
            ? null
            : BigInt.from(json['expires_at_ms'] as int));
    return current = PlusSnapshot(
        active: false,
        visible: false,
        peerBadges: current.peerBadges,
        order: order,
        expiresAtMs: order.expiresAtMs);
  }

  @override
  Future<String> prepare() async {
    if (!_prepared) preparations++;
    _prepared = true;
    return 'durable-blinded-request';
  }

  @override
  Future<PlusSnapshot> complete(String signature) async {
    await saveOrder({
      ...testOrder,
      'status': 'issued',
      'expires_at_ms':
          DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch
    });
    return current = PlusSnapshot(
        active: true,
        visible: false,
        peerBadges: current.peerBadges,
        order: current.order,
        expiresAtMs: current.expiresAtMs);
  }

  @override
  Future<PlusSnapshot> visibility(bool visible) async => current = PlusSnapshot(
      active: current.active,
      visible: visible,
      peerBadges: current.peerBadges,
      order: current.order,
      expiresAtMs: current.expiresAtMs);
}

class TestBilling extends PlusBilling {
  TestBilling() : super(testPlusConfig);
  bool paid = false;
  bool failIssue = false;
  final requests = <String>[];
  @override
  Future<Map<String, dynamic>> catalog() async => {
        ...testOrder,
        'token_decimals': 9,
        'issuer_public_key_b64': testPlusConfig.issuerKey
      };
  @override
  Future<Map<String, dynamic>> create() async => {...testOrder};
  @override
  Future<Map<String, dynamic>> refresh(PlusOrder order) async => {
        ...testOrder,
        'status': paid ? 'paid' : 'awaiting_payment',
        if (paid)
          'expires_at_ms': DateTime.now()
              .add(const Duration(days: 30))
              .millisecondsSinceEpoch
      };
  @override
  Future<Map<String, dynamic>> issue(PlusOrder order, String blinded) async {
    requests.add(blinded);
    if (failIssue) throw StateError('offline');
    return {
      ...testOrder,
      'status': 'issued',
      'blind_signature_b64': 'signed-blinded-request'
    };
  }
}
