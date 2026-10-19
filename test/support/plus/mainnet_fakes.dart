import 'dart:convert';
import 'package:mosh/src/features/plus/plus_billing.dart';
import 'package:mosh/src/features/plus/plus_commands.dart';
import 'package:mosh/src/features/plus/plus_config.dart';
import 'package:mosh/src/rust/plus/checkout.dart';
import 'package:mosh/src/rust/plus/recovery_types.dart';
import 'package:mosh/src/rust/plus/types.dart';

const mainnetConfig = PlusConfig(
    issuerKey: 'pin', serverUrl: 'https://billing.example', mainnet: true);
const mainnetSeries =
    PlusSeries(id: 'series', accessToken: 'private-series-token');
final mainnetCatalog = <String, dynamic>{
  'version': 2,
  'network': 'solana-mainnet',
  'product': 'mosh-plus-supporter-30d',
  'recipient': '11111111111111111111111111111111',
  'issuer_key_id': 'a' * 64,
  'issuer_public_key_b64': 'pin',
  'purchases_enabled': true,
  'terms_url': 'https://mosh.example/terms',
  'support_url': 'https://mosh.example/support',
  'assets': [
    {
      'id': 'USDC',
      'mint': 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v',
      'decimals': 6,
      'amount_atomic': '5000000'
    },
    {
      'id': 'CLXAI',
      'mint': 'ECZV4aRyQKz2zr3ZFB9qeb4EzJbzuMCQZ2gpiBQfoHrK',
      'decimals': 9,
      'amount_atomic': '2575000000000'
    },
  ],
};
final mainnetOrder = <String, dynamic>{
  'id': 'renewal',
  'network': 'solana-mainnet',
  'product': 'mosh-plus-supporter-30d',
  'asset': 'CLXAI',
  'mint': 'ECZV4aRyQKz2zr3ZFB9qeb4EzJbzuMCQZ2gpiBQfoHrK',
  'token_decimals': 9,
  'issuer_key_id': 'a' * 64,
  'series_id': 'series',
  'request_id': 'request',
  'recipient': '11111111111111111111111111111111',
  'amount_atomic': '2575000000000',
  'reference': 'So11111111111111111111111111111111111111112',
  'status': 'awaiting_payment',
  'access_token': 'private-order-token',
  'payment_uri':
      'solana:11111111111111111111111111111111?amount=2575&spl-token=ECZV4aRyQKz2zr3ZFB9qeb4EzJbzuMCQZ2gpiBQfoHrK&reference=So11111111111111111111111111111111111111112',
};

class MainnetTestCommands extends PlusCommands {
  String? selectedAsset;
  PlusCheckoutIntent? intent;
  PlusOrder? pending;
  PlusRecoverySession? recovery;
  bool ready = true;
  final expiry = BigInt.from(
      DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch);
  PlusSnapshot get current => PlusSnapshot(
      active: true,
      visible: true,
      expiresAtMs: expiry,
      peerBadges: const [],
      series: mainnetSeries,
      seriesRegistered: true,
      checkoutReady: ready,
      orders: pending == null ? const [] : [pending!],
      order: pending,
      checkoutIntent: intent,
      recovery: recovery,
      unissuedOrderIds: pending == null ? const [] : [pending!.id]);

  @override
  Future<PlusSnapshot> configureMainnet(String key) async => current;
  @override
  Future<PlusSnapshot> snapshot() async => current;
  @override
  Future<PlusCheckoutIntent> prepareCheckout(String asset) async {
    selectedAsset = asset;
    return intent ??= PlusCheckoutIntent(requestId: 'request', asset: asset);
  }

  @override
  Future<PlusCheckoutIntent> bindCheckoutOffer(
          Map<String, dynamic> offer) async =>
      intent = PlusCheckoutIntent(
          requestId: intent!.requestId,
          asset: intent!.asset,
          offerJson: jsonEncode(offer));

  @override
  Future<PlusSnapshot> saveOrder(Map<String, dynamic> order) async {
    intent = null;
    pending = PlusOrder(
        id: 'renewal',
        network: 'solana-mainnet',
        product: 'mosh-plus-supporter-30d',
        mint: mainnetOrder['mint'] as String,
        recipient: mainnetOrder['recipient'] as String,
        amountAtomic: '2575000000000',
        reference: mainnetOrder['reference'] as String,
        status: PlusPaymentStatus.awaitingPayment,
        paymentUri: mainnetOrder['payment_uri'] as String,
        asset: 'CLXAI',
        tokenDecimals: 9,
        accessToken: 'private-order-token');
    return current;
  }

  @override
  Future<PlusSnapshot> saveSchedule(String id, BigInt reservedUntil) async =>
      current;
  @override
  Future<PlusRecoverySession> prepareRecovery() async =>
      recovery = PlusRecoverySession(
          id: 'session',
          pollToken: 'private-poll-token',
          publicKeyB64: 'public-key',
          code: 'ABCDEF12',
          expiresAtMs:
              BigInt.from(DateTime.now().millisecondsSinceEpoch + 900000),
          orders: const [],
          completedOrders: 0);
  @override
  Future<PlusSnapshot> saveRecoveryStatus(Map<String, dynamic> status) async {
    recovery = PlusRecoverySession(
        id: 'session',
        pollToken: 'private-poll-token',
        publicKeyB64: 'public-key',
        code: 'ABCDEF12',
        expiresAtMs: recovery!.expiresAtMs,
        url: 'https://billing.example/recover/session',
        orders: const [],
        completedOrders: 0);
    return current;
  }
}

class MainnetTestBilling extends PlusBilling {
  MainnetTestBilling() : super(mainnetConfig);
  bool enabled = true;
  @override
  Future<Map<String, dynamic>> catalog() async =>
      {...mainnetCatalog, 'purchases_enabled': enabled};
  @override
  Future<Map<String, dynamic>> createMainnet(
          PlusSeries series, PlusCheckoutIntent intent) async =>
      mainnetOrder;
  @override
  Future<Map<String, dynamic>> schedule(PlusSeries series) async =>
      {'id': series.id, 'reserved_until_ms': 0};
  @override
  Future<Map<String, dynamic>> startRecovery(
          PlusSeries series, PlusRecoverySession session) async =>
      {
        'id': session.id,
        'code': session.code,
        'url': 'https://billing.example/recover/session',
        'expires_at_ms': session.expiresAtMs.toInt(),
      };
}
