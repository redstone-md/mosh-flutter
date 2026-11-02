# Deterministic interrupted-download test

Starting commit: `509ea48a790156f204979e8e180f612b6d35a276`.
Keep all seven download/sidecar scenarios. Change only the interrupted-download
test and its existing asset fixture; production, dependencies and CI are unchanged.

## Failure and contract

The full onboarding-grouping trial exposed an existing race in
`test/features/settings/app_update_download_test.dart` /
`a download that dies mid-flight leaves nothing behind`. Its fixed number of
event-queue turns did not guarantee that the real asynchronous directory creation
and held artifact opener had completed. Accessing `assets.open.single` could
throw `Bad state: No element`; teardown then removed the staging directory before
the unfinished downloader opened its file, causing a second error.

An independent detached worktree at the starting commit reproduced both errors.
The original tracked test/helper sources matched Git byte-for-byte. An untracked
diagnostic runner registered the original synchronous `main` under 100 groups:
687 of 700 scenarios passed and 13 interrupted-download scenarios failed. These
were independent executions with all failures recorded, not retries hiding them.

Read the downloader, fixture, introduction `e695b4f0` and ADR 0045. Partial files
must be removed before the failed operation completes; real SHA-256, disk writes,
stream errors and cleanup remain in this test.

| File + full group/test path | Protected contract | Decision | Evidence |
| --- | --- | --- | --- |
| `app_update_download_test.dart` / `a download that dies mid-flight leaves nothing behind` | A stream failure after partial delivery propagates and removes the artifact. | REWRITE | Await held-body availability and its first real progress event; attach the error matcher before injecting the failure and await completion before teardown. |
| Same / `a verified artifact lands in staging and reports its progress` | Verified bytes, progress and sidecar-before-artifact ordering. | KEEP | Original callback unchanged. |
| Same / `a download with no declared size still reports what arrived` | Honest progress without a declared size. | KEEP | Original callback unchanged. |
| Same / `a checksum mismatch is refused and nothing is left behind` | Integrity refusal and removal. | KEEP | Original callback unchanged. |
| Same / `a release without a usable checksum is not downloaded at all` | Refuse an unverified artifact before download. | KEEP | Original callback unchanged. |
| Same / `parseSha256Sidecar` / `reads the published digest and tolerates a missing name` | Supported sidecar syntax and digest normalization. | KEEP | Original callback unchanged. |
| Same / `parseSha256Sidecar` / `refuses a digest for another file, or no digest at all` | Wrong-artifact and malformed-digest refusal. | KEEP | Original callback unchanged. |

## Verification

- Fixed sources: the same 100 registrations of all seven scenarios pass **700/700**,
  with no errors or skips. The normal suite retains its seven original names.
- A private mutation copy that omits failed-download cleanup fails the retained
  empty-staging assertion with the actual partial artifact still present. Real
  production files were not mutated.
- The fixture's unobserved controller list becomes a readiness future. Repository
  consumers were checked; only this interrupted-download test used that list.
- No sleeps, polling loops, retries, timeout increases, skips or new dependencies.
  Repetition drivers and mutation copies stay outside the discovered test tree.

Raw full-run failure, worktree reproduction, source snapshots and mutation output
are in `.git/test-audit/update-download/` and
`.git/test-audit/onboarding-bounded/pre-download-fix/`. Reproduction durations
are not a performance comparison. Later full-run experiments hold this fixture
fix constant in their controls and candidates.
