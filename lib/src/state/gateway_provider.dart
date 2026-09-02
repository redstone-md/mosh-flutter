// The two providers that hand out the bridge surfaces (ADR 0013, ADR 0025).
//
// The conversation seam goes through `gatewayProvider`: widgets and other
// providers read it, never a concrete implementation, so the wired runtime
// is a single swap here. Everything that only mirrors one bridge call 1:1
// goes through `bridgeFacadeProvider` -- those callers reach the concrete
// `BridgeFacade` directly, because a pass-through hides no decision worth a
// seam (ADR 0025).
//
// The app always gets the real Rust runtime; tests override these providers
// with the scriptable doubles in test/support (scriptable_gateway.dart for
// the seam, scriptable_bridge.dart for the facade), which is why no in-app
// fake ships any more.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/src/gateway/bridge_facade.dart';
import 'package:mosh/src/gateway/gateway.dart';
import 'package:mosh/src/gateway/real_bridge_gateway.dart';

final gatewayProvider = Provider<Gateway>((ref) => RealBridgeGateway());

final bridgeFacadeProvider = Provider<BridgeFacade>((ref) => BridgeFacade());
