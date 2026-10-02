import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/diagnostics/diagnostics_sections.dart';
import 'package:mosh/src/rust/moss_runtime.dart';
import 'package:mosh/src/state/session_providers.dart';

/// Existing bridge reads report library capability, never chat connectivity.
class ConnectionDiagnostics extends ConsumerWidget {
  const ConnectionDiagnostics({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final runtime = ref.watch(nativeRuntimeStatusProvider);
    final library = ref.watch(mossLibraryInfoProvider(null));
    final loading = runtime.isLoading || library.isLoading;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        runtime.when(
          skipLoadingOnRefresh: false,
          loading: () => _loading(context, l),
          error: (_, __) => _error(context, l),
          data: (status) => _runtimeRows(l, status.moss),
        ),
        library.when(
          skipLoadingOnRefresh: false,
          loading: () => runtime.isLoading
              ? const SizedBox.shrink()
              : _loading(context, l),
          error: (_, __) =>
              runtime.hasError ? const SizedBox.shrink() : _error(context, l),
          data: (info) => Column(children: [
            DiagnosticsRow(label: l.diagRowLibraryVersion, value: info.version),
            DiagnosticsRow(label: l.diagRowLogPath, value: info.logPath ?? '-'),
          ]),
        ),
        const SizedBox(height: 12),
        Text(l.settingsConnectionDiagnosticsHint,
            style: Theme.of(context).textTheme.bodySmall),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            style: TextButton.styleFrom(
                minimumSize: const Size(0, 44),
                visualDensity: VisualDensity.standard),
            onPressed: loading
                ? null
                : () {
                    ref.invalidate(nativeRuntimeStatusProvider);
                    ref.invalidate(mossLibraryInfoProvider(null));
                  },
            icon: const Icon(Icons.refresh, size: 16),
            label: Text(l.refreshStatus),
          ),
        ),
      ],
    );
  }

  Widget _runtimeRows(AppLocalizations l, MossRuntimeStatus moss) => Column(
        children: [
          DiagnosticsRow(
              label: l.settingsMossAvailability,
              value: moss.available
                  ? l.settingsMossAvailable
                  : l.settingsMossUnavailable),
          DiagnosticsRow(
              label: l.settingsMossLibraryName, value: moss.libraryName),
          DiagnosticsRow(label: l.settingsMossLinkMode, value: moss.linkMode),
        ],
      );

  Widget _loading(BuildContext context, AppLocalizations l) =>
      Text(l.settingsConnectionDiagnosticsLoading,
          style: Theme.of(context).textTheme.bodySmall);

  Widget _error(BuildContext context, AppLocalizations l) => Semantics(
      liveRegion: true,
      child: Text(l.settingsConnectionDiagnosticsError,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.error)));
}
