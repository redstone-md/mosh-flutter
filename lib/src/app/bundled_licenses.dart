import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Licenses of what Mosh ships beyond its Dart packages, whose notices Flutter
/// collects itself: Mosh's own license, the Rust crates, the Go modules of
/// Moss, libmpv and FFmpeg, and the Inter font.
/// `scripts/third-party-licenses.mjs` generates the asset in the format of
/// Flutter's own NOTICES.
const bundledLicensesAsset = 'assets/licenses/NOTICES';

final _separator = '\n${'-' * 80}\n';

/// The entries of [bundledLicensesAsset], each naming the components under
/// one license text. `main` adds it to [LicenseRegistry], which reads it only
/// when the license page opens.
Stream<LicenseEntry> bundledLicenses() async* {
  final notices =
      await rootBundle.loadString(bundledLicensesAsset, cache: false);
  for (final entry in notices.trimRight().split(_separator)) {
    final split = entry.indexOf('\n\n');
    yield LicenseEntryWithLineBreaks(
      entry.substring(0, split).split('\n'),
      entry.substring(split + 2),
    );
  }
}
