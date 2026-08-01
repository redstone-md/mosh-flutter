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
// Mirrors the React `connect` dispatch by kind: dm -> acceptInvite, group
// -> joinGroup, org -> joinOrg (all three slice-3 seams wired). Connect is
// enabled for every detected kind. The detection badge itself is 1-в-1
// with React (ok for any detected kind, bad for unknown, neutral for empty).
//
// Server/async state lives behind the gatewayProvider seam (ADR 0013);
// cross-screen form state (displayName/listenPort/staticPeer) comes from
// inviteFlowProvider (ADR 0010). joinGroup passes the invite URI verbatim
// (the runtime parses it), like React's `joinPrivateGroup({invite_uri});
// joinOrg passes the `mosh://org` bundle URI verbatim (org joins use a
// `bundleUri` field, not `inviteUri`). Only the text controller + live
// detection value are widget-local, which is why this is a
// ConsumerStatefulWidget.
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
import 'package:mosh/src/rust/private_group_runtime.dart';
import 'package:mosh/src/rust/org_runtime.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/session_providers.dart';

/// Screen where a user pastes a mosh:// invite and connects to it.
///
/// Live detection re-runs [detectInvite] on every keystroke (the ported pure
/// function; detection is NOT re-implemented here). The Connect button calls
/// the kind-appropriate Gateway method: `gateway.acceptInvite` for a DM
/// (the accepted session id is shown inline), `gateway.joinGroup` for a
/// group (navigates to the group screen, 1-в-1 with React's
/// `setActive({type:"group", id})`), or `gateway.joinOrg` for an org
/// (navigates to the sessions list -- orgs are a container, not a chat,
/// so React's `setShowSetup(false)` + `refreshOrgs` lands the user back on
/// the rail). All three carry the trimmed URI plus the cross-screen form
/// fields from [inviteFlowProvider].
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
    // Dispatch by kind (mirrors React `connect`): dm -> acceptInvite,
    // group -> joinGroup, org -> joinOrg (all three slice-3 seams wired).
    if (_busy) return;
    final kind = _detection.kind;
    if (kind == InviteDetectionKind.empty ||
        kind == InviteDetectionKind.unknown) {
      return;
    }
    final uri = _controller.text.trim();
    final flow = ref.read(inviteFlowProvider);
    final displayName =
        flow.displayName.isEmpty ? 'anonymous' : flow.displayName;
    setState(() {
      _busy = true;
      _error = null;
      _acceptedSessionId = null;
    });
    try {
      if (kind == InviteDetectionKind.dm) {
        final snapshot = await ref.read(gatewayProvider).acceptInvite(
              request: AcceptInviteRequest(
                inviteUri: uri,
                displayName: displayName,
                listenPort: flow.listenPort,
                staticPeer: flow.staticPeer,
              ),
            );
        if (mounted) setState(() => _acceptedSessionId = snapshot.sessionId);
      } else if (kind == InviteDetectionKind.group) {
        // Group: join via the Gateway, then navigate to the group screen
        // (1-в-1 with React `setActive({type:"group", id})` +
        // `setShowSetup(false)`). orgPubkey is null -- a paste/deep-link
        // join is a direct group invite, not an org group-offer.
        final snapshot = await ref.read(gatewayProvider).joinGroup(
              request: JoinGroupRequest(
                inviteUri: uri,
                displayName: displayName,
                orgPubkey: null,
                listenPort: flow.listenPort,
                staticPeer: flow.staticPeer,
              ),
            );
        if (!mounted) return;
        context.go(AppRoutes.groupFor(snapshot.groupId));
      } else {
        // Org: join via the Gateway. React's joinOrg does NOT navigate to a
        // dedicated org screen (orgs are a container, not a chat) -- it
        // leaves setup + refreshes the orgs list, so the user lands back on
        // the rail. Flutter has no org screen yet, so navigate to the
        // sessions list (mirrors how leaveChannel/closeGroup return there).
        await ref.read(gatewayProvider).joinOrg(
              request: JoinOrgRequest(
                bundleUri: uri,
                displayName: displayName,
                listenPort: flow.listenPort,
                staticPeer: flow.staticPeer,
              ),
            );
        if (!mounted) return;
        context.go(AppRoutes.sessions);
      }
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
    // Connect is enabled for every detected kind (dm + group + org -- all
    // three have a wired Gateway seam). `_detected` already excludes empty
    // + unknown, so this is just the busy guard.
    final ready = _detected && !_busy;
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
