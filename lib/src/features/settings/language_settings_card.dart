import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_select.dart';
import 'package:mosh/src/state/locale_provider.dart';

import 'settings_card.dart';

class LanguageSettingsCard extends ConsumerStatefulWidget {
  const LanguageSettingsCard({super.key});

  @override
  ConsumerState<LanguageSettingsCard> createState() =>
      _LanguageSettingsCardState();
}

class _LanguageSettingsCardState extends ConsumerState<LanguageSettingsCard> {
  bool _saving = false;
  bool _saveFailed = false;

  Future<void> _select(Locale? locale) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _saveFailed = false;
    });
    try {
      await ref.read(localeProvider.notifier).setLocale(locale);
    } catch (_) {
      if (mounted) setState(() => _saveFailed = true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return SettingsCard(
      icon: Icons.language,
      title: l.interfaceLanguageTitle,
      hint: l.interfaceLanguageHint,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        MoshSelect<Locale?>(
          label: l.interfaceLanguageTitle,
          value: ref.watch(localeProvider),
          options: [
            MoshSelectOption(null, l.interfaceLanguageSystem),
            MoshSelectOption(const Locale('ru'), l.interfaceLanguageRussian),
            MoshSelectOption(const Locale('en'), l.interfaceLanguageEnglish),
          ],
          onChanged: _saving ? null : _select,
        ),
        if (_saveFailed)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Semantics(
              liveRegion: true,
              child: Text(l.interfaceLanguageSaveError,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          ),
      ]),
    );
  }
}
