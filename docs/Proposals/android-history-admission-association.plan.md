# Authenticated admission associations for plain groups

Status: approved by the owner on 2026-10-26; implementation in progress. Supplements the approved
[automatic history contract](android-history-automatic-contract.plan.md).

Implementation is authorized by the explicit owner approval; verification is still required. Existing OrgSigned Welcome already signs its
entire original JSON, but plain Welcome has no authenticated commit association.
Pinned GroupInfo verifies the new context and author, not its unsigned commit hint.

Use one optional `admission_binding: SenderProof` field on Welcome and Commit,
plus optional `joiner_binding: SenderProof` on KeyPackage. Reuse existing dual-key
SenderProof and exact scoped `group-control/<id>` context; original proof bytes
are retained, not reconstructed from row labels.

`joiner_binding` payload is fixed JSON tuple with literal version/domain tag:
`("mosh-history-key-package-v1", 1, conversation, mesh_id, org_key_or_null,
  sha256(exact_key_package_tls), full_joiner_mls_key, full_joiner_moss_key)`.
It is verified independently against the KeyPackage's verified actual full leaf key.
No same-label/account shortcut. Existing clients ignore the optional field.

`admission_binding` payload is a fixed JSON tuple:
`("mosh-history-admission-association-v1", 1, conversation, mesh_id,
  org_key_or_null, exact_mls_group_id_hex, prior_context, next_context,
  sha256(exact_original_commit_tls), sha256(exact_welcome_tls),
  sha256(exact_ratchet_tree_tls), full_admitted_mls_key,
  sha256(exact_joiner_binding_bytes)_or_null, claimed_transition_at_ms)`.
Contexts are `(epoch, sha256(exact_verified_GroupContext_TLS))`.
SenderProof already domain separates and dual-signs its bound tuple; no new key,
algorithm, library or private snapshot wire.

The current issuer creates this association from its own staged original Add and
advanced own context, and saves it before publication atomically with its own
snapshot. Joiner verifies the exact Welcome/tree/commit hashes and scope, actual
staged Welcome full signer equals association MLS signer, and authenticated
OrgSigned sender/admin credential where org-bound. Raw commit header must name
actual MLS group and prior epoch+1 == staged next epoch, without claiming the
joiner decrypted/validated pre-admission commit. The issuer's association remains
an original authorized issuer claim. Existing recipients actually verify the
commit from their own prior MlsGroup and compare both context hashes.

Canonical instance hash uses SHA256 with `mosh-history-admission-v1\0` and fixed
JSON tuple `(version=1, exact_mls_group_id_hex, canonical_commit_hash,
full_admitted_mls_key)`. Genesis uses a separate tagged variant with pinned
initial context hash and creator key. A binding is not invented for unsigned
legacy Welcome. Invalid supplied binding refuses admission; absent binding keeps
legacy live compatibility and missing-evidence recovery status.

No PublicGroup ciphertext replay, foreign private snapshot, new trust in historic
time, prejoin history grant, room content transport, or admin approval UI.

Verification covers real OpenMLS KeyPackage/Welcome/commit flow; mismatched signer, scope, epoch, context and exact byte hashes; invalid supplied proofs; absent legacy fields; atomic storage refusal/restart; removal/rejoin and no pre-admission export.

AGENTS.md requires approval before changing public contracts. The owner explicitly approved these optional fields and fixed signing inputs on 2026-10-26. Implementation verification remains required. No new dependencies or encrypted tables are proposed.
