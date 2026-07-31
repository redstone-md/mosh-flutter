// ADR 0013 seam: the single provider whose implementation swaps fake<->real.
// S4.1 wires FakeGateway here; S5 replaces it with RealBridgeGateway. The
// default throws so the app fails loudly if anything reads the gateway before
// S4.1 lands; the S2b diagnostics smoke does NOT read it (it calls the frb
// appDiagnostics() binding directly), so the app still runs for the smoke.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/src/gateway/gateway.dart';

final gatewayProvider = Provider<Gateway>((ref) {
  throw UnimplementedError('FakeGateway wired in S4.1');
});
