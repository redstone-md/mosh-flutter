import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/features/conversation/conversation_tools.dart'
    show isMobileBreakpoint;
import 'package:mosh/src/routing/mosh_title_bar.dart';

import 'display_name_form.dart';
import 'first_run_device_step.dart';
import 'first_run_heading.dart';
import 'first_run_layout.dart';
import 'first_run_network_step.dart';
import 'first_run_profile.dart';
import 'first_run_provider.dart';
import 'first_run_transition.dart';

class FirstRunWizard extends ConsumerStatefulWidget {
  const FirstRunWizard({super.key, required this.profile});
  final FirstRunProfile profile;

  /// Width of a step's column on the desktop.
  static const double stepWidth = 480;

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
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
            child: Column(children: [
          if (MoshTitleBar.standsAlone(context))
            const MoshTitleBar.brand(showName: false),
          Expanded(child: LayoutBuilder(builder: _viewport)),
        ])),
      );

  /// The Wizard step card: one column on the background, 480 px wide and
  /// centred on the desktop, as wide as the screen and at its top on a phone.
  Widget _viewport(BuildContext context, BoxConstraints constraints) {
    final pad = constraints.maxWidth < FirstRunWizard.stepWidth + MoshSpace.s12
        ? MoshSpace.s4
        : MoshSpace.s6;
    final mobile = isMobileBreakpoint(context);
    return SingleChildScrollView(
      child: SetupStableLayout(
        viewportHeight: constraints.maxHeight,
        centred: !mobile,
        layout: (
          constraints.biggest,
          MediaQuery.textScalerOf(context),
          Localizations.localeOf(context)
        ),
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxWidth: FirstRunWizard.stepWidth + pad * 2),
          child: Padding(
            key: const ValueKey('setup-step'),
            padding: EdgeInsets.all(pad),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // On a phone the progress stands a step inside the column.
                  Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: mobile ? MoshSpace.s4 : 0),
                    child:
                        Center(child: SetupProgress(step: widget.profile.step)),
                  ),
                  const SizedBox(height: MoshSpace.s5),
                  SetupStepTransition(
                      key: const ValueKey('setup-content'),
                      step: widget.profile.step,
                      builder: _step),
                ]),
          ),
        ),
      ),
    );
  }

  /// A step: its question, then what answers it.
  Widget _step(BuildContext context, SetupStep step) {
    final l = AppLocalizations.of(context)!;
    final controller = ref.read(firstRunProfileProvider.notifier);
    return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SetupHeading(step: step),
          const SizedBox(height: MoshSpace.s5),
          switch (step) {
            SetupStep.name => DisplayNameForm(
                inSetup: true,
                showAvatar: false,
                showSaveConfirmation: false,
                note: const SetupPrivacyNote(),
                initialName: widget.profile.displayName,
                actionLabel: l.firstRunContinue,
                onSave: (name) => controller.saveName(name, advance: true)),
            SetupStep.device => const FirstRunDeviceStep(),
            SetupStep.network => const FirstRunNetworkStep(),
          },
        ]);
  }
}
