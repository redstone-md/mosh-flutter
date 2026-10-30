import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/plus/plus_catalog.dart';
import 'package:mosh/src/features/plus/plus_mainnet_flow.dart';
import 'package:mosh/src/rust/plus/checkout.dart';
import 'package:mosh/src/rust/plus/types.dart';
import '../../support/plus/mainnet_fakes.dart';

void main() {
  test('a lost checkout response retains its accepted price after restart',
      () async {
    final native = MainnetTestCommands();
    final billing = LostResponseBilling();
    final original = PlusCatalog.fromJson(mainnetCatalog, 'pin', mainnet: true);
    PlusMainnetFlow flow(Future<PlusCatalog> Function() catalog) =>
        PlusMainnetFlow(
            commands: native,
            client: billing,
            catalog: catalog,
            alive: () => true,
            update: (_) {});
    await expectLater(flow(() async => original).purchase('CLXAI'),
        throwsA(isA<StateError>()));
    expect(native.intent?.offerJson, contains('2575000000000'));
    // A new controller/process resumes native state without consulting a new price.
    await flow(() async => throw StateError('new price or catalog outage'))
        .purchase('CLXAI');
    expect(native.pending?.id, 'renewal');
    expect(billing.requests, ['request', 'request']);
  });
}

class LostResponseBilling extends MainnetTestBilling {
  final requests = <String>[];
  @override
  Future<Map<String, dynamic>> createMainnet(
      PlusSeries series, PlusCheckoutIntent intent) async {
    requests.add(intent.requestId);
    if (requests.length == 1) throw StateError('response lost');
    return mainnetOrder;
  }
}
