// ADR 0013 seam: the single provider whose implementation swaps fake<->real.
// S4.0 wires FakeGateway here (slice-one in-Dart fake); S5 replaces it with
// RealBridgeGateway by changing only this body. All other providers and
// widgets consume `gatewayProvider`, never a concrete Gateway impl.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/src/gateway/fake_gateway.dart';
import 'package:mosh/src/gateway/gateway.dart';

final gatewayProvider = Provider<Gateway>((ref) => FakeGateway());
