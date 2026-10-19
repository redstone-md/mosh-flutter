import 'dart:convert';
import 'package:mosh/src/rust/api/plus.dart' as api;
import 'package:mosh/src/rust/plus/types.dart';
import 'package:mosh/src/rust/plus/checkout.dart';
import 'package:mosh/src/rust/plus/recovery_types.dart';

/// Only blinded requests cross this boundary; wallet keys stay in the wallet.
class PlusCommands {
  Future<PlusSnapshot> configure(String key) =>
      api.configureIssuer(publicKeyB64: key);
  Future<PlusSnapshot> configureMainnet(String key) =>
      api.configureMainnetIssuer(publicKeyB64: key);
  Future<PlusSeries> prepareSeries() => api.prepareSeries();
  Future<PlusSnapshot> confirmSeries(String id) =>
      api.confirmSeriesRegistered(id: id);
  Future<PlusCheckoutIntent> prepareCheckout(String asset) =>
      api.prepareCheckout(asset: asset);
  Future<PlusCheckoutIntent> bindCheckoutOffer(Map<String, dynamic> offer) =>
      api.bindCheckoutOffer(offerJson: jsonEncode(offer));
  Future<PlusSnapshot> cancelCheckout() => api.cancelCheckout();
  Future<PlusSnapshot> saveSchedule(String id, BigInt reservedUntil) =>
      api.saveSchedule(id: id, reservedUntilMs: reservedUntil);
  Future<String> prepareOrder(String id) =>
      api.prepareOrderIssuance(orderId: id);
  Future<PlusSnapshot> completeOrder(String id, String signature) =>
      api.completeOrderIssuance(orderId: id, blindSignatureB64: signature);
  Future<PlusRecoverySession> prepareRecovery() => api.prepareRecovery();
  Future<PlusSnapshot> saveRecoveryStatus(Map<String, dynamic> status) =>
      api.saveRecoveryStatus(statusJson: jsonEncode(status));
  Future<PlusRecoveryIssuance> prepareRecoveryIssuance(String id) =>
      api.prepareRecoveryIssuance(orderId: id);
  Future<PlusSnapshot> snapshot() => api.snapshot();
  Future<PlusSnapshot> saveOrder(Map<String, dynamic> order) =>
      api.saveOrder(orderJson: jsonEncode(order));
  Future<String> prepare() => api.prepareIssuance();
  Future<PlusSnapshot> complete(String signature) =>
      api.completeIssuance(blindSignatureB64: signature);
  Future<PlusSnapshot> visibility(bool visible) =>
      api.setVisible(visible: visible);
}
