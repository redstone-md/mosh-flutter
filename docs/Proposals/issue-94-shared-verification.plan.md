# Issue 94: reuse immutable signature checks across callers

The owner caller export `callers-20261024-041744` matches the five binaries,
PID 21948 and all 7,662 weights of `cpu-20261024-031529`. There is no skipped
weight; 2,755 weights contain broken unwinds. Private original artifacts stay
outside the repository.

## Ranked evidence

| Target | Inclusive weight | Interpretation | Next check |
| --- | ---: | --- | --- |
| Windows adapter enumeration | 452 (5.90%) | Calling Go goroutine missing at system-stack transition | Preserve the existing interface work; no speculative additional Moss change |
| Rust mesh snapshot | 365 (4.76%) | Seen in service, lists and poll/read commands | Separate freshness and cadence investigation |
| Strict Ed25519 verification | 341 (4.45%) | 241 under roster reads; 85 under DM identity claims | Count actual repeated checks through the real callers |
| Local identity loading | 356 (4.65%) | Includes roster validation and ownership construction | Overlaps signature work; do not add shares |
| Mark-viewed command | 242 (3.16%) | Includes inbound/protocol work | Preserve receipt retry and current authorization behavior |

Weights are sampled observations, not CPU durations. Rows overlap. Flutter
and incomplete native stacks prevent attributing the entire remaining CPU.
Mapped Go frames use the exact owner DLL's recovered function ranges.

## Hypotheses and scope

1. Deserializing an unchanged roster resets its per-object OnceLock, so repeated
   identity opens repeat the same signatures. An unchanged-open counter must
   fail before and pass after reuse, while changed chains and revocation fail
   or update normally.
2. DM topology validation verifies unchanged claims on each service tick and
   again during add-client validation. Repeated topology checks should reuse
   signature math while checking the current roster and MLS signers each time.
3. Repeated mesh snapshots and read commands also cost CPU, but their freshness
   and retry behavior require their own evidence. Do not change their cadence
   as part of this signature correction.

The existing deletion verifier already retains at most 4,096 successful,
timeless signature/certificate facts. Move that implementation behind a
crate-private cryptographic boundary and reuse it for roster signatures and
DM proof signatures. Keep one shared bound, fixed-size digests, strict Dalek
verification, canonical device-key validation and success-only insertion.
Never retain authorization, membership, revocation or a whole identity.
No public contract, dependency, wire/storage shape or Moss source changes.

Opportunity: impact 2 / confidence 5 / effort 3 = 3.33. The expected gain is
limited to repeated cryptographic checks, not the whole process or network.

## Execution and checks

- Add actual verification counters and caller regressions first; run them red.
- Reuse the existing cache, with tests for changed key/signature/input,
  invalid/weak keys, bounded eviction and concurrent hits/misses.
- Keep caller tests for malformed/forked/removed device chains, revoked
  identities, changed MLS membership and existing history permissions.
- Compare before/after native API workers on the same restored fictional
  saved-chat fixture, with identical message/identity/permission outputs and
  identical public-discovery isolation. Alternate order and avoid builds
  during measurement. This is not whole-Windows acceptance.
- Run formatting, Rust build/tests/Clippy, independent code review, CodeAnt
  comments/nitpicks and platform CI. Build the configured Windows release only
  after verification. No merge or release is authorized.
