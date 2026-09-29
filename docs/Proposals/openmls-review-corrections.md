# OpenMLS review corrections

These changes address the ten approved inline findings and six selected nitpicks
in [PR 29](https://github.com/redstone-md/mosh-flutter/pull/29). The user approved
the scope on 2026-09-28 after triage. The vendored version remains OpenMLS 0.8.1,
upstream commit `47dbedecad0c1fd8eb5368d582250ebfcc1e1ce6`. They extend the local
[historical-validation patch](openmls-historical-validation.md).

No dependency versions, serialized fields, exported types or function signatures
change. Runtime corrections affect commit staging, leaf signing and resumption
PSK retention. Application-data validation is behind `extensions-draft-08`;
Mosh does not enable that feature. Framework and benchmark corrections affect
test utilities and examples.

## Approved inline fixes

Locations below are the original review locations. The four LIKELY ACCEPT
findings were reproduced with real RustCrypto providers before being fixed.

| Thread ID | Approved verdict | Reviewed file | Verified correction |
| --- | --- | --- | --- |
| `PRRT_kwDOTpdkls6m3GB3` | ACCEPT | [tests/book_code_discard_commit.rs:499](../../third_party/openmls/tests/book_code_discard_commit.rs) | Use the actual group ID and plaintext snapshots; compare non-proposal state and retain the pending proposal. |
| `PRRT_kwDOTpdkls6m3GGS` | ACCEPT | [src/test_utils/test_framework/mod.rs:216](../../third_party/openmls/src/test_utils/test_framework/mod.rs) | Return None for an unknown leaf index. |
| `PRRT_kwDOTpdkls6m3GGc` | ACCEPT | [src/test_utils/test_framework/mod.rs:470](../../third_party/openmls/src/test_utils/test_framework/mod.rs) | Reject an empty client setup with NotEnoughClients before random selection. |
| `PRRT_kwDOTpdkls6m3GGi` | ACCEPT | [src/test_utils/test_framework/mod.rs:517](../../third_party/openmls/src/test_utils/test_framework/mod.rs) | Reject zero-sized groups before creating any group state. |
| `PRRT_kwDOTpdkls6m3GGq` | ACCEPT | [src/test_utils/test_framework/mod.rs:691](../../third_party/openmls/src/test_utils/test_framework/mod.rs) | Sample eligible removal targets without replacement using the existing rand dependency. |
| `PRRT_kwDOTpdkls6m3GKW` | LIKELY ACCEPT | [src/group/public_group/validation.rs:757](../../third_party/openmls/src/group/public_group/validation.rs) | Validate Remove against the proposed or current dictionary and reject missing components. |
| `PRRT_kwDOTpdkls6m3GwQ` | LIKELY ACCEPT | [src/schedule/psk.rs:594](../../third_party/openmls/src/schedule/psk.rs) | Evict the lowest retained epoch, including stores restored with legacy cursor/order. |
| `PRRT_kwDOTpdkls6m3HAy` | LIKELY ACCEPT | [src/group/mls_group/commit_builder.rs:973](../../third_party/openmls/src/group/mls_group/commit_builder.rs) | Complete message conversion before saving a pending commit or resetting AAD. |
| `PRRT_kwDOTpdkls6m3HLs` | LIKELY ACCEPT | [src/group/mls_group/proposal.rs:187](../../third_party/openmls/src/group/mls_group/proposal.rs) | Reject unsupported by-value self-Update before key or proposal storage changes. |
| `PRRT_kwDOTpdkls6m3Hbg` | ACCEPT | [src/group/tests_and_kats/tests/app_data_update_proposal_validation.rs:740](../../third_party/openmls/src/group/tests_and_kats/tests/app_data_update_proposal_validation.rs) | Require ConfirmationTagMismatch for wrong application-data updates and unchanged receiver state. |

All ten fixes pass the full OpenMLS library suite and the relevant integration
suites. GitHub confirms `isResolved: true` for every thread ID in the table;
there were no resolution failures. The two rejected threads remain unresolved.
The user explicitly approved commit and ordinary push to the PR branch on
2026-09-28 after reviewing the completed checks and file inventory.
Publication was then held to investigate failing CI. That separate native
discovery correction is recorded in [the CI follow-up](native-discovery-ci.md).

## Compatibility and simplifications

- The PSK store keeps its serialized shape and initial cursor convention, so
  existing storage KATs remain valid. Full-store eviction scans retained epochs
  instead of trusting a cursor produced by the old code. This costs O(capacity),
  with the current group builder retaining 32 entries. Secrets already evicted
  by the old code cannot be recovered.
- A self-Update cannot be included in its author's own Commit under
  [RFC 9420 section 12.2](https://www.rfc-editor.org/rfc/rfc9420.html#section-12.2).
  The generic proposal API now rejects that unsupported encoding using its
  existing error type. Reference proposals and the direct self-update API keep
  their behavior.
- Random removals use rand 0.9's existing sampling API. The resampling loop,
  duplicate-identity tracking and per-target client locks are removed.
- The dictionary-mismatch test now checks the actual authenticated failure
  rather than accepting either success or any error. The duplicate-Remove test
  starts with an existing component, so it still checks deduplication.
- Snapshot comparison in the custom-proposal discard test uses plaintext,
  matching neighboring tests. Encrypted sending legitimately advances message
  secrets even when the delivery service later rejects a Commit.

## Nitpicks

Six of the eight items in the
[latest summary](https://github.com/redstone-md/mosh-flutter/pull/29#issuecomment-5878572887)
were fixed:

1. Reject benchmark group sizes below two; skip undersized legacy stored groups.
2. Assert the decoding error in the KeyPackage protocol-version test.
3. Store Bob's Update at Alice and check that Alice's Commit contains it.
4. Assert both expected create-commit errors in proposal-validation tests.
5. Process application messages and queue member/external-join proposals in
   `MemberState::deliver_and_apply` instead of panicking. Storage errors use the
   existing processing error type.
6. Sign the updated leaf before storing its new private key.

Two remain outside this patch:

- Moving the removed-member Inactive transition after merge does not make the
  multiple storage writes atomic and could weaken the existing failure behavior.
  This needs a storage transaction/rollback design.
- Completing the three omitted message KAT comparisons needs additional cases
  in the public test-utils `EncodingMismatch` enum. That contract change was not
  part of the approved inline fixes.

The two rejected inline findings, `PRRT_kwDOTpdkls6m3GKO` and
`PRRT_kwDOTpdkls6m3GNc`, remain unresolved with verdict DO NOT ACCEPT. Draft-08 explicitly permits
AppDataDictionary in GroupInfo in
[sections 4.6 and 7.2.1](https://datatracker.ietf.org/doc/html/draft-ietf-mls-extensions-08#section-4.6).
Removing the fallible leaf-extension builder check without a final validation
boundary would change its contract rather than safely repair setter ordering.

## Verification

The published crate omits upstream `test_vectors` and its self dev-dependency,
so standalone library tests need an isolated checkout. Validation restores only
those missing upstream test inputs at the exact provenance commit. The repository
manifest and dependency declarations remain unchanged. Generated vectors and
coverage/build files stay outside tracked source.

Reproduce from the repository root:

```bash
review_dir=$(mktemp -d /tmp/mosh-openmls-review.XXXXXX)
python3 - "$review_dir" <<'PY_COPY'
from pathlib import Path
import shutil, sys
shutil.copytree('third_party/openmls', sys.argv[1], dirs_exist_ok=True,
                ignore=shutil.ignore_patterns('target', '.git'))
PY_COPY
sha=$(python3 -c 'import json; print(json.load(open("third_party/openmls/.cargo_vcs_info.json"))["git"]["sha1"])')
curl -fsSL "https://codeload.github.com/openmls/openmls/tar.gz/$sha" -o "$review_dir/upstream.tar.gz"
tar -xzf "$review_dir/upstream.tar.gz" -C "$review_dir" --strip-components=2 "openmls-$sha/openmls/test_vectors"
cat >> "$review_dir/Cargo.toml" <<'TOML'

[dev-dependencies.openmls]
path = "."
features = ["test-utils"]
TOML
cargo test --manifest-path "$review_dir/Cargo.toml" --features test-utils,extensions-draft-08 --lib
cargo test --manifest-path "$review_dir/Cargo.toml" --features test-utils,extensions-draft-08 \
  --test mls_group --test managed_api --test book_code_discard_commit --test app_data_update
cargo test --manifest-path "$review_dir/Cargo.toml" --features test-utils --example large-groups review_tests
```

Completed checks:

- OpenMLS: 689 library tests passed, with 13 existing ignored tests.
- Relevant OpenMLS integration suites: 75 passed; benchmark parser: 1 passed.
- Mosh core: build, strict all-target Clippy and formatter passed; 410 unit tests
  and 29 integration tests passed, with 13 existing ignored subprocess/test entries.
- LLVM coverage of measured changed runtime lines: 51/53, 96.23%. Branch coverage
  requires a nightly toolchain, unavailable in the installed stable toolchains;
  the export contains no branch counters and no branch percentage is claimed.
- Changed Rust files pass rustfmt and the patch passes git diff --check.

Upstream files already exceed the repository's size limits. Existing large
functions, including the shared app-data fixture, retain their structure to keep
this vendor patch reviewable. New regression files are below 150 lines and new
helpers/tests are below 50 lines. There are no Mosh Rust API changes requiring
bridge regeneration.

## Changed files

- [docs/Proposals/openmls-historical-validation.md](../../docs/Proposals/openmls-historical-validation.md)
- [docs/Proposals/openmls-review-corrections.md](../../docs/Proposals/openmls-review-corrections.md)
- [third_party/openmls/examples/large-groups.rs](../../third_party/openmls/examples/large-groups.rs)
- [third_party/openmls/examples/review_regressions/large_groups.rs](../../third_party/openmls/examples/review_regressions/large_groups.rs)
- [third_party/openmls/src/framing/tests.rs](../../third_party/openmls/src/framing/tests.rs)
- [third_party/openmls/src/group/mls_group/commit_builder.rs](../../third_party/openmls/src/group/mls_group/commit_builder.rs)
- [third_party/openmls/src/group/mls_group/proposal.rs](../../third_party/openmls/src/group/mls_group/proposal.rs)
- [third_party/openmls/src/group/mls_group/proposal_review_tests.rs](../../third_party/openmls/src/group/mls_group/proposal_review_tests.rs)
- [third_party/openmls/src/group/mls_group/tests_and_kats/tests/mls_group.rs](../../third_party/openmls/src/group/mls_group/tests_and_kats/tests/mls_group.rs)
- [third_party/openmls/src/group/public_group/validation.rs](../../third_party/openmls/src/group/public_group/validation.rs)
- [third_party/openmls/src/group/tests_and_kats/tests/app_data_review_tests.rs](../../third_party/openmls/src/group/tests_and_kats/tests/app_data_review_tests.rs)
- [third_party/openmls/src/group/tests_and_kats/tests/app_data_update_proposal_validation.rs](../../third_party/openmls/src/group/tests_and_kats/tests/app_data_update_proposal_validation.rs)
- [third_party/openmls/src/group/tests_and_kats/tests/proposal_validation.rs](../../third_party/openmls/src/group/tests_and_kats/tests/proposal_validation.rs)
- [third_party/openmls/src/schedule/psk.rs](../../third_party/openmls/src/schedule/psk.rs)
- [third_party/openmls/src/schedule/psk_store_review_tests.rs](../../third_party/openmls/src/schedule/psk_store_review_tests.rs)
- [third_party/openmls/src/test_utils/single_group_test_framework/mod.rs](../../third_party/openmls/src/test_utils/single_group_test_framework/mod.rs)
- [third_party/openmls/src/test_utils/test_framework/mod.rs](../../third_party/openmls/src/test_utils/test_framework/mod.rs)
- [third_party/openmls/src/test_utils/test_framework/review_tests.rs](../../third_party/openmls/src/test_utils/test_framework/review_tests.rs)
- [third_party/openmls/src/treesync/node/leaf_node.rs](../../third_party/openmls/src/treesync/node/leaf_node.rs)
- [third_party/openmls/tests/book_code_discard_commit.rs](../../third_party/openmls/tests/book_code_discard_commit.rs)
- [third_party/openmls/tests/managed_api.rs](../../third_party/openmls/tests/managed_api.rs)
- [third_party/openmls/tests/mls_group.rs](../../third_party/openmls/tests/mls_group.rs)
- [third_party/openmls/tests/review_regressions/commit_and_update.rs](../../third_party/openmls/tests/review_regressions/commit_and_update.rs)
- [third_party/openmls/tests/review_regressions/delivery.rs](../../third_party/openmls/tests/review_regressions/delivery.rs)
- [third_party/openmls/tests/review_regressions/test_framework.rs](../../third_party/openmls/tests/review_regressions/test_framework.rs)

## Standards

No hard documented breaches or substantive heuristic smells. The fixes remain
local to the approved vendor scope, preserve dependencies and serialized
contracts, reuse existing APIs, and add focused regressions. Existing upstream
size exceptions are documented here. Findings: 0.

## Spec

All ten approved inline fixes are implemented; the four LIKELY findings were
reproduced before fixing. Six nitpicks are fixed and two are deferred with
documented reasons. PSK storage remains compatible with legacy records. Commit
conversion and leaf signing precede their state writes. No unrequested scope or
incorrect implementation identified. Actionable findings: 0.

The verified patch contains 16 modified tracked files and 9 new files,
all listed above and all from this workflow. Publication uses an ordinary push
to the existing feature branch.
