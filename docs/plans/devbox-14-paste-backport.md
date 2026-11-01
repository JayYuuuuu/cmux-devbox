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

Pending implementation and validation. No claim that these fixes explain or resolve the previously unproven remote upload failure.
