# Issue 94: reuse the loaded installation signing key

The exact `a640f75a` owner capture `cpu-20261022-213459` records 9.214% of
one logical core and 0.494 Mbit/s mean traffic, without network trace loss.
The process is only 196 seconds old; its 269.82 MiB median working set and
resource changes from the previous older process are not controlled comparisons.
All 1,794 Rust instruction weights resolve using the original shipping PDB.
Raw instruction and CSV totals differ by one of 9,521 weights; retain that
measurement limitation rather than claiming exact reconciliation.

The existing release caller profile at this exact runtime identifies repeated
`DeviceIdentity::open` and public-key construction under ownership proofs.
Dalek `SigningKey::from_bytes` calculates its public key; `Clone` preserves it.
The current identity getter repeats construction for validation, certificate
construction, signing and per-session device preparation. Rank this opportunity
impact 3 × confidence 5 / effort 2 = 7.5, ahead of lower-confidence JSON and
public incoming-network hypotheses. This is a Mosh CPU change, not a bandwidth fix.

## Scope and proof

1. Count real identity key construction at the actual getter; reproduce repeated
   work through `ownership::create` and verify unchanged serialized proofs.
2. Retain one normal Dalek `SigningKey` within its existing `DeviceIdentity`
   owner. Keep the owned-return getter contract. Match its seed before reuse;
   derive on direct record mutation so no caller can obtain a stale key.
   Update/reload must align the retained key with the installed record.
3. Preserve every fresh persisted-row read, structural/roster/certificate check,
   expected-peer check and current revocation check. No identity-validation or
   authorization result cache, global cache, timer, Moss, dependency, public API,
   schema or wire changes. Existing signing and randomness are unchanged.
4. Check deterministic signatures/proof bytes, direct seed edits, successful
   record replacement/reload and invalid committed seed refusal. Existing stale
   writer/revocation and native linked-installation tests must remain green.
5. Compare identical restored release API fixtures, alternate twenty pairs and
   compare all message metadata. Run fmt, build, Clippy, native tests, coverage,
   independent Standards/Spec review, CodeAnt and cross-platform CI. Build a
   configured Windows installer with its original PDB.

The retained object contains a seed copy and its public key, scoped to the same
owner that already holds the seed. Use Dalek's existing clone/drop behavior;
do not serialize, log or expose this object. Existing `DeviceIdentity` methods
already exceed the type-size guideline; this small field/getter change is a
local exception, avoiding an unrelated identity refactor.

Rollback is the one functional commit. Whole-Windows idle, retained memory,
residual public mesh traffic and Android acceptance stay open. No merge or
release is included.

Measurements and checks are recorded in the [results](issue-94-identity-key.results.md).
