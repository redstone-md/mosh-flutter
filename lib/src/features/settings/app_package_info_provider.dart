import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// The installed build, including command-line version overrides.
/// The plugin caches successful reads; leaving About allows a failed read
/// to be retried on the next visit, without a refresh control.
final appPackageInfoProvider = FutureProvider.autoDispose<PackageInfo>(
  (ref) => PackageInfo.fromPlatform(),
  retry: (count, error) => null,
);
