import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:mosh/src/features/plus/plus_commands.dart';
import 'package:mosh/src/rust/api/private_dm.dart' as setup;
import 'package:mosh/src/rust/frb_generated.dart';
import 'package:mosh/src/rust/plus/types.dart';

void main() {
  test('real PLUS bridge persists order, prepares blindly and rejects forgery',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('mosh-plus-bridge-');
    final extension = Platform.isWindows
        ? 'dll'
        : Platform.isMacOS
            ? 'dylib'
            : 'so';
    final prefix = Platform.isWindows ? '' : 'lib';
    await RustLib.init(
        externalLibrary: ExternalLibrary.open(
            'mosh-core/target/debug/${prefix}mosh_core.$extension'));
    addTearDown(() async {
      RustLib.dispose();
      if (!Platform.isWindows) await directory.delete(recursive: true);
    });
    await setup.setAppDataDir(path: directory.path);
    await setup.setHistoryDek(dek: List.filled(32, 77));
    final vector = jsonDecode(
        await File('mosh-core/tests/fixtures/plus-public-vector.json')
            .readAsString()) as Map<String, dynamic>;
    final commands = PlusCommands();
    expect((await commands.configure(vector['public_key'] as String)).active,
        isFalse);
    final expires =
        ((DateTime.now().millisecondsSinceEpoch ~/ 86400000) + 31) * 86400000;
    final order = <String, dynamic>{
      'id': 'bridge-test',
      'network': 'solana-devnet',
      'product': 'mosh-plus-30d',
      'mint': 'So11111111111111111111111111111111111111112',
      'recipient': '11111111111111111111111111111111',
      'amount_atomic': '1',
      'reference': 'So11111111111111111111111111111111111111112',
      'status': 'paid',
      'expires_at_ms': expires,
      'access_token': 'public-native-test-capability-000000000000',
      'payment_uri':
          'solana:11111111111111111111111111111111?amount=0.000000001&spl-token=So11111111111111111111111111111111111111112&reference=So11111111111111111111111111111111111111112',
    };
    expect((await commands.saveOrder(order)).order!.status,
        PlusPaymentStatus.paid);
    final blinded = await commands.prepare();
    expect(base64Decode(blinded).length, 256);
    expect(await commands.prepare(), blinded);
    await expectLater(commands.complete(base64Encode(List.filled(256, 0))),
        throwsA(anything));
    expect((await commands.snapshot()).active, isFalse);
    expect((await commands.visibility(false)).visible, isFalse);
    expect((await commands.snapshot()).order!.id, 'bridge-test');
  });
}
