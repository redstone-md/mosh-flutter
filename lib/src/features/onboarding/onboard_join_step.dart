// Embeddable invite-join step body -- 1-to-1 with React OnboardJoinStep
// (src/features/private-dm/NewSessionPanelSteps.tsx). Renders the step
// CONTENT ONLY: the body paragraph, the invite Semantics+TextField
// (aria-label="Invite link" + aria-invalid), the live 3-state detection
// badge, the full-width primary Connect button (disabled until detection is
// valid), the inline accepted-session text, and the inline error. NO frame,
// NO back affordance, NO title -- the caller wraps this in the frame
// (OnboardStepFrame for the full-screen route, OnboardStepBody when the
// desktop chat-pane composes it inline in atomic #8). One step content,
// two frames -- DRY, matching atomic #1/#2 (OnboardStepBody/OnboardMenu)
// and atomic #4/#5/#6 (ChatCreateStep/GroupCreateStep/ChannelJoinStep).
//
// Scope: the invite-join step UI + the acceptInvite/joinGroup/joinOrg Gateway
// seams (slice-3). Live detection re-runs [detectInvite] on every keystroke
// (the ported pure function; detection is NOT re-implemented here). Connect
// is enabled for every detected kind (dm + group + org -- all three have a
// wired Gateway seam). The detection badge is 1-to-1 with React (ok for any
// detected kind, bad for unknown, neutral for empty).
//
// Navigation split (mirrors atomic #6 ChannelJoinStep): the SUCCESS
// navigation stays INSIDE this step -- context.go(AppRoutes.groupFor(id))
// for a group join and context.go(AppRoutes.sessions) for an org join
// (both the route screen and the inline panel land on the same
// destinations). For a DM, the accepted session id is stored inline (no
// navigation; React shows it inline too). Only onBack is injected (1-to-1
// with React props.onBack): the caller decides where Back goes (route
// screen -> AppRoutes.onboarding, inline panel -> back to menu). Hence
// go_router + app_router stay imported here for the success hops.
//
// State split: only the text controller + live detection value + busy/
// acceptedSessionId/error are widget-local (ephemeral UI, like React's
// per-step useState), which is why this is a ConsumerStatefulWidget. The
// displayName/listenPort/staticPeer come from [inviteFlowProvider] (ADR
// 0010 DRY: one settings source for both flows).
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsValidationResult;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/invite/invite_detection.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/rust/private_group_runtime.dart';
import 'package:mosh/src/rust/org_runtime.dart';
import 'package:mosh/src/state/channel_group_providers.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/org_providers.dart';
import 'package:mosh/src/state/session_providers.dart';

/// Embeddable invite-join step body -- the step CONTENT only.
///
/// Renders the body paragraph, the invite Semantics+TextField, the live
/// 3-state detection badge ([_DetectBadge]), the full-width primary Connect
/// button (disabled until detection is valid), the inline accepted-session
/// text, and the inline error. Caller wraps this in [OnboardStepFrame]
/// (full-screen route, e.g. [InvitePasteScreen]) or OnboardStepBody (inline,
/// atomic #8).
///
/// Mirrors React OnboardJoinStep (NewSessionPanelSteps.tsx) which renders
/// its body inside an OnboardStepFrame -- there the frame and content are
/// coupled; here they are split so the same content composes into two frames
/// (route + inline). State stays in this widget (the controller + live
/// detection value + busy/acceptedSessionId/error are ephemeral UI).
///
/// [onBack] is an injected VoidCallback (1-to-1 with React props.onBack)
/// reserved for caller parity -- the step body renders no back affordance
/// itself; the framing widget owns the Back button and wires it to this
/// callback. Unlike atomic #4/#5, this step KEEPS the success navigation
/// inside itself because both the route screen and the inline panel land on
/// the same destinations: group -> context.go(AppRoutes.groupFor(id)),
/// org -> context.go(AppRoutes.sessions), dm -> the accepted session id
/// stored inline (no navigation; React shows it inline too). Only Back
/// routing is delegated to the caller.
///
/// [initialInviteUri] seeds the field on first build (1-to-1 with the
/// deep-link seed -- the /join route passes the mosh:// URI here via
/// state.extra). Null by default, so in-app navigation (no deep link)
/// constructs the step with an empty field. The route wrapper
/// ([InvitePasteScreen]) reads state.extra and forwards it here.
class OnboardJoinStep extends ConsumerStatefulWidget {
  const OnboardJoinStep({super.key, required this.onBack, this.initialInviteUri});

  /// Back-navigation callback (1-to-1 with React props.onBack). The step
  /// body does not render a back affordance itself; the framing widget owns
  /// the Back button and wires it to this callback.
  final VoidCallback onBack;

  /// Optional URI string to pre-fill into the invite field. The S2-3
  /// deep-link intake passes the incoming mosh:// URI here via the /join
  /// route's xtra. Null for in-app navigation (manual paste).
  final String? initialInviteUri;

  @override
  ConsumerState<OnboardJoinStep> createState() => _OnboardJoinStepState();
}

class _OnboardJoinStepState extends ConsumerState<OnboardJoinStep> {
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
    // seed _detection directly here; the badge then matches the seeded
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
    // Dispatch by kind (mirrors React connect): dm -> acceptInvite,
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
        await ref.read(sessionListProvider.notifier).refresh();
        if (mounted) setState(() => _acceptedSessionId = snapshot.sessionId);
      } else if (kind == InviteDetectionKind.group) {
        // Group: join via the Gateway, then navigate to the group screen
        // (1-to-1 with React setActive({type:"group", id}) +
        // setShowSetup(false)). orgPubkey is null -- a paste/deep-link
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
        await ref.read(groupListProvider.notifier).refresh();
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
        await ref.read(orgsProvider.notifier).refresh();
        if (!mounted) return;
        context.go(AppRoutes.sessions);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    // Connect is enabled for every detected kind (dm + group + org -- all
    // three have a wired Gateway seam). _detected already excludes empty
    // + unknown, so this is just the busy guard.
    final ready = _detected && !_busy;
    return Column(
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
       // aria-invalid equivalent is Semantics.validationResult
       // (SemanticsValidationResult.invalid for the unknown kind); the
       // border stays neutral (only the badge reflects the error
       // visually), and the badge's liveRegion also announces the
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
    );
  }
}

/// Live detection status row, 1-to-1 with the React detect-badge
/// (3 states: ok / bad / neutral). Mirrors the React classes:
///   detected (dm|group|org) -> detect-badge-ok  (green/primary + check icon)
///   kind === unknown       -> detect-badge-bad (error/red, no check icon)
///   kind === empty         -> detect-badge     (outline/muted, no check icon)
///
/// Wraps the row in Semantics(liveRegion: true) (the Flutter equivalent of
/// ria-live="polite") and exposes a status role so screen readers announce
/// detection changes. The check icon shows ONLY when detected (React shows
/// IconCheck only in the ok state).
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
