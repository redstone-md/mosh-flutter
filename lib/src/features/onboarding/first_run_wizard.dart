import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/routing/mosh_title_bar.dart';

import 'display_name_form.dart';
import 'first_run_device_step.dart';
import 'first_run_layout.dart';
import 'first_run_network_step.dart';
import 'first_run_profile.dart';
import 'first_run_provider.dart';

class FirstRunWizard extends ConsumerStatefulWidget {
  const FirstRunWizard({super.key, required this.profile});
  final FirstRunProfile profile;

  @override
  ConsumerState<FirstRunWizard> createState() => _FirstRunWizardState();
}

class _FirstRunWizardState extends ConsumerState<FirstRunWizard> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) ref.read(firstRunShownProvider.notifier).mark();
    });
  }

  @override
  Widget build(BuildContext context) => Theme(
      data: _setupTheme(Theme.of(context)),
      child: Scaffold(
        backgroundColor: MoshColors.bg0,
        body: SafeArea(
            child: Column(children: [
          const MoshTitleBar.brand(),
          Expanded(child: LayoutBuilder(builder: (context, size) {
            final narrow = size.maxWidth < 800;
            return SingleChildScrollView(
              padding: EdgeInsets.all(narrow ? 16 : 32),
              child: Center(
                  child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1160),
                child: Container(
                  padding: EdgeInsets.all(narrow ? 20 : 40),
                  decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: MoshColors.moss.withValues(alpha: .3)),
                      gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color.alphaBlend(
                                MoshColors.moss.withValues(alpha: .055),
                                MoshColors.bg0),
                            MoshColors.bg1,
                            MoshColors.bg0
                          ])),
                  child: _content(context),
                ),
              )),
            );
          })),
        ])),
      ));

  ThemeData _setupTheme(ThemeData theme) => theme.copyWith(
      visualDensity: VisualDensity.standard,
      filledButtonTheme: FilledButtonThemeData(
          style: theme.filledButtonTheme.style?.copyWith(
              minimumSize: const WidgetStatePropertyAll(Size(0, 52)))),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: theme.outlinedButtonTheme.style?.copyWith(
              minimumSize: const WidgetStatePropertyAll(Size(0, 48)))));

  Widget _content(BuildContext context) => Column(children: [
        ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: SetupProgress(step: widget.profile.step)),
        const SizedBox(height: 40),
        SetupFrame(step: widget.profile.step, child: _form(context)),
      ]);

  Widget _form(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final controller = ref.read(firstRunProfileProvider.notifier);
    return switch (widget.profile.step) {
      SetupStep.name =>
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Semantics(
              header: true,
              child: Text(l.firstRunNameTitle,
                  style: Theme.of(context).textTheme.headlineSmall)),
          const SizedBox(height: 12),
          Text(l.firstRunNameBody),
          const SizedBox(height: 24),
          DisplayNameForm(
              initialName: widget.profile.displayName,
              actionLabel: l.firstRunContinue,
              onSave: (name) => controller.saveName(name, advance: true)),
        ]),
      SetupStep.device => const FirstRunDeviceStep(),
      SetupStep.network => const FirstRunNetworkStep(),
    };
  }
}
