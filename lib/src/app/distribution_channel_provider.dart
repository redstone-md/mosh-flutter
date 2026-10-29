import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'distribution_channel.dart';

/// The channel this build was compiled for. Injectable, so a test runs a store
/// build's rules without recompiling.
final distributionChannelProvider =
    Provider((_) => DistributionChannel.fromEnvironment());
