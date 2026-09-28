# Rust core

Shared runtime and the only Flutter bridge. Read the root architecture map
and relevant ADR before changing a runtime.

- Entry points: src/api and src/lib.rs. Each feature owns its own module.
- Reuse api/shared_runtime resources. One Moss node and encrypted database
  per installation. Keep device signing keys, Moss identity and MLS separate.
- Keep Moss source unchanged. Its process-global keystore requires independent
  processes for independent-installation tests.
- Commands and limits are in root AGENTS.md. Run cargo build before tests,
  cargo fmt, clippy with -D warnings and bridge codegen after API changes.
- Use implement/TDD for feature work, Rust domain guidance for invariants,
  Context7 for crate APIs and code-review before delivery.
- Device linking uses src/device_link, docs/ADR/0029 and its real-process
  tests. Keep private device keys out of bridge outputs. Expose QR text only
  to the initiating screen while its request is active; keep it out of logs.
