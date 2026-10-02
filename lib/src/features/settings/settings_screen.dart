import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/routing/app_router.dart' show AppRoutes;
import 'package:mosh/src/routing/mosh_title_bar.dart';

import 'settings_content.dart';
import 'settings_nav.dart';
import 'settings_navigation.dart';

/// Sidebar plus useful content width. Narrow windows use list/detail navigation.
const double kSettingsTwoPaneMinWidth = 800;

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _showSection = false;

  void _select(SettingsSection section) {
    ref.read(settingsSectionProvider.notifier).select(section);
    setState(() => _showSection = true);
  }

  void _exit() {
    _rememberDefault(
        MediaQuery.sizeOf(context).width >= kSettingsTwoPaneMinWidth);
    final router = GoRouter.maybeOf(context);
    if (router == null) return;
    if (router.canPop()) {
      router.pop();
    } else {
      router.go(AppRoutes.sessions);
    }
  }

  void _rememberDefault(bool wide) {
    if (wide && ref.read(settingsSectionProvider) == null) {
      ref.read(settingsSectionProvider.notifier).select(SettingsSection.sound);
    }
  }

  void _back(bool wide) {
    if (!wide && _showSection) {
      setState(() => _showSection = false);
    } else {
      _exit();
    }
  }

  @override
  Widget build(BuildContext context) {
    final section = ref.watch(settingsSectionProvider) ?? SettingsSection.sound;
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= kSettingsTwoPaneMinWidth;
      return PopScope<Object?>(
        canPop: wide || !_showSection,
        onPopInvokedWithResult: (didPop, _) {
          _rememberDefault(wide);
          if (!didPop) _back(wide);
        },
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () => _back(wide),
          },
          child: Focus(
            autofocus: true,
            child: Scaffold(
              backgroundColor: MoshColors.bg0,
              appBar: wide ? null : _appBar(),
              body: SafeArea(
                child: wide ? _wide(section) : _narrow(section),
              ),
            ),
          ),
        ),
      );
    });
  }

  PreferredSizeWidget? _appBar() {
    if (!_showSection) return null;
    final l = AppLocalizations.of(context)!;
    return AppBar(
      title: Text(l.settingsTitle),
      leading: IconButton(
        tooltip: l.settingsBackToSections,
        onPressed: () => _back(false),
        icon: const Icon(Icons.arrow_back),
      ),
    );
  }

  Widget _wide(SettingsSection section) => Column(
        children: [
          const MoshTitleBar.brand(),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 280,
                  child: SettingsNav(
                    sidebar: true,
                    selected: section,
                    onSelect: _select,
                    onExit: _exit,
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: SettingsContent(
                      key: ValueKey(section), section: section, wide: true),
                ),
              ],
            ),
          ),
        ],
      );

  Widget _narrow(SettingsSection section) => _showSection
      ? SettingsContent(key: ValueKey(section), section: section, wide: false)
      : SettingsNav(selected: section, onSelect: _select, onExit: _exit);
}
