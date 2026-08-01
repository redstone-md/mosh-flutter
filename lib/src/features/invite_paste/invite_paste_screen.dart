// S4.5: Invite Paste screen. Paste a mosh:// invite URI, detect its kind
// live, and accept it via the Gateway seam. Mirrors the React OnboardJoinStep
// (src/features/private-dm/NewSessionPanelSteps.tsx): a shared
// OnboardStepFrame (back button + h1 title + body), a multiline invite
// field, a live 3-state detection badge (ok / bad / neutral), and a
// full-width primary Connect button disabled until detection is valid.
//
// Visual shell: the screen composes the shared OnboardStepFrame (extracted
// for the chat-create step) instead of its own Scaffold + AppBar, 1-в-1
// with React OnboardJoinStep. A thin Scaffold wraps the frame only for
// SafeArea + theming; the AppBar is gone (the frame's Back button
// replaces it).
//
// Known temporary divergence from React: the React `connect` dispatches by
// kind (dm -> onAccept, group -> onJoinGroup, org -> onJoinOrg). The
// Flutter Gateway has ONLY `acceptInvite` (DM). So in this atomic Connect
// is DM-only: it calls `acceptInvite` when `kind === dm`, and the Connect
// button is DISABLED for group/org detections. Group/org join needs
// Gateway `joinGroup`/`joinOrg` methods that do not exist yet (deferred).
// The detection badge itself is 1-в-1 with React (ok for any detected
// kind, bad for unknown, neutral for empty).
//
// Server/async state lives behind the gatewayProvider seam (ADR 0013);
// cross-screen form state (displayName/listenPort/staticPeer) comes from
// inviteFlowProvider (ADR 0010). Only the text controller + live detection
// value are widget-local, which is why this is a ConsumerStatefulWidget.
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsValidationResult;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/onboarding/onboard_step_frame.dart';
import 'package:mosh/src/invite/invite_detection.dart';
import 'package:mosh/src/routing/app_router.dart';
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
    // DM-only this atomic (see file header): group/org join needs Gateway
    // joinGroup/joinOrg methods that do not exist yet (deferred). The
    // Connect button is gated to dm below, so this guard is a backstop.
    if (_detection.kind != InviteDetectionKind.dm || _busy) return;
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

  void _onBack() => context.go(AppRoutes.onboarding);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    // DM-only ready (see file header): group/org join is deferred until the
    // Gateway grows joinGroup/joinOrg. React enables Connect for every
    // detected kind; Flutter enables it for DM only for now.
    final ready = _detected &&
        _detection.kind == InviteDetectionKind.dm &&
        !_busy;
    return Scaffold(
      body: SafeArea(
        child: OnboardStepFrame(
          title: l.onboardTileJoinTitle,
          onBack: _onBack,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l.onboardJoinStepBody,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
              ),
              const SizedBox(height: 16),
             // aria-label="Invite link" + aria-invalid={kind === "unknown"}
             // (React). The literal 'Invite link' is non-localized, matching
             // React's literal aria-label (not in onboardText). The
             // aria-invalid equivalent is `Semantics.validationResult`
             // (SemanticsValidationResult.invalid for the unknown kind); the
             // border stays neutral (only the badge reflects the error
             // visually), and the badge's `liveRegion` also announces the
             // error to assistive tech (the polite announcement matches
             // React's aria-live intent).
             Semantics(
               textField: true,
               label: 'Invite link',
               validationResult: _detection.kind == InviteDetectionKind.unknown
                   ? SemanticsValidationResult.invalid
                   : SemanticsValidationResult.none,
               child: TextField(
                  controller: _controller,
                  maxLines: 4,
                  minLines: 2,
                  enabled: !_busy,
                  decoration: InputDecoration(
                    hintText: l.onboardJoinPlaceholder,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _DetectBadge(
                kind: _detection.kind,
                detected: _detected,
                label: _detectLabel(l),
              ),
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
                    style: theme.textTheme.bodySmall),
              ],
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Live detection status row, 1-в-1 with the React `detect-badge`
/// (3 states: ok / bad / neutral). Mirrors the React classes:
///   detected (dm|group|org) -> detect-badge-ok  (green/primary + check icon)
///   kind === unknown       -> detect-badge-bad (error/red, no check icon)
///   kind === empty          -> detect-badge     (outline/muted, no check icon)
///
/// Wraps the row in `Semantics(liveRegion: true)` (the Flutter equivalent of
/// `aria-live="polite"`) and exposes a status role so screen readers announce
/// detection changes. The check icon shows ONLY when detected (React shows
/// `IconCheck` only in the ok state).
class _DetectBadge extends StatelessWidget {
  const _DetectBadge({
    required this.kind,
    required this.detected,
    required this.label,
  });

  final InviteDetectionKind kind;
  final bool detected;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isBad = kind == InviteDetectionKind.unknown;
    final color = detected
        ? scheme.primary
        : isBad
            ? scheme.error
            : scheme.outline;
    return Semantics(
      liveRegion: true,
      child: Row(
        children: [
          if (detected) ...[
            Icon(Icons.check, size: 16, color: color),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: color, fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
