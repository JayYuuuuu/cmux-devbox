# cmux DevBox fork: read first

This checkout is **cmux DevBox**, a personal fork of manaflow-ai/cmux (branch
`devbox-custom`, upstream base in `scripts/build-devbox.sh` `UPSTREAM_TAG`).
These rules override the upstream notes below where they conflict.
User-facing details: [docs/devbox-edition.md](docs/devbox-edition.md).

- **Edition switch.** Every edition-only behavior keys off the bundle id
  `com.cmuxterm.app.staging.devbox`: `CmuxDevBoxEdition` (CmuxSettings: forced
  MDM keys, Settings sections, sign-in), `CmuxFeatureFlags.devBoxEditionPinnedOffKeys`
  (flags pinned off) and `DevBoxEditionUpdates` (CmuxUpdater: own Sparkle feed).
  Add new Cloud / account / phone entry points to these switches; never scatter
  ad-hoc `if` checks, and never let edition code change behavior for other ids.
- **Keep the patch set small** so upstream upgrades stay cheap: one change per
  commit, prefer gating over deleting upstream code. Upgrades cherry-pick
  `devbox-custom` onto a new stable tag; never track upstream `main`.
- **Image paste is the core feature.** Uploads must insert the remote
  *absolute* path (Claude Code does not expand `~`). Any change near
  `RemotePasteFileTransferPolicy`, `TerminalSSHSessionDetector` or the
  clipboard paste path needs the package tests plus a real Cmd+V into remote
  Claude Code showing `[Image #N]`.
- **Verify** with `python3 scripts/verify-local.py --affected <upstream tag>` and
  the touched packages' `swift test` (at least CmuxRemoteSession, CmuxSettings,
  CmuxSettingsUI, CmuxUpdater). A build is not a test run.
- **Build and release** only with `scripts/build-devbox.sh` / `scripts/release-devbox.sh`
  (never upstream reload scripts for releases, never the stable id). Releases
  are `v<upstream>-devbox.<n>`, `<n>` strictly increasing; installed copies
  update from the newest release's `appcast.xml`. Before publishing, launch the
  built app once and check that the paste worker runs and no crash report appears.
- **Public repo hygiene.** Commits use the GitHub noreply author; nothing in the
  repo may name private machines, accounts, hosts, LAN addresses or home paths
  (the build also fails if `$HOME/` leaks into the bundle). Signing keys and the
  signing keychain never enter the repo. No force pushes to `devbox-custom`.
- Machine-specific build and release notes live in an untracked `CLAUDE.local.md`.

---

# cmux agent notes

Keep repo-wide decisions here; procedures belong in [CONTRIBUTING.md](CONTRIBUTING.md),
[area instructions](#area-instructions) and [task skills](skills/README.md).
Read the matching skill before changing an area, then only the references needed.

**Manaflow AI team members and their agents:** read the private [cmuxterm-hq CLAUDE.md](https://github.com/manaflow-ai/cmuxterm-hq/blob/main/CLAUDE.md) and [AGENTS.md](https://github.com/manaflow-ai/cmuxterm-hq/blob/main/AGENTS.md) before fleet or CI work. They are the entry point for fleet builds, CI routing, agent coordination, and landing rules. Start fleet work at [Fleet and CI: start here](https://github.com/manaflow-ai/cmuxterm-hq/blob/main/build-fleet/FLEET-AND-CI.md). External contributors can ignore this block; those links return 404 for them.

## Verification and isolation

- Before committing, setup or a native build, [choose scoped verification](skills/cmux-testing/references/local-vs-ci-validation.md).
  Start with `python3 scripts/verify-local.py`; docs and portable tooling need no app build.
  Run repository commands only in a [trusted checkout](docs/contributor-verification.md#trust-boundary),
  including `verify-local.py --help`, `--list` and `--repo`. Push does not run checks for you.
- Use [CONTRIBUTING.md](CONTRIBUTING.md#getting-started) for setup. Outside cmuxterm-hq-created
  checkouts, set `CMUX_DEV_BACKEND_MODE=local` for dev builds. Follow [tagged builds](skills/cmux-dev-workflow/references/tagged-builds.md)
  for commands and cache reuse; team fleet tasks start at
  [Fleet and CI: start here](https://github.com/manaflow-ai/cmuxterm-hq/blob/main/build-fleet/FLEET-AND-CI.md).
  Never use bare `xcodebuild` or an untagged `cmux DEV.app`. Clean up only your own tags.
- A same-repo app PR gets a fleet dogfood build and link comment only while it has the
  `dev-build` label. Add it when someone will dogfood the PR, not by default; under load
  the fleet builds the newest push, and the comment says how to build a skipped commit.
- Never quit, kill, relaunch, replace or launch-profile the user's running cmux
  (`/Applications/cmux.app`, `com.cmuxterm.app`), including through a Release build or
  another bundle with that ID. Never set `CMUX_ALLOW_REPLACING_RUNNING_CMUX`; only the
  user may. Reproduce in a tagged build and attach profiling to its PID.
- Dogfood through `CMUX_TAG=<tag> scripts/cmux-debug-cli.sh`, never `/tmp/cmux-cli`.
  Never report raw `.app` paths or `file://` URLs.
- App-linked code (`Sources/`, `CLI/`, `TunnelExtension/` and their packages) must
  remain [Swift 6.0 compatible](skills/cmux-architecture/references/swift-6-0-compatibility.md).

## Area instructions

Read these before working in their scope; nested files may not load automatically:

- `ios/` or `Packages/iOS/`: [ios/AGENTS.md](ios/AGENTS.md).
- `web/` or any cmux Cloud database work: [web/AGENTS.md](web/AGENTS.md).
- `cmux-tui/`: [cmux-tui/AGENTS.md](cmux-tui/AGENTS.md).

## Contributions and publication

Before fixing a bug or adding a feature, search open upstream PRs by symptom or
issue number. Prefer landing an outside contributor's existing PR; push fixups
only when maintainer edits are allowed, and explain the changes. If using their
approach in your own PR, credit them in every such commit with `Co-authored-by`
using their commit email, link your PR from theirs and thank them. Let a human
close it; never close an outside PR without a human-written explanation.

The server directories listed in [LICENSE](LICENSE) (`web/`, `workers/ci-artifacts/`,
`workers/iroh-v2/`, `workers/presence/`, `services/iroh-relay-minter/`,
`cmux-tui/relays/cloudflare-do/`) use the Business Source License, which needs
every outside author's CLA grant. Do not merge a PR that changes those
directories while CLA Assistant is red, and do not copy an outside
contributor's work there under a `Co-authored-by` trailer unless that person
has signed the CLA. Keep code that ships in the macOS or iOS app out of those
directories.

Read [STYLE.md](STYLE.md) before drafting or revising issues, PR descriptions,
RFCs or progress updates. Fill the PR's `## Changelog` section with one
`Added`/`Changed`/`Fixed`/`Removed` line for user-visible changes, otherwise `none`.
Do not edit `CHANGELOG.md` in feature PRs; release tooling owns it.

## CI, review and merge

- Commit the failing behavioral regression before its fix; record the same
  focused command's red and green results ([testing policy](skills/cmux-testing/SKILL.md#reproduce-and-repair)).
- Check executed tests on the current SHA; green skipped jobs do not establish coverage.
  Add `full-ci` only for a user-requested or agreed broad validation plan,
  naming the extra lanes and why ([CI coverage](skills/cmux-testing/references/pr-ci-coverage.md)).
- Keep branches current locally with `scripts/merge-main.sh`; follow
  [the merge-main guide](docs/ci/merge-main.md) and never force-push over its merge.
- A first implementation pass ends with passed scoped verification and an open PR;
  do not watch CI or run speculative reviews by default.
- Before merging, use a [review subagent](skills/cmux-review/SKILL.md), correctness
  first; a second model is not a review gate. Wait for checks relevant to the
  change; disclose skipped verification on the PR. `main` is nightly: fix forward,
  do not revert.
- App/runtime/UI merges require the user’s explicit approval after dogfood **or a direct merge directive**
  (`merge`, `merge it`, `auto-merge`; not `finish`, `lgtm` or `ship it`). Follow
  [dogfood, re-dogfood and merge receipts](skills/cmux-review/SKILL.md#dogfood-and-merge).
  Notify with `cmux notify` when a socket is available.

## Implementation rules by task

Use these existing owners instead of duplicating their checklists here:

| Touching | Read before editing |
| --- | --- |
| Typing paths, SwiftUI list/store boundaries, rendering, find layering, UTTypes or OS-specific bugs | [cmux-debugging](skills/cmux-debugging/SKILL.md) |
| Packages, workspace groups, lockfiles or feature flags | [cmux-architecture](skills/cmux-architecture/SKILL.md) |
| Submodules or GhosttyKit | [cmux-ghostty](skills/cmux-ghostty/SKILL.md) |
| User-facing strings, docs or help | [cmux-localization](skills/cmux-localization/SKILL.md); report the localization audit |
| New cmux shortcuts | [cmux-keyboard-shortcuts](skills/cmux-keyboard-shortcuts/SKILL.md) |
| Tests or target wiring | [cmux-testing](skills/cmux-testing/SKILL.md); run `scripts/sync-test-wiring` after adding, renaming or deleting a `cmuxTests/` file |
| Multiple entrypoints or a bug that tests previously missed | [cmux-shared-behavior](skills/cmux-shared-behavior/SKILL.md); share action/mutation paths, verify every entrypoint, and cover the missed repro |

## Remote CLI relay

For v2 socket methods and remote CLI changes, read [relay authorization](skills/cmux-socket-policy/references/remote-relay-authorization.md).
`RemoteRelayCommandPolicy` defaults to deny. Allowlist only for a needed remote
flow, scoped to the session's objects; command-bearing params stay denied on
every method. The PR must analyze local command/content
execution, access to unowned objects and local-state exposure, and include the
required policy tests and ID scoping. Unsafe local effects must be redesigned.
Never allowlist terminal spawn/respawn without live verification that it executes
on the remote host. An allowlist addition without this analysis blocks review.
