// Group-create step, mirrors the React `GroupCreateStep`
// (src/features/private-dm/NewSessionPanelSteps.tsx). Mirrors the React
// flow: a step frame (OnboardStepFrame) with the group title, a body
// paragraph, an OPTIONAL label input (.step-input), and the Create /
// Recreate button (label flips once an invite exists), plus an
// `InviteResult` card rendered only after a successful create.
//
// Scope: the group-create step UI + the createGroup Gateway seam (slice-3).
// Tapping Create calls `gateway.createGroup` with a CreateGroupRequest built
// from the entered label + the displayName/listenPort/staticPeer that
// [inviteFlowProvider] already sources for createInvite (ADR 0010 DRY: one
// settings source for both flows), copies the returned invite URI to the
// clipboard (mirrors React `copyText(created.invite_uri)`), and stays on this
// step to show the InviteResult card (React `setShowSetup(true)` -- the user
// shares the invite before navigating away). The label is ephemeral to this
// screen visit (React keeps it as per-step `value` state), so the
// TextEditingController + the GroupCreated result stay widget-local and are
// not lifted to a store.
//
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/onboarding/inline_error.dart';
import 'package:mosh/src/features/onboarding/invite_result.dart';
import 'package:mosh/src/features/onboarding/onboard_step_frame.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/rust/private_group_runtime.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/session_providers.dart' show inviteFlowProvider;
import 'package:mosh/src/util/format.dart' show readableError;

/// The group-create step screen.
///
/// Reached from the onboarding Group tile (`context.go(AppRoutes.groupCreate)`).
/// Tapping Create calls `gateway.createGroup`, copies the returned invite URI
/// to the clipboard, and renders the InviteResult card on this step. Back
/// returns to the onboarding menu (`AppRoutes.onboarding`). The entered group
/// label is optional and ephemeral to this visit, mirroring React's per-step
/// `value` state.
class GroupCreateScreen extends ConsumerStatefulWidget {
  const GroupCreateScreen({super.key});

  @override
  ConsumerState<GroupCreateScreen> createState() => _GroupCreateScreenState();
}

class _GroupCreateScreenState extends ConsumerState<GroupCreateScreen> {
  late final TextEditingController _labelController;
  bool _busy = false;
  bool _copied = false;
  // Persistent inline error (parity with React's `props.error` on
  // NewSessionPanel -- stays until the next create attempt). Cleared at
  // the START of the next create below.
  String? _error;
  // The GroupCreated from the last successful create (null until the first
  // create). Kept widget-local -- React's `groupCreateState` lives in
  // `usePrivateDmSetup` per-step state, not the DM inviteFlowProvider, so
  // this mirrors that separation (ADR 0010 widget-local state for
  // per-step UI state).
  GroupCreated? _created;

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(text: '');
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  void _onBack() => context.go(AppRoutes.onboarding);

  // Calls gateway.createGroup with a CreateGroupRequest built from the
  // entered label (trimmed, null if empty -- React `label.trim() || null`)
  // + inviteFlowProvider's displayName/listenPort/staticPeer (the same
  // settings source createInvite uses, ADR 0010), copies the returned invite
  // URI to the clipboard (React `copyText(created.invite_uri)`), and stores
  // the GroupCreated so the InviteResult branch renders. Stays on this step
  // (React `setShowSetup(true)` -- the user shares the invite before
  // navigating away). Mirrors ChatCreateScreen's busy + reset-copied +
  // try/finally pattern.
  Future<void> _onCreate() async {
    if (_busy) return;
    final label = _labelController.text.trim();
    final settings = ref.read(inviteFlowProvider);
    setState(() {
      _busy = true;
      _copied = false;
      _error = null;
    });
    try {
      final created = await ref.read(gatewayProvider).createGroup(
            request: CreateGroupRequest(
              label: label.isEmpty ? null : label,
              displayName: settings.displayName,
              listenPort: settings.listenPort,
              staticPeer: settings.staticPeer,
            ),
          );
      await Clipboard.setData(ClipboardData(text: created.inviteUri));
      if (!mounted) return;
      setState(() {
        _created = created;
        _copied = true;
      });
    } catch (e) {
      // Mirrors React's parent try/catch feeding `props.error` down: React
      // stores `readableError(err)` (the bare message) in state, so this
      // uses the same helper. No transient SnackBar -- the inline error is
      // the one source of truth AND is announced to assistive tech via the
      // live region.
      if (mounted) setState(() => _error = readableError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // Re-copies the stored invite URI and flips the "Copied" badge (mirrors
  // ChatCreateScreen._onCopy). Only reachable when `_created != null`.
  Future<void> _onCopy() async {
    final created = _created;
    if (created == null) return;
    await Clipboard.setData(ClipboardData(text: created.inviteUri));
    if (mounted) setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return OnboardStepFrame(
      title: l.onboardTileGroupTitle,
      onBack: _onBack,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // .step-body: 12.5px, 1.6 line-height, fg-3 (onSurfaceVariant).
          Text(
            l.onboardGroupStepBody,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 12.5,
              height: 1.6,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          // .step-input: rounded bordered TextField, 12.5px text. The
          // label is OPTIONAL in React (Create is `disabled={busy}` only),
          // so the input stays enabled regardless of whether text exists.
          TextField(
            controller: _labelController,
            decoration: InputDecoration(
              hintText: l.onboardGroupNamePlaceholder,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            style: const TextStyle(fontSize: 12.5),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _onCreate(),
          ),
          const SizedBox(height: 20),
          // .btn.btn-primary.btn-block: full-width primary (mirrors
          // ChatCreateScreen's FilledButton with minimumSize 48h). The
          // label flips Create/Recreate based on `_created` (null = first
          // create). NOT disabled by an empty label (React `disabled={busy}`
          // only).
          FilledButton(
            onPressed: _busy ? null : _onCreate,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_created != null
                    ? l.onboardGroupRecreate
                    : l.onboardGroupCreate),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            InlineError(message: _error),
          ],
          // Renders only after a successful create (`_created != null`).
          // Mirrors React's GroupCreateStep InviteResult card; the URI is
          // auto-copied on create and re-copyable via `_onCopy`.
          if (_created != null) ...[
            const SizedBox(height: 20),
            InviteResult(
              note: l.onboardGroupInviteReady,
              uri: _created!.inviteUri,
              copied: _copied,
              onCopy: _onCopy,
            ),
          ],
        ],
      ),
    );
  }
}
