import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/state/session_providers.dart'
    show mossLibraryInfoProvider;
import 'package:mosh/src/features/diagnostics/channel_group_diagnostics.dart';
import 'package:mosh/src/features/diagnostics/diagnostics_summary.dart';
import 'package:mosh/src/features/diagnostics/diagnostics_sections.dart';
import 'package:mosh/src/features/diagnostics/summary_card.dart';
import 'package:mosh/src/rust/channel_runtime/types.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/rust/private_group_runtime.dart';
import 'package:mosh/src/rust/api/diagnostics.dart' show MossLibraryInfo;

/// The scrollable content column: SummaryCard, then RuntimeError (if any),
/// then the active conversation's diagnostics section, else NoActiveSession.
/// Branch order: `session ? SessionDiagnostics : channel ?
/// ChannelDiagnostics : group ? GroupDiagnostics : NoActiveSession`.
class ConversationDiagnosticsContent extends ConsumerWidget {
  const ConversationDiagnosticsContent({
    super.key,
    this.session,
    required this.channel,
    required this.group,
    required this.error,
    this.scrollable = true,
  });

  final SessionSnapshot? session;
  final ChannelSnapshot? channel;
  final GroupSnapshot? group;
  final String? error;
  final bool scrollable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final summary = diagnosticsSummary(
        l: l, session: session, channel: channel, group: group, error: error);
    // Spec #5: what the loaded library reports. The RTT question names the
    // active DM's counterpart (null elsewhere); one read per drawer mount,
    // like every other facade mirror (ADR 0025). Unloaded -> null rows: the
    // drawer renders without the library rows instead of waiting.
    final MossLibraryInfo? libraryInfo =
        switch (ref.watch(mossLibraryInfoProvider(session?.peerMossId))) {
      AsyncData(:final value) => value,
      _ => null,
    };
    final body = Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SummaryCard(summary: summary),
          if (error != null) ...[
            const SizedBox(height: 12),
            RuntimeError(message: error!),
          ],
          const SizedBox(height: 12),
          if (session != null)
            SessionDiagnostics(
              session: session!,
              libraryInfo: libraryInfo,
            )
          else if (channel != null)
            ChannelDiagnostics(channel: channel!, libraryInfo: libraryInfo)
          else if (group != null)
            GroupDiagnostics(group: group!, libraryInfo: libraryInfo)
          else
            const NoActiveSession(),
        ],
      ),
    );
    return scrollable ? SingleChildScrollView(child: body) : body;
  }
}
