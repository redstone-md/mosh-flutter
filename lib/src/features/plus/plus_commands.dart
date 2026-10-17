import 'dart:convert';
import 'package:mosh/src/rust/api/plus.dart' as api;
import 'package:mosh/src/rust/plus/types.dart';

/// Only blinded requests cross this boundary; wallet keys stay in the wallet.
class PlusCommands {
  Future<PlusSnapshot> configure(String key) =>
      api.configureIssuer(publicKeyB64: key);
  Future<PlusSnapshot> snapshot() => api.snapshot();
  Future<PlusSnapshot> saveOrder(Map<String, dynamic> order) =>
      api.saveOrder(orderJson: jsonEncode(order));
  Future<String> prepare() => api.prepareIssuance();
  Future<PlusSnapshot> complete(String signature) =>
      api.completeIssuance(blindSignatureB64: signature);
  Future<PlusSnapshot> visibility(bool visible) =>
      api.setVisible(visible: visible);
}
