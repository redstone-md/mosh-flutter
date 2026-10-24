# Issue 94: avoid signing unchanged local DM claims

The owner follow-up `cpu-20261022-195633` matches all five binaries from the
configured `56d2dc4a` installer. Its complete, loss-free 90.729-second capture
records 11.172% of one logical CPU core and 0.918 Mbit/s average traffic. The
owner reports 23 direct neighbors, no relayed neighbors, 30 relay-capable
directory entries and 483 known peers. These observations do not establish
a controlled whole-application improvement or close idle acceptance.

The exact original Rust PDB resolves all 1,997 Rust instruction weights.
Curve arithmetic leads the Rust flat profile; Go's mesh-info serialization
also remains visible. Flat instruction samples do not identify every caller.
Ranked remaining hypotheses are repeated local identity/claim work, repeated
mesh reports, and incoming public-mesh work. Test the first independently.

`prepare_devices` refreshes every session on each receive/service entry.
`refresh_device_identity` constructs and signs a claim before checking whether
its roster differs. Advertising constructs that same claim again before its
existing suppression check. Lock down this repeated-signing seam first.

## Scope

1. Add a caller-level regression that counts real claim signing during repeated
   unchanged refresh/advertising and still asserts actual emitted frame counts.
2. Reuse the deterministic signature for an identical complete signing input.
   Keep one digest/signature slot per DM session, with no persistent state or
   private keys. Fresh roster-extension and device-membership checks still run
   before reuse. Preserve selected-roster/removal logic and all publication
   schedules. A changed session, roster, MLS signer, device or name must miss.
3. Verify roster revocation after warming, changed inputs, contextual refusal,
   and existing offline advertisement retry/epoch/roster behavior. Measure an
   identical restored native fixture before/after and compare complete caller
   metadata; separate sampler/harness costs from application predictions.
4. Run native checks, cross-platform CI, independent Standards/Spec review and
   CodeAnt comments/nitpicks, then build and validate a configured Windows EXE
   with its exact original PDB.

No Moss, public API, wire, schema, dependency, timer or permissions cache changes.
Residual network traffic and owner-side resource acceptance remain open. No
merge or release is authorized in this increment.
