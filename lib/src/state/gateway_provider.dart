// The one provider that hands out the Gateway (ADR 0013).
//
// Widgets and other providers read `gatewayProvider`, never a concrete
// implementation, so the wired runtime is a single swap here. The app always
// gets the real Rust runtime; tests override this provider with the
// scriptable test gateway (test/support/scriptable_gateway.dart), which is
// why no in-app fake ships any more.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/src/gateway/gateway.dart';
import 'package:mosh/src/gateway/real_bridge_gateway.dart';

final gatewayProvider = Provider<Gateway>((ref) => RealBridgeGateway());
