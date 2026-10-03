import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/src/gateway/bridge_facade.dart';
import 'package:mosh/src/gateway/gateway.dart';
import 'package:mosh/src/gateway/real_bridge_gateway.dart';

final gatewayProvider = Provider<Gateway>((ref) => RealBridgeGateway());

final bridgeFacadeProvider = Provider<BridgeFacade>((ref) => BridgeFacade());
