# Group history: current-administrator supplements

Date: 2026-10-26. Policy selected by the user: a current administrator confirms
disputed historical records; retain the original author's signature and allow
other holders to relay retained endorsements while that administrator is offline.
**Exact wire, schema, bridge and review UI below still require approval.**
Scope: [IVO-142](https://linear.app/ivoxygen/issue/IVO-142),
[IVO-143](https://linear.app/ivoxygen/issue/IVO-143); shared bounds/importer in
[the history contract](android-history-contracts.plan.md) remain applicable.
No runtime, dependency, Moss source or database is changed by this proposal.

## Meaning and trust boundary

An endorsement says: “I, a currently authorized group administrator, approve
this exact original-signed record as historical content of the stated membership
interval, for this recipient's proven entitlement.” It does not turn the admin
into the author, verify the wall-clock creation time, or prove the record was
created before removal independently of that administrator's assertion.

This preserves full recovery when authorized original copies and sufficient
evidence are available, including genuine rows the administrator did not receive
live. It does not impose closing roots or delay removal until offline holders
answer. Missing evidence is retried/reviewed, not silently excluded as a chosen
strict-root policy. A dishonest administrator can endorse a backdated assertion;
that is the selected trust cost, not a solved cryptographic timestamp problem.

A holder's signed Page, ordinary member's receipt, role label, old roster,
or claim that another device accepted a row is not an endorsement. Current
admin approval is a separate signed object with the following exact scope.

## Canonical objects

All objects reuse common canonical tuples, complete keys, SHA-256 and bounded
fragments; integers are checked u64, not allocation instructions. Encode hashes
and Ed25519 keys/signatures in lowercase hex. No private material is included.

`RecordBindingV1` is the fixed tuple:

`(conversation, mesh_id, occurrence_key, native_message_id, kind,
content_hash, origin_hash, history_content_proof_hash_or_null,
original_author_mls_key, original_author_moss_key_or_null,
claimed_sent_at_ms, claimed_display_label)`.

`content_hash` hashes canonical Text or the complete AttachmentOffer with its
original/preview manifests. `origin_hash` hashes all original MessageOrigin
fields including its signature and ownership certificate, encoded in fixed
order. The origin must verify against the original bytes, exact conversation,
occurrence ID and original MLS key. Never sign the holder's local display name,
receipt state, downloaded path or other mutable presentation as original data.
The record hash is SHA-256 of `mosh-history-record-binding-v1\0` plus that tuple.
An existing erasure slot retains this original binding hash; it carries verified
deletion evidence instead of reconstructing content to obtain the hash.

An absent original-author signature is **not** repaired by an endorsement.
An old valid MessageOrigin without HistoryContentProof remains a content-only
original signature; the admin supplies the asserted interval/time association.
Preserve that distinction in stored provenance. A supplied invalid original
proof is rejected rather than dropped to a weaker classification.

`HistoryEndorsementV1` contains:

| Field | Exact binding |
| --- | --- |
| `version`, `endorsement_id` | 1, fresh 128-bit random identifier |
| `conversation`, `mesh_id`, `org_pubkey` | Exact group scope; org null only for plain group |
| `record_hash`, `origin_hash` | Exact RecordBinding and complete original origin |
| `claimed_context` | Historical epoch plus verified GroupContext hash |
| `author_admission` | Original author full MLS key and admission-instance hash |
| `recipient_current` | Full current recipient MLS/Moss keys and current admission instance |
| `recipient_entitled` | Exact historical admission instance and epoch/context containing this record |
| `authority_head` | Issuance epoch/GroupContext hash and authority-state digest |
| `issuer_mls_key`, `issuer_moss_key` | Complete signing keys, both proven |
| `basis` | `protected_live_acceptance` or `explicit_administrator_review` |
| `signatures` | Ed25519 signatures by both issuer keys over the same canonical tuple |

The signed tuple lists the above fields in table order, excluding signatures;
domain is `mosh-group-history-endorsement-v1\0`. Its digest covers the complete
signed tuple and both signatures. No generic wildcard record, conversation,
recipient, account or “all old messages” grant is permitted. Attach at most
one selected endorsement per record/recipient in an exported page; retain other
valid endorsements separately so an issuer change does not rewrite the author.

`authority_state_digest` binds the verified full-key plain-admin state or the
complete signed org-roster version/hash plus verified current MLS membership.
It is a branch identifier, not proof the signer's role was current at an
unverifiable wall-clock time. Acceptance always checks actual current authority.

## Admission instances and entitlement

Admission instance is SHA-256 of a versioned tuple containing MLS group ID,
canonical Add/replace commit hash and the admitted full MLS key. Genesis uses
the locally pinned initial GroupContext hash and creator key instead of an Add.
Retain the actual authenticated membership transition and original authority,
not a sender-provided epoch number or abbreviated fingerprint.

Record context must fall inside both author and entitled-recipient membership
instances verified on the receiver's accepted branch. Intervals are half-open
`[admission_epoch, removal_epoch)`, or open-ended until a known removal. Unknown
removal does not mean proof of global freshness. New admission cannot use an
endorsement for someone else's or a preceding instance's interval. Ordinary
offline does not close an instance. A new member receives from its admission;
an actually removed current recipient receives no new exports.

For rejoin, `recipient_current` names the new instance. Earlier eligible history
may be granted only where verified retained identity bindings demonstrate that
the old and new entitled instances belong to the same recipient Moss key.
A new dual-key proof proves the current leaf's possession of that Moss key;
retained original dual-key/admission evidence binds the old instance. A name,
account label or copied local-acceptance flag is not such a binding. No grant
covers the nonmember interval. No grant is silently retargeted to a newly linked
installation with a different membership instance; it needs its own entitlement.

New admissions retain the joiner's dual-key claim over group/mesh, full MLS/Moss
keys and KeyPackage hash, plus the validated original commit and resulting
GroupContext. This is an optional additive admission-envelope field, signed
before admission and matched to the actual Add leaf. Plain groups may use
existing retained SenderProof evidence for an old key binding where available;
org groups also bind the MLS credential to the proven Moss identity.
Missing historical membership/key evidence stays `evidence_missing`; no admin
endorsement invents a verifiable admission transition that was never retained.

## Current administrator authority and revocation

Resolve an immutable verified authority snapshot under the group runtime owner
after draining pending authenticated commits/roster updates. Use the same
member and admin facts as group deletion, with history-specific permission.

* Plain group: issuer full MLS key is an actual current leaf resolving uniquely
  to the tree-derived `current_admin_fingerprint`; use complete-key matching
  after unique resolution. Its Moss signature proves possession but a display
  credential/name alone does not bind a Moss identity.
* Org group: actual issuer leaf credential equals its proven Moss key, and the
  latest verified pinned org roster contains that identity with role `admin`.
  Full MLS membership is also required. Plain-group successor flags never grant
  org administrator authority. Missing roster defers; known revocation denies.
* Carriers and recipients must be actual current admitted members; org carriers
  and recipients also satisfy current roster authorization. Membership alone
  never authorizes creating a historical endorsement.

Issuer signs only while currently authorized. A receiver newly admitting an
endorsement independently verifies signatures, exact record/recipient/interval,
branch compatibility and that issuer is **currently** an admin in its own
verified view. Claimed issuance authority/epoch cannot override demotion or
removal the receiver already knows. A cached successful signature check never
caches permission. Never lower a known MLS head or org roster version/hash.

An already **locally admitted** exact endorsement remains accepted after admin
demotion so prior authenticated history is not erased or relabelled. That
protected acceptance applies only to the same endorsement/record and recipient
instance; it cannot approve later records, another recipient or another grant.
A new receiver cannot import a holder's “accepted” flag. If the issuer is now
demoted, that receiver needs a fresh current-admin endorsement. This matches
ADR 0040's local-acceptance/current-endorsement distinction, not a timestamp claim.

Offline is distinct from demoted: a retained endorsement by a still-current
admin can be relayed by any authorized holder without the admin or original
author online. Revalidate current carrier/recipient on every page. If an admin
or recipient changes during an import, revalidate uncommitted records; keep
already committed acceptance, matching rows, tombstones and durable progress.
Never reuse a pending review's previous authority snapshot after that change.

Conflicting branch hashes or equally versioned different org-roster hashes
fail closed under existing pinned authority; they are not resolved by a larger
claimed epoch or a source vote. Stale replicas cannot discover an unseen removal
without a peer carrying new evidence. No central freshness or universal immediate
revocation is introduced. An admin already trusted on the same branch can make
false historical assertions; signatures cannot remove that policy trust.

## Bounded transport and administrator review

Extend group-only History payloads with `EndorsementRequest`,
`EndorsementDecision` and `EndorsementFetch`; use recipient-directed encrypted
Moss packets via existing `send_to_peer`, with one bounded history owner, dual
SenderProof and org authorization. The single packet callback routes the fixed
`mosh-history-v1\0` prefix before the existing call-packet prefix; no second
consumer drains that inbox. The callback sender is a claim; verify full
application signatures and membership independently. No group-room content
fallback: every current member knows the group exporter key, including members
not entitled to older text. Add no competing reader of device-link stream 3
or hosted service. Requests/decisions bind the existing request ID, recovery
round, conversation and exact recipient instance.

The pinned carrier supports both paths without a new dependency: direct
`SendToPeer` uses the authenticated Noise session; relayed `sendRelayPayload`
encrypts end-to-end before the middle node forwards it. Relay AEAD uses X25519,
HKDF and ChaCha20-Poly1305 with endpoint-bound AAD, authenticated remote static
key claims and no missing-key plaintext fallback. Source:
[pinned SendToPeer](https://github.com/redstone-md/moss/blob/fcdc3383601cf3fb5232ba1ae1ffe262b552555e/internal/mesh/node_relay_api.go),
[relay sealing](https://github.com/redstone-md/moss/blob/fcdc3383601cf3fb5232ba1ae1ffe262b552555e/internal/mesh/node_relay_transport.go).
`SendStream` instead rejects relayed peers, so it is not this protocol's carrier.
This is source verification, not a substitute for direct/relayed acceptance.

Queue at most 32 outbound frames and 1 MiB aggregate; bound the history inbox
similarly before parsing or allocating reassembly. Execute the existing bounded
directed-send call outside group/session/media locks: relay establishment can
block for five seconds. No unbounded tasks or per-request threads. Missing
optional native symbols produce waiting/unsupported; never a room fallback.

One request contains up to 16 RecordBindings, original proofs, requested
contexts/intervals and a canonical batch digest. The authorized holder retains
the actual payload while seeking the endorsement. Fetch review body/offers
only if the reviewing administrator independently has proven membership
entitlement to that historical interval; current admin role is not an exception
to the new-member privacy rule. Otherwise show proof/hash/interval metadata
without plaintext and require an explicit decision on that limited basis,
never claim the admin inspected the body. The final recipient verifies actual
bytes against both original signature and endorsed binding before admission.
Pending candidates stay separate from ordinary visible history. A review
request does not silently import messages, authorize unproven recipients or
mark anything read.

Automatic endorsement requires an exact match to the admin installation's
protected durable **live** acceptance evidence: original content binding,
actual received membership context and recipient entitlement are known. A row
previously imported via another endorsement is not independent live evidence.
A matching body, author signature, sender timestamp or admin role by itself
does not qualify. Older rows lacking that local receipt require explicit review.

Without that evidence, propose one compact group-details “History requests”
batch flow for current admins: inspect original-author proof status, content,
claimed interval and exact recipient, then Confirm or Decline selected records.
No broad approvals dashboard, automatic trust toggle or pop-up for every frame.
The cost is real: an unwitnessed/disputed historical batch may wait for an admin
decision once. Retained already-endorsed evidence requires no repeated prompt
and still works when that admin is offline. **This manual flow is proposed UI,
not a product feature already approved by selecting the trust policy.**

Bound pending reviews to 16 batches per conversation, at most 16 records each,
256 KiB assembled bytes per batch and a 24-hour local request lifetime.
Reject or return capacity/expires responses without deleting older accepted
endorsements. Coalesce duplicate requests by recipient/record/interval; retries
are not new prompts. Decline is scoped to those exact record bindings/request,
not a deletion or permanent ban on history. A holder may retry after material
evidence changes; unchanged retries do not reopen declined UI automatically.
All frames obey common serialized-size/fragment limits and bounded backoff.

Issue a decision only after the signed endorsements and decision are durable.
Any current authorized holder may retain/relay those objects to their exact
recipient. Nonmatching/expired rounds cannot advance a different recovery
cursor; a timeless valid endorsement can separately be re-offered in a fresh
authorized round. A request's expiry does not revoke a saved endorsement.

## Additive storage and atomic admission

Use the already proposed encrypted `group_history_evidence` table with typed
key prefixes for endorsement digest, pending review ID, durable decision and
**local acceptance** `(endorsement_digest, recipient_instance, record_hash)`.
That last prefix is writable only by verified native import/local admission,
never by decoding remote evidence or copying an exported acceptance flag.
Reuse existing DEK/codec; no new key, table or replacement store beyond the
three tables in the common proposal. Pending reviews are not MessageLog rows.

`StoredMessage.history_evidence` retains original proof, selected endorsement
digest and provenance: `live_authenticated`, `original_signed_admin_attested`,
or existing honest legacy classification. Keep signed content-only legacy
origin separate from a newer author proof binding time/context. Never alter
the original MessageOrigin or mint it with the admin's signature.

Receiver performs all cryptographic/policy checks against a pinned authority
snapshot, then in one transaction validates unchanged authority context, stores
endorsement + local acceptance + deduplicated rows/manifests + occurrence index
+ next recovery cursor, and applies existing tombstone precedence. An authority
or deletion race retries against fresh facts; refused writes change neither
progress nor visible history. Publish completion/notifications only after commit.
An endorsement never overrides personal/shared erasure, restores deleted bytes,
changes read/delivery state, or grants a new deletion right.

Group membership transitions retain original authority evidence and the
receiver's own staged MLS snapshot atomically as in the common proposal.
Protected acceptance survives restart/admin demotion, but does not restore a
deleted local conversation or turn a new admission into its old incarnation.
No export of another client's MLS provider/snapshot or raw DEK is allowed.

## Proposed bridge changes and exact approval scope

Retain existing conversation polling. Add optional group/channel HistorySync
view with state/reason as in the common proposal; reasons include
`administrator_review_required`, not a misleading complete indicator.

Small group-only bridge additions for the proposed manual flow:

* `list_group_history_reviews(group_id, after?, limit<=16)` returns bounded
  admin-only pending batches, exact record bindings/content/proof classification,
  requested recipient/interval and an opaque review token. No key secrets.
* `resolve_group_history_review(group_id, review_token, batch_digest,
  approve_record_hashes, decline_record_hashes)` requires disjoint subsets
  belonging to that unchanged pending batch. Omitted rows stay pending. Empty,
  expired, changed-scope or ambiguous selections are refused.
* The review token binds the current authority digest, pending request, recipient
  instance and exact visible batch. Recheck current admin/membership and token
  before signing. A stale review cannot approve newly substituted rows or
  approve after demotion; return existing typed permission/persistence errors.

These calls use normal protected chat UI gating and never grant background
notification/call actions authority to approve history. No new account-level
admin capability or purchase requirement. Regenerate bridge bindings, add
feature-local gateway methods and reuse the existing group-details surface.

Approval requested covers these exact additions plus bounded directed-packet
carrier/callback routing, common History envelopes,
the optional admission identity-proof field, three encrypted tables, optional
StoredMessage evidence/snapshot fields and bounded review UI. Trust policy was
already selected; this document does not claim that exact API/schema approval.

## Verification and limits

Real independent installations: author offline; current admin offline with
retained endorsement; holder supplies previously unwitnessed genuine row and
admin explicitly confirms once; source switch/restart; private and org groups;
admission/removal/rejoin with no missing-interval disclosure; post-import live
traffic. No strict-root omission or group-admin-online requirement is hidden
inside successful completion of the already-endorsed case.

Adversarial checks: valid newly backdated old-author signature without approval;
blind auto-signing attempt; altered content/origin/recipient/interval/batch;
ordinary holder or former admin minting endorsements; current admin changing
during review/import; foreign/forked group heads; unknown old org authority;
remote forged acceptance flags; original proof absent/invalid; changed proof
after fragment assembly; oversized reviews, duplicate requests and stale actions;
write refusal and deletion between validation and commit; a newcomer with the
current exporter key and all room subscriptions attempting to decrypt pages or
admin review bodies over both direct and relayed paths; a newly promoted admin
requesting plaintext from before its admission. Unknown evidence waits;
invalid proof rejects. Admin-confirmed interval is labelled policy attestation,
never tested or advertised as cryptographic proof of pre-removal creation time.
