// S4.5: Invite Paste screen. Paste a mosh:// invite URI, detect its kind
// live, and accept it via the Gateway seam. Mirrors the React OnboardJoinStep
// (src/features/private-dm/NewSessionPanelSteps.tsx): step frame title,
// body text, a multiline invite field, a live detection badge, and a
// full-width primary Connect button disabled until detection is valid.
//
// Server/async state lives behind the gatewayProvider seam (ADR 0013);
// cross-screen form state (displayName/listenPort/staticPeer) comes from
// inviteFlowProvider (ADR 0010). Only the text controller + live detection
// value are widget-local, which is why this is a ConsumerStatefulWidget.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/invite/invite_detection.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/session_providers.dart';

/// Screen where a user pastes a mosh:// invite and connects to it.
///
/// Live detection re-runs [detectInvite] on every keystroke (the ported pure
/// function; detection is NOT re-implemented here). The Connect button calls
/// gateway.acceptInvite with the trimmed URI plus the cross-screen form
/// fields from [inviteFlowProvider]. For slice-one the accepted session id
/// is shown inline; full navigation to the DM screen is S4.7's wiring.
///
/// S2-3: an optional [initialInviteUri] seeds the field on first build so a
/// `mosh://` deep link that landed on /join arrives pre-pasted (and live
/// detection runs on it immediately). Null by default, so the existing
/// no-arg widget test and in-app navigation (which construct
/// `InvitePasteScreen()`) keep working unchanged. The /join route builder
/// reads `state.extra` (the raw URI string) and passes it here.
class InvitePasteScreen extends ConsumerStatefulWidget {
  const InvitePasteScreen({super.key, this.initialInviteUri});

  /// Optional URI string to pre-fill into the invite field. The S2-3
  /// deep-link intake passes the incoming `mosh://` URI here via the /join
  /// route's `extra`. Null for in-app navigation (manual paste).
  final String? initialInviteUri;

  @override
  ConsumerState<InvitePasteScreen> createState() => _InvitePasteScreenState();
}

class _InvitePasteScreenState extends ConsumerState<InvitePasteScreen> {
  late final TextEditingController _controller;
  InviteDetection _detection =
      const InviteDetection(kind: InviteDetectionKind.empty);
  bool _busy = false;
  String? _acceptedSessionId;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Seed from the deep-link pre-fill (if any). Setting the controller's
    // initial value in its constructor does NOT notify listeners, so we also
    // seed `_detection` directly here; the badge then matches the seeded
    // text on first paint without waiting for a keystroke. _onChanged keeps
    // it in sync for every subsequent edit.
    _controller = TextEditingController(text: widget.initialInviteUri);
    _detection = detectInvite(widget.initialInviteUri ?? '');
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    final next = detectInvite(_controller.text);
    if (next != _detection) {
      setState(() => _detection = next);
    }
  }

  bool get _detected =>
      _detection.kind == InviteDetectionKind.dm ||
      _detection.kind == InviteDetectionKind.group ||
      _detection.kind == InviteDetectionKind.org;

  String _detectLabel(AppLocalizations l) {
    switch (_detection.kind) {
      case InviteDetectionKind.dm:
        return l.onboardJoinDetectChat;
      case InviteDetectionKind.group:
        return l.onboardJoinDetectGroup;
      case InviteDetectionKind.org:
        return l.onboardJoinDetectOrg;
      case InviteDetectionKind.unknown:
        // Spec S4.5: invalid input surfaces the canonical "bad" message
        // rather than the parser's per-code error string, matching the
        // React badge fallback label.
        return l.onboardJoinDetectBad;
      case InviteDetectionKind.empty:
        return l.onboardJoinDetectNone;
    }
  }

  Future<void> _connect() async {
    if (!_detected || _busy) return;
    final uri = _controller.text.trim();
    final flow = ref.read(inviteFlowProvider);
    setState(() {
      _busy = true;
      _error = null;
      _acceptedSessionId = null;
    });
    try {
      final snapshot = await ref.read(gatewayProvider).acceptInvite(
            request: AcceptInviteRequest(
              inviteUri: uri,
              displayName:
                  flow.displayName.isEmpty ? 'anonymous' : flow.displayName,
              listenPort: flow.listenPort,
              staticPeer: flow.staticPeer,
            ),
          );
      if (mounted) setState(() => _acceptedSessionId = snapshot.sessionId);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final ready = _detected && !_busy;
    return Scaffold(
      appBar: AppBar(title: Text(l.onboardTileJoinTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l.onboardJoinStepBody,
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                maxLines: 4,
                minLines: 2,
                enabled: !_busy,
                decoration: InputDecoration(
                  hintText: l.onboardJoinPlaceholder,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              _DetectBadge(detected: _detected, label: _detectLabel(l)),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: ready ? _connect : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l.onboardJoinConnect),
              ),
              if (_acceptedSessionId != null) ...[
                const SizedBox(height: 16),
                Text('Accepted session: $_acceptedSessionId',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Live detection status row: a check icon (valid) or neutral dot, plus the
/// detection label. Mirrors the React detect-badge (ok/bad/none states).
class _DetectBadge extends StatelessWidget {
  const _DetectBadge({required this.detected, required this.label});

  final bool detected;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = detected ? scheme.primary : scheme.outline;
    return Row(
      children: [
        Icon(
            detected
                ? Icons.check_circle_outline
                : Icons.radio_button_unchecked,
            size: 18,
            color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label,
              style: TextStyle(color: color, fontSize: 14),
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}
