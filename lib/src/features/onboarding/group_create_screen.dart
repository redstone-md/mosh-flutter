// Group-create step, mirrors the React `GroupCreateStep`
// (src/features/private-dm/NewSessionPanelSteps.tsx). Mirrors the React
// flow: a step frame (OnboardStepFrame) with the group title, a body
// paragraph, an OPTIONAL label input (.step-input), and the Create /
// Recreate button (label flips once an invite exists), plus an
// `InviteResult` card rendered only after a successful create.
//
// Scope (this atomic): the group-create step UI ONLY. The Gateway
// `createGroup` (createPrivateGroup) seam is a LATER slice (Rust
// `private_group_runtime::create_group` exists; the Flutter Gateway
// method is deferred), so the Create button is a NO-OP STUB that shows a
// "later slice" SnackBar -- mirroring the channel-join stub pattern.
// The label is ephemeral to this screen visit (React keeps it as
// per-step `value` state), so the TextEditingController stays
// widget-local and is not lifted to a store until the create seam lands.
//
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/onboarding/invite_result.dart';
import 'package:mosh/src/features/onboarding/onboard_step_frame.dart';
import 'package:mosh/src/routing/app_router.dart';

/// The group-create step screen.
///
/// Reached from the onboarding Group tile (`context.go(AppRoutes.groupCreate)`).
/// Tapping Create is a NO-OP STUB that shows a "later slice" SnackBar (the
/// Gateway `createGroup` seam is deferred). Back returns to the onboarding
/// menu (`AppRoutes.onboarding`). The entered group label is optional and
/// ephemeral to this visit, mirroring React's per-step `value` state.
class GroupCreateScreen extends ConsumerStatefulWidget {
  const GroupCreateScreen({super.key});

  @override
  ConsumerState<GroupCreateScreen> createState() => _GroupCreateScreenState();
}

class _GroupCreateScreenState extends ConsumerState<GroupCreateScreen> {
  late final TextEditingController _labelController;
  // Both stay false this atomic (Create is a no-op stub). A later atomic
  // drops `final` when it wires the real createGroup seam via setState.
  final bool _busy = false;
  final bool _copied = false;
  // The InviteResult branch is dead this atomic (the create seam is
  // deferred, so no invite URI ever exists). The field-backed conditional
  // keeps the React-faithful structure so the next atomic just flips the
  // field to a provider-watched value -- no analyzer dead-code warning.
  final bool _hasInvite = false;

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

  // NO-OP STUB: the Gateway `createGroup` (createPrivateGroup) seam is a
  // later slice. Mirror the channel-join stub so the button is honest
  // about what is and isn't wired yet. The guard mirrors ChatCreateScreen.
  void _onCreate() {
    if (_busy) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.onboardJoinStepBody)),
    );
  }

  // TODO(group-create-seam): wire real clipboard copy when the Gateway
  // createGroup seam lands (mirrors ChatCreateScreen._onCopy). Dead this
  // atomic because the InviteResult branch never renders.
  void _onCopy() {}

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
          // label flips Create/Recreate based on `_hasInvite` (always
          // Create this atomic). NOT disabled by an empty label.
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
                : Text(_hasInvite
                    ? l.onboardGroupRecreate
                    : l.onboardGroupCreate),
          ),
          // Dead branch this atomic (the create seam is deferred, so
          // `_hasInvite` is always false). Kept to document the future
          // wiring so the next atomic plugs in the real create result
          // without restructuring the build tree.
          if (_hasInvite) ...[
            const SizedBox(height: 20),
            InviteResult(
              note: l.onboardGroupInviteReady,
              uri: '',
              copied: _copied,
              onCopy: _onCopy,
            ),
          ],
        ],
      ),
    );
  }
}
