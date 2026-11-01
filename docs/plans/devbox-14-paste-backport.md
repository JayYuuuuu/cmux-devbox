# DevBox 14: isolated upstream paste backport

## Scope and invariants

Keep upstream base v0.64.25, the accepted Ghostty revision, single-SCP uploads to absolute temporary paths, and endpoint-scoped upload prewarming unchanged. Do not enable Cloud, accounts, phone connectivity, or migrate remote workspaces to another transport.

## Implementation plan

1. Reproduce the worker startup timeout with an executable scripted worker on the current baseline, in a test-only commit.
2. Backport the upstream v0.65.1 clipboard helper dependencies and the fixes from PRs #18650 and #19164. Keep native paste flavor precedence, rich-text fidelity, cancellation/reaping, bounded work, and snapshot isolation. Wire new app/test sources and the helper build phase explicitly.
3. Run the focused clipboard regressions and relevant package gates on the build host. Measure cold/warm text preparation and helper idle cost; preserve explicit limits for stalled startup and preparation.
4. Build a signed candidate with the DevBox build script, exercise remote Codex paste on an isolated test session, and verify font/SSH upload behavior remains unchanged. Existing-device user acceptance still applies; do not imply another machine proves acceptance everywhere.
5. Commit/push and publish using the DevBox release workflow only after required gates. Update release notes and edition documentation with actual evidence and remaining acceptance work.

## Upstream sources

- https://github.com/manaflow-ai/cmux/pull/18650 (text bypasses busy full-worker lane)
- https://github.com/manaflow-ai/cmux/pull/19164 (separate worker startup allowance)
- https://github.com/manaflow-ai/cmux/pull/18280 (absolute remote paths, comparison only)

The new upstream remote-home finalization flow is intentionally not imported: the existing temporary upload already supplies absolute paths and preserves the accepted one-SCP behavior. The plain-text helper is a required supporting component missing from the v0.64 baseline, not a second clipboard implementation.

## Evidence

- Baseline runtime regression reproduced on the build host: a scripted worker with a 3-second startup was rejected at 2.009 seconds under a 2-second preparation budget. Native Swift Testing executed one test and reported the expected content mismatch; the failure is behavioral, not a compilation failure.
- The baseline initially failed before tests because Zig was absent from the noninteractive PATH. The rerun used the documented toolchain PATH.
- The documented `scripts/verify-local.py` is absent on this v0.64 checkout. Use the available project normalization/test-wiring checks and native/package tests; do not claim that missing command passed.
- Candidate imports the upstream clipboard cancellation/reaping dependency so the clipboard read lease is held until worker teardown, plus the resident text helper required by #18650.
- Candidate native run: 27 tests in four focused suites passed in 6.987 seconds. Covers worker startup, preparation/startup stalls, busy full-lane bypass, FIFO/cancellation/queue behavior, stale clipboard generations, native rich/image flavor fidelity, and reaping before clipboard lease release.
- Required unchanged package gates: CmuxRemoteSession 186, CmuxSettings 338, CmuxSettingsUI 169, CmuxUpdater 98 tests passed (791 total), using the locked dependencies on the build host. Relevant package sources were not modified by this backport.
- Isolated helper/provider behavioral run: 20 tests passed in 22.301 seconds, including Unicode byte fidelity, native image/file precedence, rich-text fallback, stale generations, parent disappearance, hard deadlines, and resident-reader reuse.
- Same-board seven-sample text preparation comparison, native Debug app-host: full worker median 91.073916 ms; helper median 0.146208 ms (first helper read 3.938459 ms). This measures local text preparation with identical mixed-language data, not remote upload or total Cmd+V latency.
- Project normalization and test wiring passed. No user-facing app strings or locale keys changed; internal documentation and test descriptions only.
- Production Swift pipe-client probes: three tests passed in 4.596 seconds. Checks clipboard restoration, cancellation/reaping before helper replacement, and rejecting/reaping an oversized response.
- Resident helper idle sample: 7,616 KiB RSS, displayed CPU 0.0%, CPU time 0:00.00 unchanged across five seconds. The old v0.64 source path has no resident helper, so this is additional process cost; it is not a before/after total-app measurement.
- Signed candidate built with `scripts/build-devbox.sh --release 14`: version 0.64.25-devbox.14, internal build 112.14, source 260a37f0431. ZIP SHA-256: `3dfa2ceecb5226c26c8657a57af96bf51e251d34cf4040d4ea5beb12953e0568`. Existing signing identity and bundle identity retained; strict nested-bundle signature verification passed both before and after transfer.
- Both signed Release executables were actually launched in isolated worker modes (not the main app UI): the full worker emitted its readiness byte and returned exact mixed-language text, and the resident helper returned exact UTF-8 through its framed pipe protocol. No existing application instance was quit or replaced.
- Candidate ZIP and extracted app delivered separately from the installed copy; received ZIP hash matches the build host. Installed copies and the published update channel remain on .13.
- Pending acceptance gate: launch the candidate app on the actual user device, compare Chinese/English/mixed text under unchanged settings, and perform real Cmd+V images into remote Codex with content recognition. Main-app launch/crash check and actual-device image-paste acceptance have not been performed. The user subsequently explicitly requested direct publication on 2026-11-01, authorizing release before these manual checks. Record the checks as unperformed rather than implying acceptance. No claim that these fixes explain or resolve the previously unproven remote upload failure.


## Publication completed (2026-11-01)

- Published https://github.com/JayYuuuuu/cmux-devbox/releases/tag/v0.64.25-devbox.14 from 2c1198e4bac04d2954a7c720c0678a3674823966, version 0.64.25-devbox.14 / build 112.14. The latest update feed and public download both read back correctly.
- Published ZIP: 111,064,194 bytes; SHA-256 `29bb04ecc47b20b7648da668e1c096b6ecac3a263a4210cb79222850b81f9331`. GitHub's uploaded-asset digest and the subsequently downloaded public ZIP both match the local signed archive.
- Published app's main executable, after removing only its signature from a comparison copy, matches the previously tested candidate byte for byte: SHA-256 `fa99252312fb49b54ab575abd1aad27261df63333746995346c3e83e5f6fdb9e`.
- Candidate main-app smoke on an idle user-owned Mac passed: application socket ready, one resident text helper, no new cmux crash report during the probe. Session restore was disabled for that launch; prior preferences, terminal snapshots and Ghostty config were restored afterward. This is launch evidence, not real Cmd+V image acceptance.
- Initial all-in-one asset uploads failed with duplicate-name responses; later ZIP uploads also returned broken-pipe/EOF errors. The root network cause was not established. Uploading the same signed archive over an alternate existing SSH transport succeeded (HTTP 201, exact server digest); no route, proxy, credential or account configuration was changed.
- The release script now stages assets in a draft and verifies uploaded state plus SHA-256 before promotion. Its digest verifier was exercised against a real known asset: the correct digest passes, a wrong digest and missing asset both fail. `--publish-existing` checks source/version/signature/local hashes and reuses the exact files. A resumed-publish readback URL scope error was fixed, and the same final readback stage then passed against the public release.
- The shared download page was updated through its existing owner script, including correcting the package requirement to Apple silicon. Unrelated working-tree software-version changes were preserved.
- Manual same-display font acceptance and real image Cmd+V into remote Codex remain unperformed; the user explicitly authorized direct publication before those checks. Previous .13 acceptance must not be attributed to .14.
