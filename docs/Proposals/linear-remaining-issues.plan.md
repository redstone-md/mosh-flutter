# Remaining Linear issues

Agreed scope: IVO-48, IVO-49, IVO-51 and IVO-52. Video calls are excluded.
The interview decisions below are the implementation specification.

## Message focus: IVO-48

- Remove the white message-row focus outline for mouse and keyboard input.
- Retain focus ownership, menu navigation, copy shortcuts and semantic actions.
- Keep the existing picked-message background and text-selection behavior.

## Invitation format: IVO-49

- Generate compact, self-contained signed DM invitations, approximately 300
  characters with a practical target below 400.
- Preserve both ownership signatures, routing, fingerprint checks and targeted
  admission. Existing invitation URLs and saved records remain readable.
- Show at most two lines in the shared DM/group invitation card; copying always
  copies the full invitation. Device-link invitation formats stay outside scope.

## Ordinary dialogs: IVO-51

- Share a compact Mosh dialog surface, spacing, typography and actions.
- Remove the stretched decorative warning band and raw session IDs in titles.
- Put danger emphasis on the dangerous action.
- Use the transitions.dev modal recipe: 250 ms open, 150 ms close, opacity and
  scale 0.96 to 1, cubic-bezier(0.22, 1, 0.36, 1), honoring reduced motion.
- Backdrop, Escape and close cancel. Simple forms discard unsaved input directly.
- Voice-call windows and fullscreen media viewing remain distinct UI scenarios.

## Invitation lifecycle: IVO-52

- Creating, copying or replacing an invitation does not add a chat-list row.
- Explicit Open chat or authenticated counterpart admission permanently exposes
  the conversation. Repeated opening uses the same conversation.
- New invitations are independent. Replacement affects only its invitation and
  preserves the conversation address and any existing chat-list entry.
- Successful replacement invalidates the old URL. Failed replacement leaves the
  old invitation usable. An admitted counterpart is never displaced.
- Invitations survive navigation and restart, without automatic expiration.
  The first independent counterpart permanently consumes the invitation;
  authorized linked-device admission remains separate.
- The creation screen lists saved unopened invitations compactly, with Copy,
  Replace and Open chat. Create new invitation starts an independent invitation.
- Opened waiting DMs offer Copy and Replace in their menu. Those actions disappear
  once a counterpart is admitted.

## Ownership and integration

- `fix/ivo-48-message-focus`, `/tmp/mosh-ivo48`: message rows, focused tests and
  message-menu/selection documentation.
- `feat/ivo-51-dialogs`, `/tmp/mosh-ivo51`: shared ordinary dialogs, their callers,
  focused tests and the dialog feature document.
- `feat/ivo-49-52-invitations`, `/tmp/mosh-ivo49-52`: native invitation codec and
  lifecycle, Flutter invitation flow/adapters, focused tests and invitation docs.
- The integration owner edits localization resources and architecture/index docs,
  generates bridge bindings, runs every test/build/lint and commits verified work.
  Subagents write tests but do not execute tests, compilation or analysis.

## Risks and checks

- Rotation must reject old admission attempts after restart while retaining the
  same conversation. Persistence refusal must retain the previous usable state.
- List admission and invitation consumption must be durable facts, independent
  of current reachability, peer labels or received unverified packets.
- Preserve ordinary createInvite callers used by authenticated group/org offers.
- Native regression tests use real persistence/MLS; real transport integration
  uses independent installations and the repository's local tracker harness.
- Run Moss preparation before native runtime tests; build Rust before its tests.
- Run Flutter analysis/tests/formatting and Rust formatting/tests/strict Clippy.
- Regenerate bridge bindings after API changes and verify regeneration drift.
- Check changed-code coverage against the repository's line/branch requirements.

## Progress

- [x] Read issues, screenshots, architecture and relevant ADRs.
- [x] Agree on behavior and assign independent worktrees.
- [x] Write focused regression tests and implement changes.
- [x] Integrate localization and generated bridge bindings.
- [x] Review implementation against this specification and repository standards.
- [x] Run required checks, record results and make atomic commits.

Verification and the changed-file list are recorded in
[the implementation report](linear-remaining-issues.validation.md).
