import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/src/features/device_link/device_link_provider.dart';
import 'package:mosh/src/platform/app_data_dir.dart';
import 'package:mosh/src/rust/device_link/types.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/session_providers.dart';

import 'first_run_profile.dart';

/// Production enables the gate; isolated app tests retain their existing seams.
final firstRunEnabledProvider = Provider<bool>((ref) => false);

final firstRunStoreProvider = Provider<FirstRunStore>((ref) {
  final path = appDataDir();
  return FirstRunStore(path == null ? null : Directory(path));
});

final firstRunProfileProvider =
    AsyncNotifierProvider<FirstRunController, FirstRunProfile>(
  FirstRunController.new,
);

/// The gate consumes the VPN question for this launch, avoiding a second prompt.
final firstRunShownProvider = NotifierProvider<FirstRunShown, bool>(
  FirstRunShown.new,
);

class FirstRunShown extends Notifier<bool> {
  @override
  bool build() => false;
  void mark() => state = true;
}

class FirstRunController extends AsyncNotifier<FirstRunProfile> {
  @override
  Future<FirstRunProfile> build() async {
    final store = ref.watch(firstRunStoreProvider);
    var profile = await store.read();
    if (profile == null) {
      profile = FirstRunProfile(completed: await _existingInstallation());
      await store.write(profile);
    }
    ref.read(inviteFlowProvider.notifier).setDisplayName(profile.displayName);
    return profile;
  }

  Future<bool> _existingInstallation() async {
    final bridge = ref.read(bridgeFacadeProvider);
    final subscription = ref.listen(deviceLinkProvider, (_, __) {});
    var existing = false;
    Future<void> check(Future<bool> Function() read) async {
      if (await read()) existing = true;
    }

    try {
      // Await every check. A known history bypasses setup; failed reads must
      // never turn an unknown installation into an empty one.
      await Future.wait<void>([
        check(() => bridge.listSessions().then((s) => s.sessions.isNotEmpty)),
        check(() => bridge.listChannels().then((s) => s.channels.isNotEmpty)),
        check(() => bridge.listGroups().then((s) => s.groups.isNotEmpty)),
        check(() => bridge.listOrgs().then((s) => s.isNotEmpty)),
        check(() => ref
            .read(deviceLinkProvider.future)
            .then((link) => _hasIdentityHistory(link.snapshot))),
      ]);
    } catch (_) {
      if (!existing) rethrow;
    } finally {
      subscription.close();
    }
    return existing;
  }

  Future<void> saveName(String name, {bool advance = false}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 64) {
      throw const FormatException('Invalid display name');
    }
    final profile = await future;
    await _save(profile.copyWith(
        displayName: trimmed, step: advance ? SetupStep.device : profile.step));
    ref.read(inviteFlowProvider.notifier).setDisplayName(trimmed);
  }

  Future<void> goTo(SetupStep step) async {
    final profile = await future;
    if (step != SetupStep.name && profile.displayName.isEmpty) {
      throw StateError('Choose a display name first');
    }
    await _save(profile.copyWith(step: step));
  }

  /// Save before relaunch. Reveal the router only after restart handling returns.
  Future<void> finish(Future<void> Function() afterSave) async {
    final profile = (await future).copyWith(completed: true);
    await ref.read(firstRunStoreProvider).write(profile);
    await afterSave();
    if (ref.mounted) state = AsyncData(profile);
  }

  Future<void> _save(FirstRunProfile profile) async {
    await ref.read(firstRunStoreProvider).write(profile);
    if (ref.mounted) state = AsyncData(profile);
  }
}

bool _hasIdentityHistory(DeviceLinkSnapshot snapshot) =>
    !snapshot.canJoin ||
    snapshot.revoked ||
    snapshot.devices.length > 1 ||
    snapshot.role != null ||
    snapshot.phase == DeviceLinkPhase.linked;
