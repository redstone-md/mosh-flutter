# Repository simplification

Scope: Flutter UI and state, Rust runtime and storage, native probes, build
tooling and architecture documentation. Preserve product behavior, bridge
contracts, persistence schemas, dependency versions and cryptographic checks.
Do not modify Moss.

The baseline is commit `6195121`. Tracked source contains 220,936 lines,
including 80,514 lines in third-party source. First-party application, probe and
tooling code contains 68,432 lines; generated bindings contain 23,509; tests
contain 45,020. The measured extensions and reproducible command will accompany
the final report. Report vendor removal separately from authored-code changes.

Work proceeds in independently verified commits:

1. Replace the complete OpenMLS mirror with a pinned archive and complete local
   patch. Verify byte-identical source reconstruction and offline preparation.
2. Consolidate Rust runtime ownership and encrypted persistence operations.
   Split lifecycle, actions, transport callbacks and tests into named modules.
3. Unify repeated Flutter rendering and interaction helpers. Remove obsolete
   implementation histories while retaining invariants and useful comments.
4. Split the probe and cryptographic adapter by responsibility, shorten the
   architecture map and record how the final modules connect.
5. Run formatting, analyzers, strict Clippy, full Flutter and real-native Rust
   tests, bridge drift checks and focused coverage. Rebase on current main and
   open a ready PR with actual LOC counts and limitations.

Risks: durable write ordering, MLS admission and recovery, FFI callback lifetimes,
Flutter asynchronous lifetime guards and native source preparation. Existing
behavior tests remain. Code reduction does not justify removing security checks,
features or useful regression coverage. The vendor source migration adds a first
checkout preparation requirement; CI and Flutter native builds own it.
