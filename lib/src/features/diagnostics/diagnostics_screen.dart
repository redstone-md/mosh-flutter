// S4.8: Diagnostics screen - app + runtime status (slice-one).
//
// Both rows flow through the Gateway seam (ADR 0013): AppDiagnostics via
// `diagnosticsProvider` and NativeRuntimeStatus via `nativeRuntimeStatusProvider`.
// The five `NativeRuntimeStatus` sub-structs are non-opaque across
// flutter_rust_bridge, so the card reads real field values under both
// `FakeGateway` (tests) and `RealBridgeGateway` (S5) - no `<opaque>` fallback.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/rust/api/diagnostics.dart';
import 'package:mosh/src/state/session_providers.dart';

// Compact loading indicator shared by the app + native cards.
const _spinner = Padding(
  padding: EdgeInsets.symmetric(vertical: 8),
  child: Center(
    child: SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(strokeWidth: 2),
    ),
  ),
);

class DiagnosticsScreen extends ConsumerStatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  ConsumerState<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends ConsumerState<DiagnosticsScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context)!;
    final nativeRuntime = ref.watch(nativeRuntimeStatusProvider);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cable_outlined, size: 18),
            SizedBox(width: 8),
            Text(l.diagnosticsDiagnostics),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _heading(theme, 'App'),
                const SizedBox(height: 8),
                _AppDiagnosticsCard(ref: ref),
                const SizedBox(height: 24),
                _heading(theme, 'Native runtime'),
                const SizedBox(height: 8),
                _NativeRuntimeCard(async: nativeRuntime),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _heading(ThemeData theme, String label) => Text(
        label.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 1.3,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
}

class _AppDiagnosticsCard extends StatelessWidget {
  const _AppDiagnosticsCard({required this.ref});
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(diagnosticsProvider);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: async.when(
          loading: () => _spinner,
          error: (err, _) => _StatusRow(
            label: 'appDiagnostics',
            value: 'error: $err',
            isError: true,
          ),
          data: (d) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StatusRow(label: 'appName', value: d.appName),
              _StatusRow(label: 'privacyModel', value: d.privacyModel),
              _StatusRow(label: 'discoveryModel', value: d.discoveryModel),
              _StatusRow(label: 'mossLinkMode', value: d.mossLinkMode),
            ],
          ),
        ),
      ),
    );
  }
}

class _NativeRuntimeCard extends StatelessWidget {
  const _NativeRuntimeCard({required this.async});
  final AsyncValue<NativeRuntimeStatus> async;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: async.when(
          loading: () => _spinner,
          error: (err, _) => _StatusRow(
            label: 'nativeRuntimeStatus',
            value: 'error: $err',
            isError: true,
          ),
          data: (status) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StatusRow(label: 'moss.linkMode', value: status.moss.linkMode),
              _StatusRow(
                  label: 'moss.available',
                  value: status.moss.available ? 'true' : 'false'),
              _StatusRow(
                  label: 'moss.libraryName', value: status.moss.libraryName),
              _StatusRow(
                  label: 'secureStorage.backend',
                  value: status.secureStorage.backend),
              _StatusRow(
                  label: 'secureStorage.available',
                  value: status.secureStorage.available ? 'true' : 'false'),
              _StatusRow(
                  label: 'persistence.backend',
                  value: status.persistence.backend),
              _StatusRow(
                  label: 'persistence.available',
                  value: status.persistence.available ? 'true' : 'false'),
              _StatusRow(
                  label: 'openmlsSmoke',
                  value: _describeOpenMlsResult(
                    status.openmlsSmoke.error,
                    () {
                      final ok = status.openmlsSmoke.ok;
                      if (ok == null) return null;
                      return 'provider=${ok.provider}, '
                          'ciphersuite=${ok.ciphersuite}, '
                          'protectedMessageCreated=${ok.protectedMessageCreated}';
                    }(),
                  )),
              _StatusRow(
                  label: 'openmlsRoundtrip',
                  value: _describeOpenMlsResult(
                    status.openmlsRoundtrip.error,
                    () {
                      final ok = status.openmlsRoundtrip.ok;
                      if (ok == null) return null;
                      return 'provider=${ok.provider}, '
                          'ciphersuite=${ok.ciphersuite}, '
                          'welcomeJoined=${ok.welcomeJoined}, '
                          'plaintextRoundtrip=${ok.plaintextRoundtrip}';
                    }(),
                  )),
            ],
          ),
        ),
      ),
    );
  }

  // The OpenMLS fields are flattened into non-opaque `OpenMls*RuntimeStatus`
  // wrappers (`ok` carries the success snapshot, `error` carries the failure
  // message). Render the snapshot's real fields when the test passed, the failure
  // message when it did not, and `unavailable` if neither is set.
  static String _describeOpenMlsResult(String? error, String? okDescription) {
    if (error != null) return 'error: $error';
    if (okDescription != null) return 'ok: $okDescription';
    return 'unavailable';
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow(
      {required this.label, required this.value, this.isError = false});
  final String label;
  final String value;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valueStyle = theme.textTheme.bodySmall?.copyWith(
      color:
          isError ? theme.colorScheme.error : theme.textTheme.bodySmall?.color,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 7,
            child: Text(value, style: valueStyle),
          ),
        ],
      ),
    );
  }
}
