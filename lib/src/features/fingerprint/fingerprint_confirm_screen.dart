// S4.6: Fingerprint confirmation gate (slice-one).
//
// Mirrors src/features/private-dm/ActiveChatHeader.tsx -> FingerprintBadge and
// the invite confirm surface from private-dm.content.ts. The local user reads
// the peer MLS fingerprint out-of-band, then taps Confirm to unlock messaging.
//
// SLICE-ONE SIMPLIFICATION: the confirmed flag lives in this widget's State,
// NOT in the runtime. FakeGateway (S4) does not model MLS confirmation, and the
// real confirmation transition is an S5 concern of RealBridgeGateway. Once S5
// lands a confirmFingerprint gateway method, replace this StatefulWidget with
// a mutation call (mirroring inviteFlowProvider.create) and read the confirmed
// flag back from the SessionSnapshot. The visual surface stays stable.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/state/session_providers.dart';

/// Shows the peer fingerprint, a verify-out-of-band hint, the E2EE crypto
/// notice, and a Confirm button that flips to a disabled "confirmed" state.
///
/// Consumes `activeSessionProvider(sessionId)` (server state, ADR 0010) and
/// holds the ephemeral confirmation flag in widget state (ADR 0010 allows
/// widget-local ephemeral UI state).
class FingerprintConfirmScreen extends ConsumerStatefulWidget {
  const FingerprintConfirmScreen({required this.sessionId, super.key});

  final String sessionId;

  @override
  ConsumerState<FingerprintConfirmScreen> createState() =>
      _FingerprintConfirmScreenState();
}

class _FingerprintConfirmScreenState
    extends ConsumerState<FingerprintConfirmScreen> {
  // Slice-one local flag; see file header for the S5 replacement plan.
  bool _confirmed = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final async = ref.watch(activeSessionProvider(widget.sessionId));

    return Scaffold(
      appBar: AppBar(title: Text(l.inviteFingerprintLabel)),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) =>
            Center(child: Text('${l.inviteFingerprintLabel}: $err')),
        data: (snapshot) => _Body(
          fingerprint: snapshot.fingerprint,
          confirmed: _confirmed,
          onConfirm: () => setState(() => _confirmed = true),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.fingerprint,
    required this.confirmed,
    required this.onConfirm,
  });

  final String fingerprint;
  final bool confirmed;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.inviteFingerprintLabel, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          // Fingerprint displayed prominently in monospace (mirrors the React
          // <code> block in ActiveChatHeader's FingerprintBadge).
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              fingerprint,
              style: theme.textTheme.titleLarge?.copyWith(
                fontFamily: 'monospace',
                letterSpacing: 2,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(l.inviteFingerprintHint, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 24),
          const _CryptoNotice(),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: confirmed ? null : onConfirm,
            icon: Icon(confirmed ? Icons.verified : Icons.shield),
            label: Text(
              confirmed ? l.inviteConfirmedButton : l.inviteConfirmButton,
            ),
          ),
        ],
      ),
    );
  }
}

class _CryptoNotice extends StatelessWidget {
  const _CryptoNotice();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lock, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(l.cryptoNoticeTitle, style: theme.textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 8),
          Text(l.cryptoNoticeBody, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
