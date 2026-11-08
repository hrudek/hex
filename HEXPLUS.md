# Hex+

`hrudek/hex` is a personal fork of [anomalyco/hex](https://github.com/anomalyco/hex)
for the iPhone app. Branch `hex-plus` (the fork's default branch) is upstream's
`dev` merged in daily, plus Hex+'s own features. Upstream takes no pull
requests, so features live only here. Features are built locally with Pi and
reach `hex-plus` through PRs that a Claude review agent checks; this file is
the entry point for agents and for the owner.

## For agents: start here

- Work only in `ios/` and this file. Touch `.github/hexplus/` or
  `.github/workflows/hexplus-*.yml` only when asked; such PRs need the `infra`
  label (CI's scope check fails otherwise). Never edit upstream's `AGENTS.md`
  or other upstream files outside `ios/`: every change there conflicts with
  the daily upstream merge.
- Local development with Pi is **PR-first**: discuss the request in Pi → branch
  `feature/<name>` from `hex-plus` → PR to `hex-plus` with label `feature` → squash
  merge. No issue or issue number in the branch name is required. Do not create
  an issue retroactively just to document an already implemented change.
- Use an existing relevant issue when there is one. Create an issue only for
  deferred or unresolved work, coordination across multiple PRs, or at the
  owner's request. Issues are notes only: no agent starts from an issue or an
  `@claude` comment.
  Use `Closes #<issue>` only when the PR fully resolves that issue; otherwise
  link it without closing it. The pinned status issue keeps its role and is
  not affected by this rule.
- Keep each PR cohesive and independently reviewable. A larger feature may span
  several PRs; do not force it into one commit merely to match an issue.
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
  - Make a proven feature permanent through a PR: remove the switch and the old
    code path, set its table status to `permanent`. The same optional-issue rule
    applies; no separate "Make … permanent" issue is required.
- Every feature brings simulator tests (`ios/HEXMobileTests`), so the daily
  merge cannot silently break it. Hand over promptly: a successful local simulator
  run is not required before the push; CI runs tests after merging to `hex-plus`.
  Use targeted tests for debugging or when the owner asks to fix failures first,
  and report honestly which tests ran or are left to CI. On a macOS runner, use
  `bash .github/hexplus/agent-test.sh [Target/Class,…]` (it leaves the app's
  identity untouched; never commit `com.bearylabs` identifiers).
- Merge-conflict markers in a `sync` or `upstream-pr` PR: keep upstream's
  change and Hex+'s behaviour, remove every marker; CI's "No conflict markers"
  check must pass. Push to that PR's own branch, then remove the `conflict`
  label and mark the PR ready (`gh pr edit <n> --remove-label conflict && gh pr ready <n>`).
- The PR is the durable record of a directly developed change. Its description
  says: the goal, agreed user-visible behaviour, important decisions and their
  reasons, which files changed, what was tested, and what could not be tested
  (anything only a real iPhone proves). Carry relevant outcomes out of the Pi
  conversation into the PR or repository documentation; session logs alone are
  not the handover. Update the description when the agreed scope changes.
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
The PR is the primary change reference. Use `—` in the Issue column when no
issue is needed; never create one just to fill the table. Multiple related PRs
may be listed for a feature. Documentation-only process changes need no feature row.

| Feature | Issue | PR | Status | Main files |
| --- | --- | --- | --- | --- |
| [AI cleanup](ios/AI_CLEANUP.md): on-device Apple Intelligence local word fixes and explicit self-corrections, with plain-transcript fallback; last outcome shown in the Hex+ card | — | #49, #52, #53 | switch | ios/HEXMobile/TranscriptCleanup.swift, ios/HEXMobile/CleanupGuard.swift, ios/HEXMobile/CleanupObservation.swift, ios/HEXMobile/AppleIntelligenceCleaner.swift, ios/HEXMobile/DictationController.swift, ios/HEXShared/HexPlusSettings.swift, ios/HEXMobile/HexPlusCard.swift |
| Hex keyboard no longer falls back to the iOS keyboard (Swift 6 lexicon crash) | #31 | pending | fix | ios/HEXKeyboard/KeyboardViewController.swift, ios/HEXShared/FullKeyboard/LexiconDelivery.swift |
| German autocorrect: ae/oe/ue/ss → ä/ö/ü/ß and German typo fixes on the full keyboard | #33 | pending | switch | ios/HEXShared/FullKeyboard/GermanAutocorrect.swift, ios/HEXShared/HexPlusSettings.swift, ios/HEXMobile/HexPlusCard.swift |
| Keep mic warm stays hot after a keyboard dictation (no trip back into the app for the next one) | #42 | pending | fix | ios/HEXMobile/AudioBackend.swift, ios/HEXMobile/DictationController.swift |
| Keyboard switch key: tap on the dictation bar shows the full keyboard; hold 0.35 s on the full keyboard shows the dictation bar | #44 | pending | switch | ios/HEXShared/FullKeyboard/KeyboardSwitchKey.swift, ios/HEXKeyboard/KeyboardViewController.swift, ios/HEXShared/FullKeyboard/FullKeyboardView.swift, ios/HEXShared/KeyboardSurface.swift, ios/HEXShared/HexPlusSettings.swift, ios/HEXMobile/HexPlusCard.swift |

## Asking for work (owner)

- **Default: develop here with Pi.** Describe the change in the conversation;
  Pi clarifies requirements as needed, implements on `feature/<name>`, performs
  appropriate checks and opens a PR to `hex-plus`. No issue is needed. Use a
  draft PR if an early durable work-in-progress record helps. The PR preserves
  the agreed behaviour, decisions and verification; lasting product or
  architecture rules belong in repository documentation. Existing CI, merge
  requirements and distribution rules still apply. To try a PR before it
  merges, run **Hex+ PR to iPhone** with its number.
- **Review agent (automatic).** Every same-repository PR into `hex-plus`
  (`feature/*`, `fix/*`, `infra/*`, …; not `sync/upstream` or `upstream-pr/*`)
  is reviewed by Claude (`hexplus-review.yml`, Opus, read-only) when it is
  opened, reopened or marked ready, and again after **every new commit**; a
  newer commit cancels the review of the older one. The verdict is one sticky
  PR comment for exactly the reviewed commit, and the check **Hex+ review**:
  - `✅ PASS — nothing to fix`: check green.
  - `❌ FIX — N thing(s) to fix`: check red, with a numbered list (file, line,
    problem, fix). Optional remarks sit collapsed under *Optional notes* and
    never change the verdict.
  - `⚠️ NO RESULT`: the review could not finish (usage limit, timeout); re-run
    the failed job.
  Agents working on a PR: read the latest Hex+ review comment, fix every
  numbered finding, push, and wait for the next verdict. The check is not a
  required status check, so the owner can still merge deliberately.
- **Changes to a PR:** ask Pi here to continue on that branch; the push starts
  a new review.
- **The loop, end to end** (nothing merges by itself; no repair agent runs in CI):

  ```ts
  Pi: develop on feature/<name> → commit → push → PR (label feature)
  ├─ automatic: Hex+ review + PR CI (Linux checks, Decide, Unsigned archive)
  ├─ ❌ FIX → in the same Pi session (a new one if the context is long or stale):
  │          "read the Hex+ review comment and fix the findings" → commit → push → review again
  ├─ ✅ PASS + checks green → owner: "merge" → squash merge
  └─ hex-plus: archive → TestFlight at once; simulator tests in parallel
     └─ tests red → status issue + GitHub mail → Pi: "hex-plus CI is red, read
        `gh run view <id> --log-failed` and fix it" → branch fix/<name> → PR → same loop
  ```

  TestFlight deliberately does not wait for the tests: try the build on the
  iPhone at once and fix in parallel.
- **Removing a feature:**
  1. Not merged yet: close the PR.
  2. Merged, just not wanted right now: turn its switch off in the app's Hex+ section.
  3. For good: on the merged feature PR click **Revert**, then squash-merge the
     revert PR. For a feature spanning several PRs, revert the relevant commits
     together, accounting for dependencies. Remove its table row only when the
     whole feature is removed; PRs and any existing issue stay as history.
     Reverting the revert brings it back.
  4. The revert conflicts (a later feature builds on it): ask Pi to remove the
     feature while preserving the dependent behaviour.
  Agents: a revert is mechanical; prefer GitHub's Revert over rewriting code.
- **Automation changes** need the `infra` label. Adding it re-runs the PR's failed
  Hex+ CI jobs by itself (`hexplus-recheck.yml`; the scope check reads labels live).
  Other label events start no CI run (as in OpenCode).
  Draft PRs get only the Linux checks until marked ready.
- **An unmerged upstream PR:** `gh workflow run hexplus-upstream-pr.yml -R hrudek/hex -f pr=1234`.
  It opens a PR from `upstream-pr/1234`; without conflicts it merges
  automatically with a **merge commit** once its required checks pass. With
  conflicts it is a draft labelled `conflict` without auto-merge: resolve it
  locally (see below), then merge it with a merge commit. The daily sync PR
  reports when upstream merged (the carry dissolves) or closed it (decide
  whether to keep it).
- **A merge conflict:** resolved locally with Pi. A feature or fix PR that
  GitHub shows as conflicting: merge `hex-plus` into its branch locally,
  resolve, push (the review runs again). A sync or carried upstream PR (draft,
  label `conflict`, markers committed): check out its branch, resolve, push,
  remove `conflict`, mark ready. The status issue lists a conflicting sync.

The review agent is the only agent in CI. It uses the owner's Claude
subscription (`CLAUDE_CODE_OAUTH_TOKEN`, environment `hexplus-agent`) and has
no signing secrets. The review runs as `pull_request_target` from `hex-plus`'s copy of
its workflow, so a PR cannot change its own reviewer; it only reads the PR's
code and never runs it. The previous automation (issue/`@claude` agent,
Hex+ fix repair agent, automatic conflict resolver) is kept on branch
`backup/workflows-2026-11-08`.

## How the fork works

The pinned issue **Hex+ status** (updated after every hex-plus and sync/upstream
CI run and every sync) says under *Needs you* what to fix locally: a red
hex-plus or sync/upstream CI run, a failed sync, a sync with merge conflicts.
It also shows the last TestFlight upload, open PRs and what must be renewed soon.

```ts
hexplus-sync (daily 04:23 UTC, or by hand)
├─ upstream dev has new commits? no → done
├─ sync/upstream = hex-plus + merge of upstream dev (never rebases, never force-pushes hex-plus)
│  ├─ upstream touching Hex+ files → issue "Hex+ sync needs you"
│  ├─ conflict → merge committed with markers, draft PR labelled conflict (later syncs wait for it;
│  │             resolve locally, push, remove conflict, mark ready)
│  ├─ open sync PR with local fixes on top (tip not by hexplus-sync) → left alone until promoted
│  └─ PR "Sync upstream … (N commits, iOS changed: yes|no)", label sync,
│     with the upstream state of every carried upstream PR
├─ Hex+ CI runs on sync/upstream (tests AND archive must pass; red → fix locally on sync/upstream)
└─ hexplus-gate: green → fast-forward hex-plus to the merge (the PR shows as merged)

Hex+ CI (fast lane: only Linux checks and compiling block; tests never hold anything up)
├─ Linux checks: script tests, actionlint, no conflict markers, scope (every PR and push)
├─ Decide: did the app change (pushes to hex-plus) / the app or Hex+ CI scripts (PRs)? no → stop
├─ PRs (including upstream-pr/* push checks): required archive, no simulator/screenshots
├─ Push to hex-plus with app changes: archive and simulator tests in parallel
│  └─ Test failures → status issue → fix locally → fix/<name> PR → review → merge → tests again
├─ Manual simulator mode: tests + screenshot artifacts, no device archive/signing
└─ Sign
   ├─ push to hex-plus → TestFlight as soon as the archive compiled
   └─ by hand → ad-hoc (hex-plus or feature/*, needs approval) or testflight

Hex+ review (every same-repository PR, every new commit; not sync/upstream, upstream-pr/*)
├─ sticky comment "reviewing <sha>" → Claude (Opus, read-only) reviews the PR diff
└─ ✅ PASS (check green) | ❌ FIX + numbered findings (check red) | ⚠️ NO RESULT (re-run)

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

### Automatic runner-capacity retries

`Hex+ runner retry` watches completed Hex+ CI and PR-to-iPhone workflows.
When GitHub explicitly reports that a hosted macOS job could not acquire a
runner, it retries that job after 5, 10, then 20 minutes. The job must have no
assigned runner and no executed steps. Real test/build failures, user-cancelled
runs, foreign repositories and unrelated workflows are never retried this way.
The wait uses a Linux runner, not a macOS runner; no agent or signing secret is
used. Control code always comes from trusted `hex-plus`, never the failed branch.

At most three retries are permitted per original run, using GitHub's
`run_attempt` counter (manual reruns also consume this budget). Only one affected
job is retried per attempt; GitHub may also rerun its dependent jobs. Successful
independent jobs and genuine test failures are not rerun. The source branch must
still point at the same commit, and a PR must remain open and non-draft. These
checks repeat after the wait; a newer attempt cancels the pending retry.
After the budget is exhausted the original run stays red and the retry workflow's
summary says no retry is possible.

The Linux unit tests cover recognition, exclusions, delay/budget bounds, current
source checks and selective rerun requests. They do not prove GitHub's real
capacity recovery or guarantee that a later attempt receives a runner.

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
on `hex-plus` after app changes; the upstream-sync gate still requires
successful tests before promotion.
A cancelled or not-yet-started CI run is refused. It checks again after approval;
if the PR changed, rerun once the new commit's required jobs pass.
Artifacts expire after seven days: rerun PR CI if the archive is missing or
expired, or use the fresh-build fallback. A changed Hex+ identity also requires
a new PR build. Signing uses only control scripts from `hex-plus`, never scripts
from the PR; no signing secrets reach the PR build. The reused IPA keeps the
original archive's build number and `build.json`. Merging still creates a fresh
TestFlight build as before. Archive selection, provenance, digest and ZIP checks
have Linux unit tests; these do not prove Xcode export or installation on a real
iPhone.

All builds share one bundle ID: an ad-hoc install replaces the TestFlight
version on the iPhone (data stays). If GitHub's macOS runners are short on
capacity, set the variable `MACOS_RUNNER` (now `macos-15-intel`; the default
is `macos-26`). Remotes: `origin` = `hrudek/hex`, `upstream` = `anomalyco/hex`
(push disabled).
