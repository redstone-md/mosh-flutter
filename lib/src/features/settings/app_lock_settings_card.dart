import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_select.dart';
import 'package:mosh/src/features/lock/android_app_access.dart';
import 'package:mosh/src/features/lock/android_access_state.dart';
import 'settings_card.dart';

class AppLockSettingsCard extends ConsumerStatefulWidget {
  const AppLockSettingsCard({super.key});
  @override
  ConsumerState<AppLockSettingsCard> createState() =>
      _AppLockSettingsCardState();
}

class _AppLockSettingsCardState extends ConsumerState<AppLockSettingsCard> {
  bool _saving = false, _failed = false;
  Future<void> _save(AndroidAppAccess access, int seconds) async {
    setState(() {
      _saving = true;
      _failed = false;
    });
    try {
      await access.setDelay(seconds);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final access = ref.watch(androidAppAccessProvider);
    if (access == null) return const SizedBox.shrink();
    final l = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: SettingsSurface(
        padding: const EdgeInsets.all(20),
        child: ListenableBuilder(
            listenable: access,
            builder: (context, _) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SettingsCardHeader(
                          icon: Icons.lock_outline,
                          subtitle: Text(l.appLockDelay),
                          title: Text(l.appLockTitle,
                              style: Theme.of(context).textTheme.titleMedium)),
                      const SizedBox(height: 12),
                      MoshSelect<int>(
                          label: l.appLockDelay,
                          value: access.delaySeconds,
                          options: [
                            for (final seconds in AndroidAccessState.delays)
                              MoshSelectOption(
                                  seconds,
                                  seconds == 0
                                      ? l.appLockImmediate
                                      : l.appLockMinutes(seconds ~/ 60))
                          ],
                          onChanged: _saving
                              ? null
                              : (seconds) => _save(access, seconds)),
                      if (_failed)
                        Text(l.appLockSaveError,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)),
                    ])),
      ),
    );
  }
}
