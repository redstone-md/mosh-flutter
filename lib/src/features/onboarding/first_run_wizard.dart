import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/routing/mosh_title_bar.dart';

import 'display_name_form.dart';
import 'first_run_device_step.dart';
import 'first_run_heading.dart';
import 'first_run_layout.dart';
import 'first_run_network_step.dart';
import 'first_run_profile.dart';
import 'first_run_provider.dart';
import 'first_run_sizing.dart';
import 'first_run_theme.dart';

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
      data: buildSetupTheme(Theme.of(context)),
      child: Scaffold(
        backgroundColor: MoshColors.bg0,
        body: SafeArea(
            child: Column(children: [
          const MoshTitleBar.brand(),
          Expanded(child: LayoutBuilder(builder: _viewport)),
        ])),
      ));

  Widget _viewport(BuildContext context, BoxConstraints constraints) {
    final sizing = SetupSizing(constraints.biggest,
        textScale: MediaQuery.textScalerOf(context).scale(14) / 14);
    return SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: Padding(
          padding: EdgeInsets.all(sizing.outerPadding),
          child: Center(
              child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: sizing.cardMaxWidth),
                  child: _card(context, sizing))),
        ),
      ),
    );
  }

  Widget _card(BuildContext context, SetupSizing sizing) => Container(
      width: double.infinity,
      padding: EdgeInsets.all(sizing.cardPadding),
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: MoshColors.moss.withValues(alpha: .3)),
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.alphaBlend(
                    MoshColors.moss.withValues(alpha: .055), MoshColors.bg0),
                MoshColors.bg1,
                MoshColors.bg0
              ])),
      child: _content(context, sizing));

  Widget _content(BuildContext context, SetupSizing sizing) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: SetupProgress(
                        step: widget.profile.step, compact: sizing.compact))),
            SizedBox(height: sizing.sectionGap),
            Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: SetupHeading(step: widget.profile.step))),
            const SizedBox(height: 24),
            SetupFrame(
                step: widget.profile.step,
                sizing: sizing,
                child: _form(context, sizing)),
            if (sizing.stacked &&
                sizing.showIllustration &&
                widget.profile.step == SetupStep.name) ...[
              const SizedBox(height: 20),
              const SetupPrivacyNote(),
            ],
          ]);

  Widget _form(BuildContext context, SetupSizing sizing) {
    final l = AppLocalizations.of(context)!;
    final controller = ref.read(firstRunProfileProvider.notifier);
    return switch (widget.profile.step) {
      SetupStep.name => DisplayNameForm(
          compact: sizing.compact,
          initialName: widget.profile.displayName,
          actionLabel: l.firstRunContinue,
          onSave: (name) => controller.saveName(name, advance: true)),
      SetupStep.device => const FirstRunDeviceStep(),
      SetupStep.network => const FirstRunNetworkStep(),
    };
  }
}
