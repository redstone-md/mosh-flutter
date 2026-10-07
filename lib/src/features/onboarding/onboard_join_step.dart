import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsValidationResult;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/onboarding/inline_error.dart';
import 'package:mosh/src/features/shared/conversation_action_error.dart';
import 'package:mosh/src/invite/invite_detection.dart';
import 'package:mosh/src/invite/invite_uri.dart' show parseMoshGroupInvite;
import 'package:mosh/src/features/onboarding/join_preview.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/rust/private_group_runtime.dart';
import 'package:mosh/src/rust/org_runtime.dart';
import 'package:mosh/src/gateway/conversation_target.dart'
    show ConversationKind;
import 'package:mosh/src/state/conversation_providers.dart'
    show conversationListProvider;
import 'package:mosh/src/state/gateway_provider.dart' show bridgeFacadeProvider;
import 'package:mosh/src/state/org_providers.dart';
import 'package:mosh/src/state/session_providers.dart';

class OnboardJoinStep extends ConsumerStatefulWidget {
  const OnboardJoinStep({
    super.key,
    this.initialInviteUri,
  });

  /// Seeds the input for a deep link; null leaves manual paste empty.
  final String? initialInviteUri;

  @override
  ConsumerState<OnboardJoinStep> createState() => _OnboardJoinStepState();
}

class _OnboardJoinStepState extends ConsumerState<OnboardJoinStep> {
  late final TextEditingController _controller;
  InviteDetection _detection = const InviteDetection(
    kind: InviteDetectionKind.empty,
  );
  bool _busy = false;
  ConversationActionError? _error;

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
    _name = _linkName();
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
    if (next == _detection && _linkName(next) == _name) return;
    setState(() {
      _detection = next;
      _name = _linkName();
    });
  }

  // Detected = any of the three wired kinds (empty + unknown are not).
  static const _detectedKinds = {
    InviteDetectionKind.dm,
    InviteDetectionKind.group,
    InviteDetectionKind.org,
  };
  bool get _detected => _detectedKinds.contains(_detection.kind);

  // Spec S4.5: invalid input surfaces the canonical "bad" message rather
  // than the parser's per-code error string.
  String _detectLabel(AppLocalizations l) => switch (_detection.kind) {
        InviteDetectionKind.dm => l.onboardJoinDetectChat,
        InviteDetectionKind.group => l.onboardJoinDetectGroup,
        InviteDetectionKind.org => l.onboardJoinDetectOrg,
        InviteDetectionKind.unknown => l.onboardJoinDetectBad,
        InviteDetectionKind.empty => l.onboardJoinDetectNone,
      };

  Future<void> _connect() async {
    if (_busy) return;
    final kind = _detection.kind;
    if (!_detectedKinds.contains(kind)) return;
    final uri = _controller.text.trim();
    final flow = ref.read(inviteFlowProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final destination = await switch (kind) {
        InviteDetectionKind.dm => _acceptDm(uri, flow),
        InviteDetectionKind.group => _joinGroup(uri, flow),
        InviteDetectionKind.org => _joinOrg(uri, flow),
        // Unreachable: _detectedKinds filtered these above.
        InviteDetectionKind.empty ||
        InviteDetectionKind.unknown =>
          Future.value(''),
      };
      if (!mounted) return;
      context.go(destination);
    } catch (e) {
      if (mounted) setState(() => _error = ConversationActionError.of(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String> _acceptDm(String uri, InviteFlowState flow) async {
    final snapshot = await ref.read(bridgeFacadeProvider).acceptInvite(
          request: AcceptInviteRequest(
            inviteUri: uri,
            displayName: flow.senderDisplayName,
            listenPort: flow.listenPort,
            staticPeer: flow.staticPeer,
          ),
        );
    await ref
        .read(conversationListProvider(ConversationKind.dm).notifier)
        .refresh();
    return AppRoutes.dmFor(snapshot.sessionId);
  }

  Future<String> _joinGroup(String uri, InviteFlowState flow) async {
    // orgPubkey is null -- a paste/deep-link join is a direct group
    // invite, not an org group-offer.
    final snapshot = await ref.read(bridgeFacadeProvider).joinGroup(
          request: JoinGroupRequest(
            inviteUri: uri,
            displayName: flow.senderDisplayName,
            orgPubkey: null,
            listenPort: flow.listenPort,
            staticPeer: flow.staticPeer,
          ),
        );
    await ref
        .read(conversationListProvider(ConversationKind.group).notifier)
        .refresh();
    return AppRoutes.groupFor(snapshot.groupId);
  }

  // Orgs are a container, not a chat; there is no dedicated org screen
  // yet, so land on the sessions list (where leaving a channel or group
  // also returns).
  Future<String> _joinOrg(String uri, InviteFlowState flow) async {
    await ref.read(bridgeFacadeProvider).joinOrg(
          request: JoinOrgRequest(
            bundleUri: uri,
            displayName: flow.senderDisplayName,
            listenPort: flow.listenPort,
            staticPeer: flow.staticPeer,
          ),
        );
    await ref.read(orgsProvider.notifier).refresh();
    return AppRoutes.sessions;
  }

  /// The name the link carries, for a group or an organization. Two
  /// links of one kind can differ only in it, so it is tracked apart.
  String? _name;

  String? _linkName([InviteDetection? detection]) {
    final text = _controller.text.trim();
    try {
      return switch ((detection ?? _detection).kind) {
        InviteDetectionKind.group => parseMoshGroupInvite(text).label,
        InviteDetectionKind.org => Uri.parse(text).queryParameters['name'],
        _ => null,
      };
    } on Object {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    // _detected already excludes empty + unknown, so this is just the
    // busy guard.
    final ready = _detected && !_busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Invalid input is flagged to assistive tech here and announced by
        // the preview's live region; the border stays neutral.
        Semantics(
          validationResult: _detection.kind == InviteDetectionKind.unknown
              ? SemanticsValidationResult.invalid
              : SemanticsValidationResult.none,
          child: TextField(
            controller: _controller,
            maxLines: 4,
            minLines: 1,
            enabled: !_busy,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: InputDecoration(
              labelText: l.onboardInviteLinkLabel,
              hintText: l.onboardJoinPlaceholder,
              prefixIcon: const Icon(Icons.link, size: 20),
            ),
          ),
        ),
        const SizedBox(height: 14),
        JoinPreview(
          kind: _detection.kind,
          title: _detectLabel(l),
          name: _name,
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: ready ? _connect : null,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: _busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l.onboardJoinConnect),
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          InlineError(message: _error?.describe(l)),
        ],
      ],
    );
  }
}
