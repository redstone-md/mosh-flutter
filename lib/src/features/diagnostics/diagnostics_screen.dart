// S4.8: Diagnostics screen - app + runtime status (slice-one).
//
// Split path per S4.0: AppDiagnostics via diagnosticsProvider (Gateway seam;
// Fake works); NativeRuntimeStatus via the frb `nativeRuntimeStatus()` called
// DIRECTLY (its 5 sub-structs are opaque, so Fake cannot synthesize them).
// Under `flutter test` RustLib is NOT initialized (main() never runs), so the
// call throws synchronously - we catch that and render an error row.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  late final Future<NativeRuntimeStatus?> _nativeStatus;

  @override
  void initState() {
    super.initState();
    _nativeStatus = _fetchNativeRuntimeStatus();
  }

  // One-shot fetch via the frb binding. try/catch + onError guarantee the
  // future completes when RustLib is not initialized (test env) or Moss absent.
  Future<NativeRuntimeStatus?> _fetchNativeRuntimeStatus() {
    try {
      return nativeRuntimeStatus()
          .then<NativeRuntimeStatus?>((v) => v, onError: (Object _) => null);
    } catch (_) {
      return Future<NativeRuntimeStatus?>.value(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    // TODO(slice-one): add a `diagnosticsDiagnostics` ARB key for the AppBar
    // title. Field values below are raw and intentionally not localized.
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cable_outlined, size: 18),
            SizedBox(width: 8),
            Text('Diagnostics'),
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
                _NativeRuntimeCard(future: _nativeStatus),
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
  const _NativeRuntimeCard({required this.future});
  final Future<NativeRuntimeStatus?> future;

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
        child: FutureBuilder<NativeRuntimeStatus?>(
          future: future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return _spinner;
            }
            if (snap.hasError) {
              return _StatusRow(
                label: 'nativeRuntimeStatus',
                value: 'error: ${snap.error}',
                isError: true,
              );
            }
            final status = snap.data;
            if (status == null) {
              return _StatusRow(
                label: 'nativeRuntimeStatus',
                value: 'unavailable',
                isError: true,
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _StatusRow(
                    label: 'moss.linkMode', value: _describe(status.moss)),
                _StatusRow(
                    label: 'secureStorage.backend',
                    value: _describe(status.secureStorage)),
                _StatusRow(
                    label: 'persistence.backend',
                    value: _describe(status.persistence)),
                _StatusRow(
                    label: 'openmlsSmoke',
                    value: _describe(status.openmlsSmoke)),
                _StatusRow(
                    label: 'openmlsRoundtrip',
                    value: _describe(status.openmlsRoundtrip)),
              ],
            );
          },
        ),
      ),
    );
  }

  // Opaque sub-structs expose no field getters in slice-one's frb bindings;
  // try/catch guards against a getter changing in a future frb regen.
  static String _describe(Object? sub) {
    try {
      if (sub == null) return '<null>';
      return '<opaque: ${sub.runtimeType.toString().split('<').first}>';
    } catch (_) {
      return '<opaque>';
    }
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
