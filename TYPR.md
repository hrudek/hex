# Typr

[hrudek/typr](https://github.com/hrudek/typr) is a standalone iPhone dictation
keyboard. Typr is based on Hex by Kit Langton
(https://github.com/kitlangton/hex / https://github.com/anomalyco/hex), MIT.
The default and integration branch is `main`.
[PORTS.md](PORTS.md) records provenance and selected future adoptions.
Features are built locally with Pi and reach `main` through reviewed PRs;
this file is the entry point for agents and the owner.

## For agents: start here

- Work anywhere in the repository. Changes under `.github/` need the `infra`
  label (CI's scope check fails otherwise), so automation permissions cannot
  be widened unnoticed. Follow [AGENTS.md](AGENTS.md) for worktrees.
- Local development with Pi is **PR-first**: discuss the request in Pi →
  successful `git fetch --prune origin` → branch `feature/<name>` (or
  `fix/<name>`) from the freshly fetched `origin/main` → PR to `main` with
  label `feature` → squash merge. See [AGENTS.md](AGENTS.md) for worktrees
  and resuming existing tasks.
  No issue or issue number in the branch name is required. Do not create
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
  - Switches live with their related settings, not in separate Typr or
    Experiments sections: **Keyboard**, **AI & vocabulary**, or **History & feedback**.
    `TyprShared/TyprSettings.swift` still stores Typr values in the App Group;
    `Typr/SettingsPreferences.swift` and `Typr/KeyboardSettingsCard.swift`
    host the controls. Do not move Typr values into `FullKeyboardSettings.swift`.
    Existing switches and behavior stay in place unless explicitly changed.
  - Tweaks, extensions and follow-ups use the feature's existing switch (if
    it has one), even in a new session or PR; update that table row.
    A separate switch requires a genuine experiment or owner request.
  - Make a proven feature permanent through a PR: remove the switch and old
    code path, set its table status to `permanent`. No separate issue is required.
- Every feature brings simulator tests (`ios/TyprTests`) to protect its
  behavior. Hand over promptly: a successful local simulator
  run is not required before the push; CI runs tests after merging to `main`.
  Use targeted tests for debugging or when the owner asks to fix failures first,
  and report honestly which tests ran or are left to CI. On a macOS runner, use
  `bash .github/typr/agent-test.sh [Target/Class,…]` (it leaves the app's
  identity untouched and validates it against `.github/typr/app.json`).
- The PR is the durable record of a directly developed change. Its description
  says: the goal, agreed user-visible behaviour, important decisions and their
  reasons, which files changed, what was tested, and what could not be tested
  (anything only a real iPhone proves). Carry relevant outcomes out of the Pi
  conversation into the PR or repository documentation; session logs alone are
  not the handover. Update the description when the agreed scope changes.
- PRs allocate no simulator runner: no automatic simulator tests or screenshots.
  For an optional visual/test check before merging, manually run Typr CI on the
  feature branch with distribution `simulator`. It runs tests, then captures the
  fixed `--snap-state` scenes (`ready`, `keyboard-warm`, `keyboard-recording`,
  `full-keyboard-idle`, `full-keyboard-idle-dark`) using the same simulator build,
  with no device archive or signing. Download `typr-screenshots-RUN_ID` from
  the run's artifacts (kept seven days); screenshots are no longer posted to PRs.
  List affected scenes in the PR's `Screenshots:` line as suggestions for this
  optional check, and pass them through the manual `scenes` input. New screens
  can add a scene in `KeyboardPreviewHost.swift` / `FullKeyboardSnapshotStage.swift`.
- Update the feature table below in the same PR.

Orientation:

```sh
git log --no-merges --oneline split/hex-upstream..main  # Typr commits on top of the adopted upstream base
git diff split/base..main --stat                       # changes since the standalone split
gh pr list --state merged --label feature                 # features, with their reasons
```

## Typr features

The inherited base is recorded in [PORTS.md](PORTS.md).
Status: `switch` (has a switch in the app's Typr section),
`permanent` (no switch), `fix` (bug fix, never had a switch).
`pending` in the PR column means a change recorded before the PR-first rule,
without its own PR number.
The PR is the primary change reference. Use `—` in the Issue column when no
issue is needed; never create one just to fill the table. Multiple related PRs
may be listed for a feature. Documentation-only process changes need no feature row.

| Feature | Issue | PR | Status | Main files |
| --- | --- | --- | --- | --- |
| Dictation-log late-answer regression test: wait for cleanup hooks, completed fallback delivery and the correlated late answer instead of fixed sleeps, so slow simulator archive readiness cannot let the next dictation cancel the first | — | #89 | fix | ios/TyprTests/DictationLogControllerTests.swift |
| Settings redesign: Dictation before Preferences, with selected-value links to Speech engine, Language (single-line, label-only choices) and Style (described choices), both checkmarked; compact dark overview with purpose-based Keyboard, AI & vocabulary, Speech engine and History & feedback pages; no Typr/Experiments split; compact single-line menu entries with standalone icons (wrapping only for accessibility text), shared accessible rows, concise decision copy and expandable technical detail; unchanged settings keys, defaults and actions, including keyboard-feedback deep links and the selective setup checklist (explicit setup links return to it from any page) | — | #85, #86 (dictation grouping and explained choices) | permanent | ios/Typr/ContentView.swift, ios/Typr/SettingsComponents.swift, ios/Typr/SettingsPreferences.swift, ios/Typr/KeyboardSettingsCard.swift, ios/Typr/SpeechEngineCard.swift, ios/Typr/DictationSettingsCards.swift, ios/Typr/CustomVocabularyEditor.swift, ios/TyprTests/SettingsPresentationTests.swift |
| [AI cleanup](ios/AI_CLEANUP.md): on-device Apple Intelligence rewrites dictations into clear written text in every style but Verbatim (self-corrections, stutters/fillers, clumsy sentences, paragraphs, misheard words and technical terms from context: the text before the cursor or recent dictations), never translates English terms, writes English compounds without hyphens (deterministic pass), uses the vocabulary list as preferred spellings, with plain-transcript fallback; *Language* picker (Automatic / German / English) for Apple Speech and cleanup; last outcome shown in AI & vocabulary settings (the former model-display setting and row are removed). The inherited *Clean up with Apple Intelligence* experiment and its code are removed; this is the only AI cleanup path, and off runs no AI cleanup | — | #49, #52, #53, #55, #57, #75 (rewrite, language, context), #82 (inherited experiment removed) | switch | ios/Typr/TyprCleanup.swift, ios/Typr/CleanupGuard.swift, ios/Typr/CleanupPrompt.swift, ios/Typr/CleanupContext.swift, ios/Typr/CleanupHyphens.swift, ios/Typr/CleanupObservation.swift, ios/Typr/TyprAppleCleaner.swift, ios/Typr/DictationController.swift, ios/Typr/ContentView.swift, ios/TyprShared/DictationLanguage.swift, ios/TyprShared/KeyboardBridge.swift, ios/TyprShared/TyprSettings.swift, ios/Typr/SettingsPreferences.swift, ios/TyprTests/CleanupRewriteTests.swift |
| [Speech engines](ios/SPEECH_ENGINES.md): a *Speech engine* section lists Apple Speech, Parakeet V2 and Whisper Large V3 Turbo (WhisperKit 1.1.1, pinned Core ML model, about 629 MB) with languages and live OS/device/install/progress/failure status; the user's explicit choice is persisted and never falls back (no choice keeps the automatic Apple Speech / Parakeet behavior); Whisper downloads only from its Download button into Application Support (cancel/retry, verified sizes and local tokenizer before it is selectable), prepares offline on CPU and Neural Engine, gates silence, follows the Language picker (de/en/automatic) per dictation and gets vocabulary only as post-processing; an explicit Apple Speech language no longer falls back to another language; Parakeet warns it is English-only; switching is refused during a dictation and releases the previous model first | — | pending | permanent | ios/Typr/SpeechEngineCard.swift, ios/Typr/SpeechEngineProvider.swift, ios/Typr/WhisperTranscriber.swift, ios/Typr/WhisperTokenizer.swift, ios/Typr/WhisperModelInstaller.swift, ios/Typr/WhisperModelStore.swift, ios/Typr/WhisperModelSpec.swift, ios/TyprShared/SpeechEngineChoice.swift, ios/TyprShared/TyprSettings.swift, ios/TyprShared/DictationLanguage.swift, ios/Typr/AppleSpeechTranscriber.swift, ios/Typr/ParakeetTranscriber.swift, ios/Typr/DictationController.swift, ios/Typr/DictationLog.swift, ios/Typr/KeyboardSetup.swift, ios/Typr/ContentView.swift, ios/project.yml, ios/TyprTests/SpeechEngineSelectionTests.swift, ios/TyprTests/WhisperInstallerTests.swift, ios/TyprTests/WhisperTranscriberTests.swift |
| Whisper storage guard: before specializing Whisper (first load, after OS/Typr updates or an interrupted preparation, tracked in `typr-whisper-preparation.json`) require 4.5 GB free storage and otherwise stop with a clear message instead of being terminated by iOS; show *Loading Whisper* vs *Optimizing Whisper for this iPhone*; prewarm the models one at a time to lower peak memory during specialization | — | #84 | fix | ios/Typr/WhisperTranscriber.swift, ios/Typr/WhisperModelStore.swift, ios/Typr/WhisperModelSpec.swift, ios/Typr/DictationLog.swift, ios/SPEECH_ENGINES.md, ios/TyprTests/WhisperTranscriberTests.swift |
| Whisper preparation feedback: real sequential component steps and an animated activity indicator replace the fixed 15% bar in engine settings, recording stage and keyboard handoff; no elapsed time or invented percentages; measured download progress stays unchanged | — | #91 | fix | ios/Typr/WhisperTranscriber.swift, ios/Typr/ParakeetTranscriber.swift, ios/Typr/SpeechEngineCard.swift, ios/Typr/ContentView.swift, ios/Typr/KeyboardSetup.swift, ios/TyprTests/WhisperTranscriberTests.swift, ios/TyprTests/SpeechEngineSelectionTests.swift, ios/SPEECH_ENGINES.md |
| Whisper quiet-recording fix: lower the pre-inference amplitude floor from 0.02 to 0.005 RMS so quiet speech reaches the model; distinguish below-floor audio from empty decoder results in keyboard messages and log classification; real recorded-speech regression at reduced gain | — | #81 | fix | ios/Typr/WhisperTranscriber.swift, ios/Typr/DictationLog.swift, ios/TyprTests/WhisperTranscriberTests.swift, ios/TyprTests/SpeechEngineSelectionTests.swift, ios/SPEECH_ENGINES.md |
| [Dictation log](ios/DICTATION_LOG.md): durable on-device archive without automatic eviction; detail shows recognized text and AI correction (each with Copy) (only after a successful AI pass) and an inline expectations note, preserving legacy references, everything else under More details; new entries retain applied vocabulary replacements, not the complete unrelated saved dictionary (legacy snapshots remain readable); one-tap Good/Problem feedback, optional categories/reference/notes; complete versioned JSON file export and bounded recent text export. Off stops collection and keeps saved logs; only explicit Delete/Clear removes them (owner-approved retention exception) | — | #58, #59, #60, #61 (archive/feedback/JSON), #64 (feedback detail), #70 (vocabulary terms per entry), #78 (expectations note, accepted AI display, lean vocabulary evidence) | switch | ios/Typr/DictationLogArchive.swift, ios/Typr/DictationLogFeedbackView.swift, ios/Typr/DictationLog.swift, ios/Typr/DictationLogStorage.swift, ios/Typr/DictationLogView.swift, ios/Typr/DictationLogExport.swift, ios/Typr/DictationLogExportMenu.swift, ios/Typr/WordDiff.swift, ios/Typr/CleanupTextDiagnostics.swift, ios/Typr/TyprCleanup.swift, ios/Typr/DictationController.swift, ios/TyprShared/TyprSettings.swift, ios/Typr/SettingsPreferences.swift, ios/TyprTests/DictationLogImprovementTests.swift |
| [Tech terms before cleanup](ios/AI_CLEANUP.md#built-in-tech-glossary-and-sounds-like-forms-before-cleanup): built-in tech glossary fixes misheard developer terms (Pull Request, GitHub, gemergt, Orchestrator, pi Agent, herdr pane, …) before AI cleanup, real words only with fitting dictation context; its terms are Apple Speech hints after the user's and are named to cleanup when they appear; Custom vocabulary terms get optional sounds-like forms that win over the glossary; replacements logged as `built-in`. Filler trim keeps German "um"/"er", no capital after bzw./z. B./d. h. | — | #74 | permanent | ios/Typr/TechGlossary.swift, ios/Typr/DictationVocabulary.swift, ios/TyprShared/VocabularySpelling.swift, ios/TyprShared/CustomVocabularySettings.swift, ios/Typr/CustomVocabularyEditor.swift, ios/TyprShared/TranscriptFormatter.swift, ios/Typr/DictationController.swift, ios/Typr/DictationLog.swift, ios/TyprTests/TechGlossaryTests.swift |
| [Local dictation report](ios/tools/dictation_log/README.md): explicit offline Python import/report, private SQLite and raw evidence outside Git, revision-safe merge, HMAC settings fingerprints and bounded reference-only metrics; no app/runtime changes | — | #63 | permanent | ios/tools/dictation_log/archive.py, ios/tools/dictation_log/store.py, ios/tools/dictation_log/report.py, ios/tools/dictation_log/cli.py, ios/tools/dictation_log/tests/test_dictation_log.py |
| Keyboard quick feedback: exact newly inserted result, identical shared full-panel Good/Problem on both keyboards (Good or ✕ closes at once; Problem leaves *Feedback in Typr* and ✕ for six seconds; failed queuing restores Retry); cold starts wait for archive readiness and job ownership survives keyboard recreation; *Feedback in Typr* opens the exact entry’s free-form expectations note, with unchanged original recognition and accepted AI output only; durable text-free queue; honest Noted, archive commit before removal | — | #62, #64, #73, #78 (shared panel and cold-start ownership/readiness) | switch | ios/TyprShared/DictationFeedback.swift, ios/TyprShared/DictationFeedbackBridge.swift, ios/TyprShared/TyprFeedbackTray.swift, ios/TyprShared/FullKeyboard/TyprFeedbackPanel.swift, ios/TyprShared/FullKeyboard/FullKeyboardView.swift, ios/TyprShared/TyprFeedbackLink.swift, ios/Typr/TyprFeedbackRouter.swift, ios/Typr/TyprApp.swift, ios/TyprShared/TyprSettings.swift, ios/Typr/SettingsPreferences.swift, ios/TyprKeyboard/KeyboardViewController.swift, ios/Typr/DictationLog.swift, ios/Typr/DictationController.swift, ios/TyprShared/FullKeyboard/KeyboardStripView.swift, ios/TyprShared/KeyboardSurface.swift, ios/TyprTests/DictationKeyboardFeedbackTests.swift |
| Automatic return to the app you dictated in: after a cold start Typr returns to the keyboard's host app, detected via UIKit's keyboard arbiter (private API), opened by bundle ID (private `LSApplicationWorkspace`), else its resuming URL, else swipe back; refuses to open Typr from share sheets and other surfaces it cannot return to. Replaces the manual *Return to* app choice, the keyboard return tray and the handoff screen's quick-jump chips | — | #71 | permanent | ios/TyprKeyboard/KeyboardHost.swift, ios/TyprKeyboard/KeyboardArbiter.c, ios/TyprShared/HostReturnCatalog.swift, ios/Typr/HostReturner.swift, ios/Typr/DictationController.swift, ios/TyprKeyboard/KeyboardViewController.swift, ios/TyprShared/KeyboardBridge.swift, ios/TyprShared/KeyboardSurface.swift, ios/TyprShared/FullKeyboard/FullKeyboardView.swift, ios/TyprShared/FullKeyboard/TyprKeyViews.swift, ios/Typr/ContentView.swift, ios/TyprTests/HostReturnCatalogTests.swift, ios/TyprTests/DictationControllerTests.swift |
| Typr wordmark optically centered in the app icon, keyboard key and Dynamic Island minimal (shifted right/down from its geometric bounds); header marks unchanged | — | #69 | fix | ios/Branding/generate.py, ios/Branding/TyprWordmark.swift, ios/AppIcon.icon/Assets/Image.png, ios/TyprShared/FullKeyboard/FullKeyboardPalette.swift, ios/TyprShared/TyprTheme.swift, ios/TyprWidgets/TyprDictationLiveActivity.swift |
| Typr keyboard no longer falls back to the iOS keyboard (Swift 6 lexicon crash) | #31 | pending | fix | ios/TyprKeyboard/KeyboardViewController.swift, ios/TyprShared/FullKeyboard/LexiconDelivery.swift |
| Autocorrect languages: independently select Deutsch and English below Autocorrect (both default on); German ae/oe/ue/ss → ä/ö/ü/ß and typo fixes remain, English contractions/typos run only when selected; replaces the German autocorrect experiment | #33 | pending | permanent | ios/TyprShared/FullKeyboard/GermanAutocorrect.swift, ios/TyprShared/FullKeyboard/AutocorrectEngine.swift, ios/TyprShared/FullKeyboard/FullKeyboardView.swift, ios/TyprShared/TyprSettings.swift, ios/Typr/KeyboardSettingsCard.swift, ios/TyprTests/GermanAutocorrectTests.swift |
| Microphone startup resilience (CarPlay / audio-route changes): use a fresh input graph with its native tap format; contain AVFAudio Objective-C exceptions and discard failed graphs so startup reports a recoverable error rather than terminating the app; successful warm sessions remain running between dictations | — | #90 | fix | ios/Typr/AudioBackend.swift, ios/Typr/TyprAudioInput.h, ios/Typr/TyprAudioInput.m, ios/Typr/Typr-Bridging-Header.h, ios/project.yml, ios/TyprTests/AudioInputTests.m |
| Keep mic warm stays hot after a keyboard dictation (no trip back into the app for the next one) | #42 | pending | fix | ios/Typr/AudioBackend.swift, ios/Typr/DictationController.swift |
| Keyboard switch key (always enabled with the full keyboard; no setting): tap on the dictation bar shows the full keyboard; on the full keyboard, slide down on the Typr key shows the dictation bar (replaces the separate switch key) | #44 | #45, #72 | permanent | ios/TyprShared/FullKeyboard/KeyboardSurfaceChoice.swift, ios/TyprShared/FullKeyboard/TyprKeyGesture.swift, ios/TyprKeyboard/KeyboardViewController.swift, ios/TyprShared/FullKeyboard/FullKeyboardView.swift, ios/TyprShared/KeyboardSurface.swift, ios/TyprShared/TyprSettings.swift |
| Hide suggestion bar: the full keyboard without the bar above the keys (portrait 224 instead of 253 pt), top-row key previews widen the key in place, Typr messages use the feedback panel, autocorrect on space still applies; the full keyboard's *Undo dictation* chip is removed | — | #73 | switch | ios/TyprShared/TyprSettings.swift, ios/Typr/KeyboardSettingsCard.swift, ios/TyprShared/FullKeyboard/KeyboardLayout.swift, ios/TyprShared/FullKeyboard/FullKeyboardEngine.swift, ios/TyprShared/FullKeyboard/FullKeyboardView.swift, ios/TyprShared/FullKeyboard/KeyboardStripView.swift, ios/TyprShared/FullKeyboard/KeyboardKeyPlaneView.swift, ios/TyprTests/SuggestionBarTests.swift, ios/TyprTests/KeyboardLayoutTests.swift |
| Full keyboard Typr key: a quick tap types a space like the space bar; hold dictates and slide up opens the style menu as before | — | #72 | permanent | ios/TyprShared/FullKeyboard/TyprKeyGesture.swift, ios/TyprShared/FullKeyboard/TyprKeyViews.swift, ios/TyprShared/FullKeyboard/FullKeyboardView.swift, ios/TyprShared/FullKeyboard/FullKeyboardEngine.swift |
| [Hyphens as spaces](ios/AI_CLEANUP.md#language-context-and-hyphens): in every style including Verbatim, before spelling and AI cleanup, hyphens between words become spaces ("Pull-Request", "Feedback-Menü", "Know-how" → "Pull Request", "Feedback Menü", "Know how"); kept after a single letter (E-Mail), between numbers (5-10), in links and in hyphenated Custom vocabulary terms; an accepted AI answer may write hyphens at its own discretion (only the conservative English-term pass runs over it) | — | #88 | permanent | ios/Typr/CleanupHyphens.swift, ios/Typr/DictationController.swift, ios/Typr/DictationSettingsCards.swift, ios/TyprTests/CleanupRewriteTests.swift |

## Asking for work (owner)

- **Default: develop here with Pi.** Describe the change in the conversation;
  Pi clarifies requirements as needed, implements on `feature/<name>`, performs
  appropriate checks and opens a PR to `main`. No issue is needed. Use a
  draft PR if an early durable work-in-progress record helps. The PR preserves
  the agreed behaviour, decisions and verification; lasting product or
  architecture rules belong in repository documentation. Existing CI, merge
  requirements and distribution rules still apply. To try a PR before it
  merges, run **Typr PR to iPhone** with its number.
- **Review agent (automatic).** Every same-repository PR into `main`
  (`feature/*`, `fix/*`, `infra/*`, …)
  is reviewed by Claude (`typr-review.yml`, Opus, read-only) when it is
  opened, reopened or marked ready, and again after **every new commit**; a
  newer commit cancels the review of the older one. The verdict is one sticky
  PR comment for exactly the reviewed commit, and the check **Typr review**:
  - `✅ PASS — nothing to fix`: check green.
  - `❌ FIX — N thing(s) to fix`: check red, with a numbered list (file, line,
    problem, fix). Optional remarks sit collapsed under *Optional notes* and
    never change the verdict.
  - `⚠️ NO RESULT`: the review could not finish (usage limit, timeout); re-run
    the failed job once; if it still has no result, inform the owner.
  Agents working on a PR: read the latest Typr review comment, fix every
  numbered finding, push, and wait for the next verdict. The check is not a
  required status check, so the owner can still merge deliberately.
- **Changes to a PR:** ask Pi here to continue on that branch; the push starts
  a new review.
- **The loop, end to end** (nothing merges by itself; no repair agent runs in CI):

  ```ts
  Pi: develop on feature/<name> → commit → push → PR (label feature)
  ├─ automatic: Typr review + PR CI (Linux checks, Decide, Unsigned archive)
  ├─ ❌ FIX → in the same Pi session (a new one if the context is long or stale):
  │          "read the Typr review comment and fix the findings" → commit → push → review again
  ├─ ✅ PASS + checks green → owner: "merge" → squash merge
  └─ main: archive → TestFlight at once; simulator tests in parallel
     └─ tests red → status issue + GitHub mail → Pi: "main CI is red, read
        `gh run view <id> --log-failed` and fix it" → branch fix/<name> → PR → same loop
  ```

  TestFlight deliberately does not wait for the tests: try the build on the
  iPhone at once and fix in parallel.
- **Removing a feature:**
  1. Not merged yet: close the PR.
  2. Merged, just not wanted right now: if it has a switch, turn it off in the app's Typr section.
  3. For good: on the merged feature PR click **Revert**, then squash-merge the
     revert PR. For a feature spanning several PRs, revert the relevant commits
     together, accounting for dependencies. Remove its table row only when the
     whole feature is removed; PRs and any existing issue stay as history.
     Reverting the revert brings it back.
  4. The revert conflicts (a later feature builds on it): ask Pi to remove the
     feature while preserving the dependent behaviour.
  Agents: a revert is mechanical; prefer GitHub's Revert over rewriting code.
- **Automation changes** need the `infra` label. Adding it re-runs the PR's failed
  Typr CI jobs by itself (`typr-recheck.yml`; the scope check reads labels live).
  Other label events start no CI run (as in OpenCode).
  Draft PRs get only the Linux checks until marked ready.
- **A merge conflict:** resolve a feature or fix PR locally with Pi. Fetch
  `origin` successfully, merge the freshly fetched `origin/main` into its
  branch, resolve, then push (the review runs again). Do not use a stale local
  `main` as the integration source.

The review agent is the only agent in CI. It uses the owner's Claude
subscription (`CLAUDE_CODE_OAUTH_TOKEN`, environment `typr-agent`) and has
no signing secrets. The review runs as `pull_request_target` from `main`'s copy of
its workflow, so a PR cannot change its own reviewer; it only reads the PR's
code and never runs it. The previous automation (issue/`@claude` agent,
Typr fix repair agent, automatic conflict resolver) is kept on branch
`backup/workflows-2026-11-08`.

## How the pipeline works

The pinned issue **Typr status** is refreshed after each main push CI run,
weekly on Monday at 06:17 UTC for renewal warnings, or manually. Under
*Needs you* it lists red main CI runs and `needs-human` issues. It also shows
the last TestFlight upload, open PRs and upcoming renewals from `expiry.json`.

```ts
Typr CI (fast lane: only Linux checks and compiling block; tests never hold anything up)
├─ Linux checks: CI helper + offline dictation-log tests, actionlint, shell syntax; scope on PRs
├─ Decide: did the app change (pushes to main) / the app or Typr CI scripts (PRs)? no → stop
├─ PRs: required archive, no simulator/screenshots
├─ Push to main with app changes: archive and simulator tests in parallel
│  └─ Test failures → status issue → fix locally → fix/<name> PR → review → merge → tests again
├─ Manual simulator mode: tests + screenshot artifacts, no device archive/signing
└─ Sign
   ├─ push to main → TestFlight as soon as the archive compiled
   └─ by hand → ad-hoc (main or feature/*, needs approval) or testflight

Typr review (every same-repository PR, every new commit)
├─ sticky comment "reviewing <sha>" → Claude (Opus, read-only) reviews the PR diff
└─ ✅ PASS (check green) | ❌ FIX + numbered findings (check red) | ⚠️ NO RESULT (re-run)

Typr PR to iPhone (by hand, from main, enter an open feature PR number)
├─ Verify current PR commit, successful Linux checks, Decide and unsigned archive
├─ No automatic PR simulator tests; optional manual checks do not block signing
├─ Your approval in typr-ad-hoc
├─ Revalidate PR, download existing archive, check GitHub SHA-256 and build provenance
└─ Sign → encrypted ad-hoc IPA (no rebuild, no TestFlight upload)
```

`main` only moves forward: `git pull --ff-only` always works locally.
Branch rules: changes reach `main` through PRs with green `Linux checks`,
`Decide` and `Unsigned archive` (skipped counts as passed);
no force pushes or deletion. Repository admins can bypass; the owner decides
when to merge. Nothing merges by itself.

### Automatic runner-capacity retries

`Typr runner retry` watches completed Typr CI and PR-to-iPhone workflows.
When GitHub explicitly reports that a hosted macOS job could not acquire a
runner, it retries that job after 5, 10, then 20 minutes. The job must have no
assigned runner and no executed steps. Real test/build failures, user-cancelled
runs, foreign repositories and unrelated workflows are never retried this way.
The wait uses a Linux runner, not a macOS runner; no agent or signing secret is
used. Control code always comes from trusted `main`, never the failed branch.

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

Typr's identity is committed in `ios/` and mirrored in
`.github/typr/app.json`: app `dev.rudek.typr`, extensions
`dev.rudek.typr.keyboard` and `dev.rudek.typr.widgets`, tests
`dev.rudek.typr.tests`, App Group `group.dev.rudek.typr` (app and keyboard
only), URL scheme `typr`, display name **Typr**, team `2ZNGF24932`.
`identity.py` validates source and configuration without rewriting them.
App Store Connect is **Typr Keyboard** (app ID `6832515139`, SKU `typr`);
internal TestFlight group **Typr Internal**.

Signing profiles are named `Typr Ad Hoc <bundle>` or `Typr App Store <bundle>`.
The local profile directories and ZIPs are `typr-ad-hoc` /
`typr-testflight` and `typr-<distribution>-profiles.zip` under
`~/.local/share/ios-build-signing/`.
CI uses environments `typr-ad-hoc` (owner approval), `typr-testflight` and
`typr-agent`. The owner must set `CLAUDE_CODE_OAUTH_TOKEN` in `typr-agent`;
GitHub cannot copy the old environment's write-only secret.

## Owner commands

```sh
# Fast path: sign the existing compiled feature PR archive (no rebuild, no test wait).
# Run from main, enter the PR number, approve on the run page:
gh workflow run typr-ad-hoc.yml -R hrudek/typr --ref main -f pr=123

# Optional pre-merge simulator tests + screenshots (no device archive/signing):
gh workflow run typr-ci.yml -R hrudek/typr --ref feature/NAME \
  -f distribution=simulator -f scenes=keyboard-transcribing,full-keyboard-numbers-dark
# Download screenshots from that run's typr-screenshots-RUN_ID artifact.
# only_testing optionally restricts tests; none skips the simulator job and screenshots.

# Fallback: build a fresh ad-hoc archive of main or a feature branch:
gh workflow run typr-ci.yml -R hrudek/typr --ref feature/NAME -f distribution=ad-hoc

# For either path, RUN_ID below is the signing workflow's run ID:

gh run download -R hrudek/typr RUN_ID --pattern 'typr-ad-hoc-*' --dir ~/code/typr-downloads/RUN_ID
age --decrypt --identity ~/.local/share/ios-build-signing/artifacts.agekey \
  --output Typr.ipa ~/code/typr-downloads/RUN_ID/typr-ad-hoc-RUN_ID/Typr.ipa.age
~/code/apple-dev-setup/iphone-wifi install "$PWD/Typr.ipa"

# TestFlight happens on its own for every main change to the app; by hand:
gh workflow run typr-ci.yml -R hrudek/typr -f distribution=testflight

# Profiles (local only, uses ~/.local/share/ios-build-signing):
python3 -I .github/typr/provision.py ad-hoc|testflight

# CI scripts and offline dictation-log tooling on Linux:
python3 -m unittest discover -s .github/typr/tests
python3 -m unittest discover -s ios/tools/dictation_log/tests
```

The fast path accepts only open, non-draft `feature/*` PRs from this repository
into `main`. It requires the latest PR CI run for the current head commit,
with `Linux checks`, `Decide` and `Unsigned archive` successful (none may be
skipped). PRs do not automatically run simulator tests or screenshots. Optional
manual simulator checks do not gate archive reuse. Automated simulator tests run
on `main` after app changes.
A cancelled or not-yet-started CI run is refused. It checks again after approval;
if the PR changed, rerun once the new commit's required jobs pass.
Artifacts expire after seven days: rerun PR CI if the archive is missing or
expired, or use the fresh-build fallback. A changed Typr identity also requires
a new PR build. Signing uses only control scripts from `main`, never scripts
from the PR; no signing secrets reach the PR build. The reused IPA keeps the
original archive's build number and `build.json`. Merging still creates a fresh
TestFlight build as before. Archive selection, provenance, digest and ZIP checks
have Linux unit tests; these do not prove Xcode export or installation on a real
iPhone.

All Typr builds share one bundle ID: an ad-hoc install replaces the Typr
TestFlight version on the iPhone (data stays). Typr has a new bundle ID and
App Group, so it installs separately from Hex+; this rebrand does not copy the
old app's settings, dictation logs or keyboard feedback into Typr. If GitHub's macOS runners are short on
capacity, set the variable `MACOS_RUNNER` (now `macos-15-intel`; the default
is `macos-26`). The only configured remote is `origin` = `hrudek/typr`.
External code is adopted deliberately through [PORTS.md](PORTS.md), not synced.
