# Hex+

[hrudek/hex](https://github.com/hrudek/hex) is a standalone iPhone project,
originally forked from [anomalyco/hex](https://github.com/anomalyco/hex) (MIT).
The integration branch is `hex-plus`; the upstream split is recorded by
`split/hex-upstream` (`cae389a8`) and `split/base` (`6f19d87b`).
[PORTS.md](PORTS.md) records the inherited base and selected future adoptions.
There are no automatic upstream merges. Features are built locally with Pi and
reach `hex-plus` through PRs checked by the Claude review agent; this file is
the entry point for agents and the owner.

## For agents: start here

- Work anywhere in the repository. Changes under `.github/` need the `infra`
  label (CI's scope check fails otherwise), so automation permissions cannot
  be widened unnoticed. Follow [AGENTS.md](AGENTS.md) for worktrees.
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
- Follow the iPhone architecture and privacy rules in `ios/README.md` and
  `AGENTS.md`. Switches are not merge protection:
  - Bug fixes, small corrections and normal features: no new switch.
  - Add a switch only for a genuine experiment or at the owner's request.
    New switches are **on by default**, and off preserves the previous
    behavior exactly. Any exception needs an explicit owner decision.
  - Switches live in the app's **Hex+** settings section:
    `HEXShared/HexPlusSettings.swift` stores values in the App Group;
    `HEXMobile/HexPlusCard.swift` hosts toggles. Do not add them to
    `ExperimentsCard.swift` or `FullKeyboardSettings.swift`.
    Existing switches and behavior stay in place unless explicitly changed.
  - Tweaks, extensions and follow-ups use the feature's existing switch (if
    it has one), even in a new session or PR; update that table row.
    A separate switch requires a genuine experiment or owner request.
  - Make a proven feature permanent through a PR: remove the switch and old
    code path, set its table status to `permanent`. No separate issue is required.
- Every feature brings simulator tests (`ios/HEXMobileTests`) to protect its
  behavior. Hand over promptly: a successful local simulator
  run is not required before the push; CI runs tests after merging to `hex-plus`.
  Use targeted tests for debugging or when the owner asks to fix failures first,
  and report honestly which tests ran or are left to CI. On a macOS runner, use
  `bash .github/hexplus/agent-test.sh [Target/Class,…]` (it leaves the app's
  identity untouched; never commit `com.bearylabs` identifiers).
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
git log --no-merges --oneline split/hex-upstream..hex-plus  # adopted base to current project
git diff split/base..hex-plus --stat                       # changes since the standalone split
gh pr list --state merged --label feature                 # features, with their reasons
```

## Hex+ features

The inherited base is recorded in [PORTS.md](PORTS.md).
Status: `switch` (has a switch in the app's Hex+ section),
`permanent` (no switch), `fix` (bug fix, never had a switch).
`pending` in the PR column means a change recorded before the PR-first rule,
without its own PR number.
The PR is the primary change reference. Use `—` in the Issue column when no
issue is needed; never create one just to fill the table. Multiple related PRs
may be listed for a feature. Documentation-only process changes need no feature row.

| Feature | Issue | PR | Status | Main files |
| --- | --- | --- | --- | --- |
| [AI cleanup](ios/AI_CLEANUP.md): on-device Apple Intelligence self-corrections, stutter/filler removal and misheard-word fixes, using the Custom vocabulary list as preferred spellings, with plain-transcript fallback; last outcome shown in the Hex+ card, which also shows the configured model (switch *Show AI cleanup model*). While on, it replaces upstream's *Clean up with Apple Intelligence* experiment | — | #49, #52, #53, #55, #57 | switch | ios/HEXMobile/HexPlusCleanup.swift, ios/HEXMobile/CleanupGuard.swift, ios/HEXMobile/CleanupPrompt.swift, ios/HEXMobile/CleanupObservation.swift, ios/HEXMobile/HexPlusAppleCleaner.swift, ios/HEXMobile/DictationController.swift, ios/HEXShared/HexPlusSettings.swift, ios/HEXMobile/HexPlusCard.swift, ios/HEXMobile/HexPlusModelInfo.swift, ios/HEXMobileTests/HexPlusModelInfoTests.swift |
| [Dictation log](ios/DICTATION_LOG.md): durable on-device archive without automatic eviction; detail shows recognized text and AI correction (each with Copy) and an inline "What I said" field, everything else under More details; one-tap Good/Problem feedback, optional categories/reference/notes; complete versioned JSON file export and bounded recent text export. Off stops collection and keeps saved logs; only explicit Delete/Clear removes them (owner-approved retention exception) | — | #58, #59, #60, #61 (archive/feedback/JSON), #64 (feedback detail) | switch | ios/HEXMobile/DictationLogArchive.swift, ios/HEXMobile/DictationLogFeedbackView.swift, ios/HEXMobile/DictationLog.swift, ios/HEXMobile/DictationLogStorage.swift, ios/HEXMobile/DictationLogView.swift, ios/HEXMobile/DictationLogExport.swift, ios/HEXMobile/DictationLogExportMenu.swift, ios/HEXMobile/WordDiff.swift, ios/HEXMobile/CleanupTextDiagnostics.swift, ios/HEXMobile/HexPlusCleanup.swift, ios/HEXMobile/DictationController.swift, ios/HEXShared/HexPlusSettings.swift, ios/HEXMobile/HexPlusCard.swift, ios/HEXMobileTests/DictationLogImprovementTests.swift |
| [Local dictation report](ios/tools/dictation_log/README.md): explicit offline Python import/report, private SQLite and raw evidence outside Git, revision-safe merge, HMAC settings fingerprints and bounded reference-only metrics; no app/runtime changes | — | #63 | permanent | ios/tools/dictation_log/archive.py, ios/tools/dictation_log/store.py, ios/tools/dictation_log/report.py, ios/tools/dictation_log/cli.py, ios/tools/dictation_log/tests/test_dictation_log.py |
| Keyboard quick feedback: exact newly inserted result, Good/Problem on the compact and full keyboard; after Problem, *Fix in Hex* opens the app on that entry's "What I said" field; durable text-free queue; honest Noted, archive commit before removal; preserves full keyboard Undo | — | #62, #64 | switch | ios/HEXShared/DictationFeedback.swift, ios/HEXShared/DictationFeedbackBridge.swift, ios/HEXShared/HexPlusFeedbackTray.swift, ios/HEXShared/FullKeyboard/HexPlusFeedbackBar.swift, ios/HEXShared/HexPlusFeedbackLink.swift, ios/HEXMobile/HexPlusFeedbackRouter.swift, ios/HEXMobile/HEXMobileApp.swift, ios/HEXShared/HexPlusSettings.swift, ios/HEXMobile/HexPlusCard.swift, ios/HEXKeyboard/KeyboardViewController.swift, ios/HEXMobile/DictationLog.swift, ios/HEXMobile/DictationController.swift, ios/HEXShared/FullKeyboard/KeyboardStripView.swift, ios/HEXShared/KeyboardSurface.swift, ios/HEXMobileTests/DictationKeyboardFeedbackTests.swift |
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
  (`feature/*`, `fix/*`, `infra/*`, …)
  is reviewed by Claude (`hexplus-review.yml`, Opus, read-only) when it is
  opened, reopened or marked ready, and again after **every new commit**; a
  newer commit cancels the review of the older one. The verdict is one sticky
  PR comment for exactly the reviewed commit, and the check **Hex+ review**:
  - `✅ PASS — nothing to fix`: check green.
  - `❌ FIX — N thing(s) to fix`: check red, with a numbered list (file, line,
    problem, fix). Optional remarks sit collapsed under *Optional notes* and
    never change the verdict.
  - `⚠️ NO RESULT`: the review could not finish (usage limit, timeout); re-run
    the failed job once; if it still has no result, inform the owner.
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
  2. Merged, just not wanted right now: if it has a switch, turn it off in the app's Hex+ section.
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
- **A merge conflict:** resolve a feature or fix PR locally with Pi. Merge
  `hex-plus` into its branch, resolve, then push (the review runs again).

The review agent is the only agent in CI. It uses the owner's Claude
subscription (`CLAUDE_CODE_OAUTH_TOKEN`, environment `hexplus-agent`) and has
no signing secrets. The review runs as `pull_request_target` from `hex-plus`'s copy of
its workflow, so a PR cannot change its own reviewer; it only reads the PR's
code and never runs it. The previous automation (issue/`@claude` agent,
Hex+ fix repair agent, automatic conflict resolver) is kept on branch
`backup/workflows-2026-11-08`.

## How the pipeline works

The pinned issue **Hex+ status** is refreshed after each hex-plus push CI run,
weekly on Monday at 06:17 UTC for renewal warnings, or manually. Under
*Needs you* it lists red hex-plus CI runs and `needs-human` issues. It also shows
the last TestFlight upload, open PRs and upcoming renewals from `expiry.json`.

```ts
Hex+ CI (fast lane: only Linux checks and compiling block; tests never hold anything up)
├─ Linux checks: CI helper + offline dictation-log tests, actionlint, shell syntax; scope on PRs
├─ Decide: did the app change (pushes to hex-plus) / the app or Hex+ CI scripts (PRs)? no → stop
├─ PRs: required archive, no simulator/screenshots
├─ Push to hex-plus with app changes: archive and simulator tests in parallel
│  └─ Test failures → status issue → fix locally → fix/<name> PR → review → merge → tests again
├─ Manual simulator mode: tests + screenshot artifacts, no device archive/signing
└─ Sign
   ├─ push to hex-plus → TestFlight as soon as the archive compiled
   └─ by hand → ad-hoc (hex-plus or feature/*, needs approval) or testflight

Hex+ review (every same-repository PR, every new commit)
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
no force pushes or deletion. Repository admins can bypass; the owner decides
when to merge. Nothing merges by itself.

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

### Identity

`.github/hexplus/app.json` gives the iPhone build Hex+'s identity:
`com.bearylabs.hex` (+ `.keyboard`, `.widgets`), App Group
`group.com.bearylabs.hex`, URL scheme `bearylabs-hex`, home-screen name
**Hex+**, Apple team `2ZNGF24932`, App Store Connect app "Hex+". `identity.py`
rewrites the committed app identity (original team `QC99C9JE59`,
`com.kitlangton.hex.mobile`) only in the disposable CI checkout. Never commit
`com.bearylabs` identifiers in app code; moving identity into source would need
its own reviewed change. The rewrite fails closed if the committed identity
changes.

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
on `hex-plus` after app changes.
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
is `macos-26`). Remotes: `origin` = `hrudek/hex`; `anomalyco` =
`anomalyco/hex` as a read-only source (push disabled), as described in
[PORTS.md](PORTS.md).
