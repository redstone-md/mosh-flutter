import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_release_provider.dart';
import 'app_update_apply.dart';
import 'app_update_download.dart';

/// What About shows while an update runs.
sealed class UpdateInstallState {
  const UpdateInstallState();
}

/// Nothing has been downloaded: the notice stands on the feed alone.
final class UpdateInstallIdle extends UpdateInstallState {
  const UpdateInstallIdle();
}

final class UpdateInstallDownloading extends UpdateInstallState {
  const UpdateInstallDownloading({required this.received, this.total});

  final int received;

  /// Null when the server declared no size, which keeps the bar indeterminate.
  final int? total;

  double? get fraction {
    final size = total;
    return size == null || size <= 0 ? null : received / size;
  }
}

/// The verified artifact is with the installer; this process is on its way out.
final class UpdateInstallApplying extends UpdateInstallState {
  const UpdateInstallApplying();
}

/// The download or the handover failed. The installed build is untouched.
final class UpdateInstallFailed extends UpdateInstallState {
  const UpdateInstallFailed();
}

/// The host this build runs on, which decides what can be installed.
final hostPlatformProvider =
    Provider<HostPlatform>((ref) => currentHostPlatform());

/// How a verified artifact is installed here.
final updateApplierProvider = Provider<UpdateApplier>(
  (ref) => switch (ref.watch(hostPlatformProvider)) {
    HostPlatform.windows => const WindowsUpdateApplier(),
    HostPlatform.macOS => const MacOsUpdateApplier(),
    HostPlatform.other => const UnsupportedUpdateApplier(),
  },
);

/// Fetches release artifacts; injectable, so tests never open a socket.
final releaseDownloaderProvider =
    Provider<ReleaseDownloader>((ref) => const ReleaseDownloader());

/// The artifact this host would install, when the feed offered a newer build.
///
/// Null covers both "nothing newer" and "nothing this host can install", so
/// About reads it to choose between the update button and the release page.
final updateCandidateProvider = Provider.autoDispose<UpdateCandidate?>((ref) {
  final release = ref.watch(updateCheckProvider).value;
  if (release == null) return null;
  return updateCandidateFor(release, ref.watch(hostPlatformProvider));
});

/// Runs one update: download, verify, hand over to the installer.
///
/// Deliberately not auto-disposed: leaving About while an update is already
/// under way must not cancel work the person asked for, and a failure has to
/// still be there when they come back.
final updateInstallProvider =
    NotifierProvider<UpdateInstall, UpdateInstallState>(UpdateInstall.new);

class UpdateInstall extends Notifier<UpdateInstallState> {
  @override
  UpdateInstallState build() => const UpdateInstallIdle();

  /// A second press while downloading is a no-op, not a second download.
  Future<void> start(UpdateCandidate candidate) async {
    if (state is UpdateInstallDownloading || state is UpdateInstallApplying) {
      return;
    }
    state = const UpdateInstallDownloading(received: 0);
    try {
      final file = await ref.read(releaseDownloaderProvider).download(
            candidate,
            onProgress: (received, total) => state =
                UpdateInstallDownloading(received: received, total: total),
          );
      state = const UpdateInstallApplying();
      await ref.read(updateApplierProvider).apply(file);
    } catch (_) {
      state = const UpdateInstallFailed();
    }
  }
}
