import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_shapes.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/state/call_presentation_provider.dart';
import 'package:mosh/src/state/voice_call_orchestrator_provider.dart';
import 'package:mosh/src/state/voice_call_session_provider.dart';
import 'call_button.dart';
import 'call_view.dart';
import 'call_view_state.dart';
import 'call_view_wiring.dart';
import 'call_who_line.dart';

/// The Call plate of the Minimized call card: a call that is not open, in
/// the desktop's title bar. A press on the name opens the call again; the
/// buttons do their own work and open nothing.
class CallPlate extends StatelessWidget {
  const CallPlate(
      {super.key,
      required this.label,
      required this.peer,
      required this.line,
      required this.controls,
      required this.onOpen});

  final String label, peer;
  final CallLine line;
  final List<CallControl> controls;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) => Semantics(
        label: label,
        container: true,
        child: Material(
          color: CallTone.neutral.plate(MoshColors.of(context)),
          shape: MoshShapes.pill,
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: MoshSpace.s8),
            child: Padding(
              padding: const EdgeInsets.only(right: MoshSpace.s1),
              child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: MoshSpace.s2,
                  children: [
                    Flexible(child: _who(context)),
                    for (final control in controls)
                      CallMiniButton(control: control, mark: true),
                  ]),
            ),
          ),
        ),
      );

  Widget _who(BuildContext context) => Tooltip(
        message: AppLocalizations.of(context)!.callExpand,
        child: InkWell(
          onTap: onOpen,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: MoshSpace.s8),
            child: Padding(
              padding: const EdgeInsets.only(left: MoshSpace.s3),
              child: Center(
                  widthFactor: 1, child: CallWhoLine(peer: peer, line: line)),
            ),
          ),
        ),
      );
}

/// The call in the title bar, which shows it while [callPresentationProvider]
/// gives the plate: a voice call minimized on the desktop. The call host under the
/// router keeps the call's sound, notification and errors.
class TitleBarCall extends ConsumerWidget {
  const TitleBarCall({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session =
        ref.watch(voiceCallSessionProvider.select((s) => s?.sessionId));
    if (session == null) return const SizedBox.shrink();
    final call = callViewOf(
        session,
        ref.watch(voiceCallOrchestratorProvider(session)),
        AppLocalizations.of(context)!);
    if (call == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: MoshSpace.s2),
      child: CallView(
          call: call,
          form: CallForm.plate,
          onOpen: ref.read(callPresentationProvider.notifier).open,
          onAction: (action) => runCallCommand(ref, call.command(action))),
    );
  }
}
