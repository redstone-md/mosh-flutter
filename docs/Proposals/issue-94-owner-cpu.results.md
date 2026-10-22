# Issue 94: owner CPU attribution and repeated history verification

Windows idle acceptance remains open. This increment addresses repeated pure
signature verification in Mosh history snapshots. It makes no Moss policy,
protocol, storage, dependency or public bridge change.

## Owner capture

The owner supplied `cpu-20261022-132801/mosh-cpu-report.zip`, SHA-256
`c98c2a18a582672f40e60ea8e740ca6053d6f1efb228f5837ed61b5e070d372a`.
All five binary hashes match the configured installer from run 39692467913:
Mosh source `3e6790f5`, Moss `eb79f38`. The process is approximately sixteen
minutes old at capture start. Hardware: AMD Ryzen 7 6800H, sixteen logical
processors; Windows 10.0.26200.0. The 90.593-second network capture is complete,
control-validated and has zero event/buffer loss.

| Observation | Value |
| --- | ---: |
| Process CPU, one logical core | 14.148% |
| CPU normalized over sixteen logical processors | 0.884% |
| Working-set median | 239.54 MiB |
| Combined network mean | 1.853 Mbit/s |
| Complete-second median / p95 / peak | 0.714 / 7.379 / 26.211 Mbit/s |
| Receive share / UDP share | 71.59% / 94.30% |
| Statistical Rust / Moss / Flutter weights | 26.68% / 25.72% / 7.65% |

Instruction totals reconcile exactly with the module export: 12,332 samples.
All 3,172 Moss instructions match function ranges recovered from the shipping
Go 1.25.9 DLL. Edwards25519 multiplication/squaring and related curve work lead
its flat profile; mesh-info serialization and allocation also contribute.
These are instruction proportions, not per-module CPU milliseconds. This ZIP
contains aggregate instruction offsets, not full caller stacks. It does not
establish which caller caused every owner-side crypto check.

Approximate CPU/network interval correlation is 0.745, using overlap with
one-second byte buckets. This supports inspecting background network work,
but is not causal attribution. The reported 100–150 Mbit/s idle condition is
not present in this complete capture.

## Reproduction and ranked hypotheses

1. History-sized repeated verification: adding signed history increases CPU in
   unchanged UI snapshots, with stacks through `message_deletion`.
2. Public peer exchange: Moss signature work scales with incoming announcements.
3. Shared mesh snapshots: repeated JSON construction/decoding scales with the
   public peer directory and number of API polls.

A private same-binary Linux release probe restores the existing fictional
8-DM/2-group/1-channel fixture. It adds locally admitted, signed messages to one
offline DM, then issues thirty public `list_sessions` calls. The manual DM
service setting removes background DM timer variance; Moss still runs. This
isolates history cost and is not a whole-Windows or network acceptance test.

| Additional history | CPU for thirty calls | Median wall time per call |
| --- | ---: | ---: |
| 0 messages | 0.13 s | 4.17 ms |
| 100 messages | 0.85 s | 45.22 ms |
| 200 messages | 1.40 s | 63.48 ms |

A twenty-second sampled run on the 200-message fixture records no lost samples.
Callers lead from `list_sessions` / `snapshot_with_mesh` into
`MessageOrigin::verify_signature`, account-proof verification and
`DeletionAuthority::member_with_proof`. Curve arithmetic leads the flat profile.
This reproduces a history-dependent CPU cause; it does not prove all owner CPU
or the residual incoming bandwidth has this cause.

## Scope and invariants

The opportunity scores impact 4 × confidence 5 / effort 2 = 10. A bounded,
process-local cache retains at most 4,096 SHA-256 fingerprints of successful
Ed25519 checks. Each fingerprint covers the decoded public key, the explicit
signature-string length, the signature and the entire signed input. No message
bodies, keys, permission results or serialized cache state are retained.

Strict verification, including weak-key rejection, still runs on a miss. Failed
checks never populate the cache. The cache lock is released before curve work;
concurrent misses may verify twice. FIFO eviction only causes re-verification.

Current membership, role, revocation, context and content checks stay outside
the cache. A cached signature cannot grant a permission after the corresponding
role/device is removed. No operation is suppressed or reordered, no RNG inputs
change, and output metadata must remain identical for unchanged authority.

The cache is an acceleration with bounded memory. Histories exceeding its working
set may still require repeated checks; full-history polling/serialization and
public network work remain independent costs. Rollback is one code commit.

## Verification

The caller-level regression first fails on repeated cryptographic work while
unchanged metadata remains correct. Independent snapshot checks reject altered
conversation/id/content-hash/author/signature/ownership transcripts and enforce
current role loss, membership removal and device revocation. The fixed focused
message-deletion suite passes all thirty-two tests, including existing linked
account, historical deletion and revoked-issuer scenarios. A cache bound check
covers eviction and duplicate admission.

Full native checks, a matched release comparison, original Windows-symbol
validation and the PR bot review are recorded below when complete.
