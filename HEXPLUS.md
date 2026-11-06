# Hex+

`hrudek/hex` is a personal fork of [anomalyco/hex](https://github.com/anomalyco/hex)
for the iPhone app. Branch `hex-plus` (the fork's default branch) is upstream's
`dev` merged in daily, plus Hex+'s own features. Upstream takes no pull
requests, so features live only here. Features are built by AI agents; this file
is the entry point for them and for the owner.

## For agents: start here

- Work only in `ios/` and this file. Touch `.github/hexplus/` or
  `.github/workflows/hexplus-*.yml` only when asked; such PRs need the `infra`
  label (CI's scope check fails otherwise). Never edit upstream's `AGENTS.md`
  or other upstream files outside `ios/`: every change there conflicts with
  the daily upstream merge.
- One feature = one issue (the spec) → branch `feature/<name>` from `hex-plus`
  → one PR to `hex-plus` with label `feature` → squash merge, so the feature is
  one commit whose message ends with `Closes #<issue>`.
- Follow upstream's iPhone rules in `ios/README.md` and `AGENTS.md`, except for
  switches: Hex+ is the owner's personal app, so its features are wanted.
  - Bug fixes and small corrections: no switch.
  - New behaviour or a new look: a Hex+ switch, **on by default**, so it can be
    turned off without a new build. Switches live in the app's own **Hex+**
    settings section, in Hex+'s own files (`HEXShared/HexPlusSettings.swift`
    for the stored values in the App Group, `HEXMobile/HexPlusCard.swift` for
    the toggles; create them with the first switch), never in upstream's
    `ExperimentsCard.swift` or `FullKeyboardSettings.swift`. The off position
    keeps today's behaviour exactly.
  - A proven feature becomes permanent through its own issue ("Make … permanent"):
    remove the switch and the old code path, set its table status to `permanent`.
- Every feature brings simulator tests (`ios/HEXMobileTests`), so the daily
  merge cannot silently break it. Hand over promptly: a successful local simulator
  run is not required before the push; CI runs tests after merging to `hex-plus`.
  Use targeted tests for debugging or when the owner asks to fix failures first,
  and report honestly which tests ran or are left to CI. On a macOS runner, use
  `bash .github/hexplus/agent-test.sh [Target/Class,…]` (it leaves the app's
  identity untouched; never commit `com.bearylabs` identifiers).
- Merge-conflict markers in a `sync` or `upstream-pr` PR: keep upstream's
  change and Hex+'s behaviour, remove every marker; CI's "No conflict markers"
  check must pass.
- The PR description says: what changes for the user, which files, how it was
  tested, what could not be tested (anything only a real iPhone proves).
- PRs allocate no simulator runner: no automatic simulator tests or screenshots.
  For an optional visual/test check before merging, manually run Hex+ CI on the
  feature branch with distribution `simulator`. It runs tests, then captures the
  fixed `--snap-state` scenes (`ready`, `keyboard-warm`, `keyboard-recording`,
  `full-keyboard-idle`, `full-keyboard-idle-dark`) using the same simulator build,
  with no device archive or signing. Download `hexplus-screenshots-RUN_ID` from
  the run's artifacts (kept seven days); screenshots are no longer posted to PRs.
  List affected scenes in the PR's `Screenshots:` line as suggestions for this
  optional check, and pass them through the manual `scenes` input. New screens
  can add a scene in `KeyboardPreviewHost.swift` / `FullKeyboardSnapshotStage.swift`.
- Update the feature table below in the same PR.

Orientation:

```sh
git log --no-merges --oneline upstream/dev..hex-plus   # every Hex+ commit
git diff upstream/dev...hex-plus --stat                # everything Hex+ changes
gh pr list --state merged --label feature              # features, with their reasons
gh pr list --label sync                                # upstream merges
gh pr list --state all --label upstream-pr             # upstream PRs carried early
```

## Features on top of upstream

Status: `switch` (on by default, can be turned off in the app's Hex+ section),
`permanent` (no switch), `fix` (bug fix, never had a switch).

| Feature | Issue | PR | Status | Main files |
| --- | --- | --- | --- | --- |
| _none yet_ | | | | |

## Asking for work (owner)

- **A feature:** open an issue with the **Hex+ feature** form (it sets the
  `agent` label itself), or label any issue `agent`. A blank issue stays a
  note the agent ignores. **Planning** (Opus, Linux runner, cannot change code) replies with
  a short summary and at most 3 questions (with suggested defaults); the full
  technical plan for the build agent sits collapsed below it. Revise with `@claude plan …`; approve with
  `@claude go` plus any corrections. **Building** (Sonnet, macOS runner) then
  implements that plan and its tests on `feature/<n>-…`, without waiting for
  a local simulator test run. PR CI builds only the device archive; simulator tests
  run after merging to `hex-plus`. The PR
  then opens itself with auto-merge: it lands on `hex-plus` as soon as it
  compiles, and TestFlight follows (fast lane, as upstream). Red tests are
  repaired afterwards by **Hex+ fix**. To try a PR before it merges, run
  **Hex+ PR to iPhone** with its number. Disable auto-merge before the required
  checks finish if you want to run the optional manual simulator check or try the
  PR on your iPhone before merging.
  You can then request fixes in the open PR and merge whenever you choose. Each run
  starts fresh and reads the issue and all comments by `hrudek` and Claude.
  A small change needs no plan: comment `@claude …` on an issue without the
  `agent` label. Label `model:opus` makes building use Opus too.
- **Changes to a PR:** comment `@claude …` on it; Claude pushes to that branch.
- **Removing a feature:**
  1. Not merged yet: close the PR.
  2. Merged, just not wanted right now: turn its switch off in the app's Hex+ section.
  3. For good: on the merged feature PR click **Revert**, then squash-merge the
     revert PR. It removes the one squash commit, including the feature's row
     in the table below; issue and PRs stay as history. Reverting the revert
     brings it back.
  4. The revert conflicts (a later feature builds on it): comment on the
     feature's issue `@claude remove this feature again, keep <other feature>`.
  Agents: a revert is mechanical; prefer GitHub's Revert over rewriting code.
- **Automation changes** need the `infra` label; label events start no CI run
  (as in OpenCode), so after adding it, re-run the failed `Linux checks`.
  Draft PRs get only the Linux checks until marked ready.
- **An unmerged upstream PR:** `gh workflow run hexplus-upstream-pr.yml -R hrudek/hex -f pr=1234`,
  or ask in an issue comment. It opens a PR from `upstream-pr/1234`; merge it
  with **Create a merge commit**. The daily sync PR reports when upstream
  merged (the carry dissolves) or closed it (decide whether to keep it).
- **A conflict** (`conflict` label, draft PR): nothing to do; Hex+ fix resolves it.

Only `hrudek` can start the agent; it reads only comments by `hrudek` and itself. It uses
the owner's Claude subscription (`CLAUDE_CODE_OAUTH_TOKEN`, environment
`hexplus-agent`) and has no signing secrets.

## How the fork works

The owner only watches: the pinned issue **Hex+ status** (updated hourly and after
every fix, sync and gate run) says whether anything needs a human, what is being
repaired, the last TestFlight upload, and what must be renewed soon.

```ts
hexplus-sync (daily 04:23 UTC, or by hand)
├─ upstream dev has new commits? no → done
├─ sync/upstream = hex-plus + merge of upstream dev (never rebases, never force-pushes hex-plus)
│  ├─ upstream touching Hex+ files → issue "Hex+ sync needs you"
│  ├─ conflict → merge committed with markers, draft PR labelled conflict (later syncs wait for it)
│  └─ PR "Sync upstream … (N commits, iOS changed: yes|no)", label sync,
│     with the upstream state of every carried upstream PR
├─ Hex+ CI runs on sync/upstream (tests AND archive must pass)
└─ hexplus-gate: green → fast-forward hex-plus to the merge (the PR shows as merged)

Hex+ CI (fast lane: only Linux checks and compiling block; tests never hold anything up)
├─ Linux checks: script tests, actionlint, no conflict markers, scope (every PR and push)
├─ Decide: did the app change (pushes to hex-plus) / the app or Hex+ CI scripts (PRs)? no → stop
├─ PRs: Unsigned archive (required), no simulator tests or screenshots
├─ Push to hex-plus with app changes: archive and simulator tests in parallel
│  └─ Test failures → Hex+ fix → fix PR → archive → merge → tests again
├─ Manual simulator mode: tests + screenshot artifacts, no device archive/signing
├─ Nightly 05:41 UTC: every test on hex-plus, no device archive/signing
└─ Sign
   ├─ push to hex-plus → TestFlight as soon as the archive compiled
   └─ by hand → ad-hoc (hex-plus or feature/*, needs approval) or testflight

Hex+ fix (no owner step; at most 6 attempts per incident)
├─ Hex+ CI red in a code job on hex-plus, sync/upstream, an open feature PR or a fix PR
│  ├─ issue "CI broken: <branch>" (label fix) is opened/reused; green CI closes it
│  └─ signing/TestFlight failed → re-run once, then needs-human (Apple's side)
├─ agent on macOS (Sonnet, Opus from attempt 2 and for syncs): reproduce with the
│  simulator tests, fix until they pass locally, hand over a patch (never .github/,
│  never weakened tests); it cannot push
├─ push job (git/gh only): commit → hex-plus incidents: PR fix/ci-<n> with auto-merge;
│  sync/upstream: commit there, conflict PR marked ready; feature PRs: their branch
├─ CI runs again → still red → next attempt right away
├─ usage limit / no change → retried every 30 minutes (limits do not count as attempts)
└─ 6 attempts or > 4 incidents a day → label needs-human, work stops, status says so

Hex+ PR to iPhone (by hand, from hex-plus, enter an open feature PR number)
├─ Verify current PR commit, successful Linux checks, Decide and unsigned archive
├─ No automatic PR simulator tests; optional manual checks do not block signing
├─ Your approval in hexplus-ad-hoc
├─ Revalidate PR, download existing archive, check GitHub SHA-256 and build provenance
└─ Sign → encrypted ad-hoc IPA (no rebuild, no TestFlight upload)
```

`hex-plus` only moves forward: `git pull --ff-only` always works locally.
Branch rules: changes reach `hex-plus` through PRs with green `Linux checks`,
`Decide` and `Unsigned archive` (skipped counts as passed);
no force pushes or deletion. Repository admins (the owner, and the sync gate
through `SYNC_TOKEN`) can bypass, so the gate can fast-forward.

### Automatic upstream sync

The sync creates/updates its PR with `SYNC_TOKEN` (the owner's trusted account),
not `github-actions[bot]`, avoiding the bot's first-contributor approval prompt.
The token needs permission to create and update pull requests in this repository
as well as push branches. The repository's approval policy for other contributors
stays unchanged; no automatic approval of arbitrary workflows is added.

After a successful `sync/upstream` push CI, a small job explicitly dispatches
`hexplus-gate.yml` on `hex-plus`. It uses only `GITHUB_TOKEN` with Actions write
permission and executes no branch code. `workflow_run` remains a fallback; two
requests for the same sync are harmless. The gate independently checks the run's
repository, workflow, push event, branch, conclusion and required job results
before its separate privileged job can push. It waits up to five minutes if the
requesting CI has not quite finished yet. A sync with no app changes can skip
both simulator tests and archive, not just one.

Promotion requires an open sync PR, the tested SHA still at `sync/upstream`, and
a fast-forward from the current `hex-plus`. Changes to Hex+'s protected control
files are refused even with green CI. An already promoted SHA is a no-op; if
`hex-plus` moved in the meantime, the next sync rebuilds the merge. For recovery,
run `gh workflow run hexplus-gate.yml --ref hex-plus -f run_id=CI_RUN_ID`.
Ordinary green syncs need no manual workflow approval or merge. Conflicts and
protected-file changes still require intervention; ad-hoc signing still requires
the owner's approval. Verification logic has Linux tests for rejected runs,
job outcomes, pagination and bounded waiting. Local Git integration tests execute
the actual promotion shell for success, duplicate requests, stale branches,
missing PRs, divergence and protected files. These checks alone are not proof
that GitHub dispatch, promotion and downstream TestFlight ran end-to-end.

Observed on 2026-11-06: push CI run `42227843662` explicitly dispatched gate
`42227898076`, which verified the run and automatically fast-forwarded `hex-plus`,
merging sync PR #15. This sync changed no app inputs, so no TestFlight build was
needed. Owner-token PR updates are still blocked until `SYNC_TOKEN` gets
**Pull requests: Read and write** for this repository: run `42227812901` failed
with `Resource not accessible by personal access token (updatePullRequest)`.
Edit the existing fine-grained token under GitHub account Settings → Developer
settings → Personal access tokens → Fine-grained tokens. If replacing it rather
than changing its permissions, update the `hexplus-sync` environment secret too.
Never paste the token in an issue or PR. After granting access, run the sync
again; the next upstream update will exercise owner-token PR creation as well.

### Files Hex+ owns

Upstream never touches these, and the sync refuses upstream commits that would:
`HEXPLUS.md`, `.github/hexplus/`, `.github/workflows/hexplus-*.yml`,
`.github/ISSUE_TEMPLATE/hexplus-*.yml`.

Upstream files Hex+ replaces or deletes are listed in `.github/hexplus/ours.txt`
(today: upstream's issue templates). Their merge conflicts resolve to Hex+'s
side automatically; conflicts anywhere else go to a draft PR. Every
other upstream workflow is disabled in this fork, and the sync disables any new
one it brings in.

### Identity

`.github/hexplus/app.json` gives the iPhone build Hex+'s identity:
`com.bearylabs.hex` (+ `.keyboard`, `.widgets`), App Group
`group.com.bearylabs.hex`, URL scheme `bearylabs-hex`, home-screen name
**Hex+**, Apple team `2ZNGF24932`, App Store Connect app "Hex+". `identity.py`
rewrites upstream's identity (Kit's team, `com.kitlangton.hex.mobile`) in the CI
checkout only, so no identity change ever conflicts with upstream. It fails
closed when upstream's identity changes.

## Owner commands

```sh
# Fast path: sign the existing compiled feature PR archive (no rebuild, no test wait).
# Run from hex-plus, enter the PR number, approve on the run page:
gh workflow run hexplus-ad-hoc.yml -R hrudek/hex --ref hex-plus -f pr=123

# Optional pre-merge simulator tests + screenshots (no device archive/signing):
gh workflow run hexplus-ci.yml -R hrudek/hex --ref feature/NAME \
  -f distribution=simulator -f scenes=keyboard-transcribing,full-keyboard-numbers-dark
# Download screenshots from that run's hexplus-screenshots-RUN_ID artifact.
# only_testing optionally restricts tests; none skips the simulator job and screenshots.

# Fallback: build a fresh ad-hoc archive of hex-plus or a feature branch:
gh workflow run hexplus-ci.yml -R hrudek/hex --ref feature/NAME -f distribution=ad-hoc

# For either path, RUN_ID below is the signing workflow's run ID:

gh run download -R hrudek/hex RUN_ID --pattern 'hexplus-ad-hoc-*' --dir ~/code/hex-downloads/RUN_ID
age --decrypt --identity ~/.local/share/ios-build-signing/artifacts.agekey \
  --output HEX.ipa ~/code/hex-downloads/RUN_ID/hexplus-ad-hoc-RUN_ID/HEX.ipa.age
~/code/apple-dev-setup/iphone-wifi install "$PWD/HEX.ipa"

# TestFlight happens on its own for every hex-plus change to the app; by hand:
gh workflow run hexplus-ci.yml -R hrudek/hex -f distribution=testflight

# Sync now:
gh workflow run hexplus-sync.yml -R hrudek/hex

# Profiles (local only, uses ~/.local/share/ios-build-signing):
python3 -I .github/hexplus/provision.py ad-hoc|testflight

# CI scripts on Linux:
python3 -m unittest discover -s .github/hexplus/tests
```

The fast path accepts only open, non-draft `feature/*` PRs from this repository
into `hex-plus`. It requires the latest PR CI run for the current head commit,
with `Linux checks`, `Decide` and `Unsigned archive` successful (none may be
skipped). PRs do not automatically run simulator tests or screenshots. Optional
manual simulator checks do not gate archive reuse. Automated simulator tests run
on `hex-plus` after app changes and nightly; the upstream-sync gate still requires
successful tests before promotion.
A cancelled or not-yet-started CI run is refused. It checks again after approval;
if the PR changed, rerun once the new commit's required jobs pass.
Artifacts expire after seven days: rerun PR CI if the archive is missing or
expired, or use the fresh-build fallback. A changed Hex+ identity also requires
a new PR build. Signing uses only control scripts from `hex-plus`, never scripts
from the PR; no signing secrets reach the build agent. The reused IPA keeps the
original archive's build number and `build.json`. Merging still creates a fresh
TestFlight build as before. Archive selection, provenance, digest and ZIP checks
have Linux unit tests; these do not prove Xcode export or installation on a real
iPhone.

All builds share one bundle ID: an ad-hoc install replaces the TestFlight
version on the iPhone (data stays). If GitHub's macOS runners are short on
capacity, set the variable `MACOS_RUNNER` (now `macos-15-intel`; the default
is `macos-26`). Remotes: `origin` = `hrudek/hex`, `upstream` = `anomalyco/hex`
(push disabled).
