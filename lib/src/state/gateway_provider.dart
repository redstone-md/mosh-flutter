// ADR 0013 seam: the single provider whose implementation swaps fake<->real.
// S4.0 wired FakeGateway here as a slice-one-only in-Dart fake; S5 (this file)
// swaps the default to RealBridgeGateway so the wired runtime is the real
// `mosh_core` (slice-one moment-of-truth, ADR 0013 close-out). All other
// providers and widgets consume `gatewayProvider`, never a concrete Gateway
// impl, so the swap is contained to this body.
//
// Per ADR 0013 the fake MUST NOT be a silent default. It is now a deliberate
// opt-in via the `MOSH_FAKE_GATEWAY` compile-time flag:
//   - default (no env):            RealBridgeGateway()  (real Rust runtime)
//   - -dMOSH_FAKE_GATEWAY=true:    FakeGateway()        (no Rust; fast widget
//                                                          tests / dev)
// Widget tests that pump a screen consuming a gateway-backed provider must
// override `gatewayProvider` with `FakeGateway()` in their ProviderScope
// (flutter test has no native cdylib, so RealBridgeGateway cannot run there).
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/src/gateway/gateway.dart';
import 'package:mosh/src/gateway/fake_gateway.dart';
import 'package:mosh/src/gateway/real_bridge_gateway.dart';

/// Compile-time opt-in for the slice-one in-Dart fake (ADR 0013). Default
/// `false` selects the real Rust runtime; pass `-dMOSH_FAKE_GATEWAY=true`
// (dart-define) for widget tests or local dev without a built cdylib.
const useFakeGateway =
    bool.fromEnvironment('MOSH_FAKE_GATEWAY', defaultValue: false);

final gatewayProvider = Provider<Gateway>(
  (ref) => useFakeGateway ? FakeGateway() : RealBridgeGateway(),
);
