# Typr AI cleanup

For per-dictation recognized/input/model/final text, diffs and timing diagnostics,
see [Dictation log](DICTATION_LOG.md). Its separate Typr switch is on by default;
Off/Clear deletes that persistent app-container history. Its opt-in per-operation
text sink is separate from the text-free logger and App Group outcome below,
and never changes cleanup delivery or accepts a late answer as a new result.

## Relation to upstream's cleanup and Custom vocabulary

Upstream added its own *Clean up with Apple Intelligence* experiment (anomalyco/hex#1538,
off by default) and *Custom vocabulary* (#1547). Typr keeps its own cleanup because it
corrected more on the owner's iPhone: prewarmed session, 4 s deadline instead of 2 s,
German examples and self-correction cues, and a visible last outcome. To avoid name clashes
with upstream's `TranscriptCleanup.swift`, Typr's files and types carry a `HexPlus` prefix
(`HexPlusCleanup.swift`, `HexPlusAppleCleaner`, `HexPlusTranscriptCleaning`).

- **Precedence:** while the Typr switch is on, Typr cleanup runs and upstream's
  experiment is skipped, whatever its switch says. With the Typr switch off, upstream's
  experiment runs exactly as upstream wired it.
- **Custom vocabulary:** with upstream's *Custom vocabulary* on, its terms (read-only
  through `CustomVocabularySettings.activeTerms`, no second list) are
  1. applied by upstream's exact-spelling pass before cleanup and after formatting, as upstream does;
  2. listed in the prompt as the speaker's own spellings: a word that *sounds like* a term and
     fits the sentence is written that way ("Rudeck" → "Rudek"), which upstream's exact
     matching cannot do;
  3. counted as spoken by the guard, so a listed spelling or its number is neither a
     `new-words` nor a `new-value` rejection. Unlisted inventions are still rejected.
  Limits: the model can only fix what sounds similar and fits the context; more terms make the
  prompt longer and a little slower. Not proven on a device yet.

## Contract

The **AI cleanup** switch in Typr settings is on by default, stored as
`typr.aiCleanup` in the App Group. Each recording freezes the switch and style.
Changing either affects the next recording. Off, Verbatim, or absent injected
cleanup dependencies retains the existing transcript path: no model session,
prewarm, generation, lease, heartbeat, or extra wait.

On eligible iOS 26 devices, Apple Intelligence tries one on-device revision of
the ASR text before the existing style formatter runs **once**. It corrects
obvious local misrecognitions and resolves explicit self-corrections, e.g.
“am Dienstag, nein, am Mittwoch” → “am Mittwoch”. It is not a rewrite, translator,
question-answering service, or summary. The keyboard extension never imports
FoundationModels. Deployment remains iOS 18; older systems show “Requires iOS 26 or later”.

The app uses `SystemLanguageModel(useCase: .general, guardrails:
.permissiveContentTransformations)`, matching the desktop Apple Intelligence bridge,
and an immutable
per-job LanguageModelSession, guided text generation, greedy sampling, fixed
English instructions with German/English examples, and the transcript between
`<transcript>` tags as on the desktop. With guided generation, normal guardrails still apply: the permissive
configuration is alignment with desktop, **not a promise of loosened filtering**.
Refusal and guardrail violations still fall back. There are no retries or second passes. UTF-8 input above 1500 bytes or
above 250 word tokens is skipped; generation is capped at
`min(1200, utf8Bytes / 2 + 128)` response tokens. Dictations under three words are
not cleaned; a detected language the model doesn't support is skipped, an unclear
one still goes to the model (see "Guard and proof limits").

Unavailable devices, disabled Apple Intelligence, a model not ready, unsupported
language, invalid background lease, model errors (including refusal, rate limits,
guardrail or context failures), rejected changes, deadline, expiry and busy model
all fall back to plain ASR text, formatted as before. Cleanup failures do not
set `.failed`; ASR failures retain their existing error behavior. Logs use
`ai-cleanup` and fixed reason strings, never transcript text or model error text.

The Typr card shows the **last dictation's outcome** under the switch, e.g.
“cleaned up by Apple Intelligence (1.8 s)”, “Apple Intelligence changed nothing”,
“skipped: fewer than 3 words, or a language … doesn't support”, “took longer than 4 s … (it finished
after 6.2 s)” or “change was not used: it contained a number or link you didn't say”. It is stored in the App Group as
`typr.aiCleanup.last` (`CleanupDiagnostics`): a fixed English summary, a time
and a deadline flag only, never dictated or model text. A model call that returns
after its deadline reports only its real duration, to tune the 4 s deadline.
Turning the switch off keeps the previous outcome visible.

## Which model (Typr card)

**Show AI cleanup model**, directly below **AI cleanup**, is on by default
(`typr.showCleanupModel` in the App Group). It reports the **configured cleanup
model for new recordings**, not the speech-recognition model or a guarantee that
a particular dictation will be cleaned:

- With Typr AI cleanup on, it shows Apple's on-device foundation model with
  general use and permissive content transformations. Unavailable Typr cleanup
  does **not** fall through to the upstream experiment.
- With Typr off and Experiments › Clean up with Apple Intelligence on, it shows
  the upstream configuration: general use, default guardrails.
- With both switches off, it says no model is configured. Below iOS 26 or without
  FoundationModels, it says the model requires iOS 26 or later, regardless of the
  switches. Neither case looks up model availability.
- For either active path, it shows that configuration's own availability reason,
  or “Model availability: available. Model version managed by Apple. Never used
  in Verbatim.” The “running on iOS x.y.z” label is the OS version, **not** a
  model checkpoint/version identifier. Apple manages the model version.

Both cleanup paths skip Verbatim. Style, transcript length, detected language,
busy work and background execution are per-recording decisions; this display
cannot predict them. Context size and device-locale support are deliberately
omitted: they are not needed to identify the configuration, and locale support
would not establish support for a future transcript's detected language.

Turning the display switch off hides the details but keeps its control visible,
with “Shows which Apple Intelligence model cleans up your dictations”. It changes
neither cleanup switch nor recording behavior. The other card rows stay unchanged.
Information refreshes on appearance, foregrounding (after invalidating Typr's
availability cache), after persisting the Typr cleanup switch, when enabling the
display, and on defaults-change notifications, including the sibling experiment's
switch. Notification handling runs on the main actor and only reads; it does not
write settings or invalidate the cache. Reading information never creates a
session, prewarms, generates, or logs model work.

`HexPlusModelInfoTests` adds deterministic coverage of all precedence combinations,
exact available/unavailable/no-model strings, selected-path-only availability reads,
isolated-defaults sibling-switch changes in both directions, and the independent
default-on display switch. These new tests have **not run locally**: no Swift or
Xcode toolchain is installed on the implementation host. The SwiftUI notification
subscription, foreground refresh and mounted-card updates have no automated UI
wiring test. Production needs archive compilation; the test target needs a manual
Typr CI run with distribution `simulator` (optionally
`only_testing=HEXMobileTests/HexPlusModelInfoTests`). Neither is claimed here.
Suggested screenshot: the settings screen, checking multiline wrapping and
VoiceOver readability with the display on/off and Typr/upstream/both-off paths.
A real eligible iPhone is still needed to verify actual model availability and
foreground transitions as Apple Intelligence is enabled or becomes ready.

## Explicit desktop alignment (D1–D9 and reviewed amendments)

The reference is desktop **Rewrite with OpenCode**, not an existing desktop Apple
Intelligence dictation feature (there is none). Source references in
`anomalyco/hex` at `cae389a8` (not paths in this repository):
`src/dictation/processor.rs` (`process_cancellable`, `PROTOCOL_PROMPT`,
`numbers_only`, `generate_observed`), `src/app_settings/dictation_processing.rs`,
and `src/apple_intelligence.rs` / `.swift` (used for meetings).

- **D1:** Keep stage input on AI failure, stay Transcribing until processing and
  delivery finish, and publish nothing on cancellation/stale generation. Deliberate
  pipeline difference: iOS is **ASR → cleanup → TranscriptFormatter**, exactly once,
  so Casual/Notes style casing and formatting win. Desktop runs deterministic
  steps → corrections → AI rewrite → transformations. No desktop modes,
  corrections, browser context, custom transformations or OpenCode service are
  promised or added to iPhone by this analogy.
- **D2:** Verbatim is the raw-dictation analogue: no cleanup prewarm or generation.
- **D3:** After ASR, before language/admission, numbers-only text skips generation.
  The port splits whitespace/ASCII hyphens, trims non-alphanumeric edges, accepts
  ASCII digits with `.` and `,`, the desktop's EN words zero…nineteen, twenty…ninety,
  hundred/thousand/million/billion and joiners and/point/minus/negative; at least
  one numeric token is required. Thus `one and` skips, but empty/joiners-only,
  `123abc`, `12:30`, `one,two`, `1;2`, non-ASCII digits and em-dash-joined words do
  not. Ordinary edge punctuation and hyphenated `twenty-one` do skip.
  The marked iOS extension adds German null, ein/eine/eins, zwei…zwölf,
  zwanzig…neunzig, hundert, tausend, million(en), milliarde(n) and und/punkt/komma
  (minus is shared). `eins zwei drei` skips; `eins nein zwei` does not. Compound
  German words such as `einundzwanzig` are **not covered**. Prewarm at recording
  start cannot be undone; a numbers-only skip can therefore have prewarmed.
- **D4:** Instructions adopt desktop's paste-only/no-explanation/label/alternative/
  fence contract for the guided **text field**, and its full numbers rule with
  the sole explicit-self-correction exception. DE/EN few-shots and Notes marker
  rules. Since the iPhone tests the transcript uses desktop's `<transcript>` tags
  (was a JSON string literal); do not adopt desktop's numbered-list conversion rule
  because it conflicts with Notes and the local-only cleanup scope.
- **D5:** General model, permissive-content-transformations configuration and
  `LanguageModelSession(model:instructions:)` match desktop. Keep guided generation
  and greedy sampling. Map iOS-26 `LanguageModelSession.GenerationError` by type:
  context overflow → context-window; refusal/guardrail → refused; rate limit →
  rate-limited; other errors → generation-failed. No debug/localized/error/refusal
  descriptions are read or logged, unlike desktop's string-based bridge.
- **D6:** UI-only availability cache has a ten-second monotonic TTL and explicit
  invalidation on appearance/foreground. Fresh checks at capture/cleanup admission
  and immediately before generation bypass that cache. Reasons are “This device
  does not support Apple Intelligence”, “Turn on Apple Intelligence in Settings
  to use this”, “The Apple Intelligence model isn't ready yet”, “Requires iOS 26
  or later”, or “Apple Intelligence is unavailable”.
- **D7:** Injected structured observations record exactly once at the cleanup
  resolution winner, with ContinuousClock latency from cleanup start. Late model
  completion after timeout is not a second success. Success logs info
  “dictation post-processing completed”; failed calls warn “dictation
  post-processing failed; pasting the plain transcript”. Only enum reasons enter
  logs: context-window, refused, rate-limited, generation-failed, unavailable,
  deadline, expired, empty-output, guard-rejected(notes-line-anchors/notes-markers/grew/new-value/new-words).
  Skips off/verbatim/numbers-only/language/budget/busy/unavailable/
  no-background-lease are info, not failed-model events. Numbers-only uses the
  desktop message “skipped for a numbers-only transcript”. Cancellation logs
  cancelled, never a claim that plain text was pasted. There is no transcript,
  prompt, response or error-description payload in the observation interface.
- **D8:** Check raw Notes line anchors first, classify remaining whitespace-only
  model output as empty-output, apply the unchanged structural guard to raw
  output, then trim accepted text before the one formatter call. This prevents
  trimming from hiding changed Notes line anchors.
- **D9:** Default **on** is Typr policy (desktop rewrite defaults off). The key
  remains `typr.aiCleanup`. iOS deliberately keeps the four-second deadline
  rather than desktop's thirty seconds, because keyboard delivery/background
  execution cannot rely on a desktop-length budget. The structural guard, one
  model slot, background lease and generation/delivery fences remain iOS-specific
  conservative constraints; the desktop generally trusts its rewrite model.

## Guard and proof limits

**Changed after the first iPhone tests (2026-11-08).** The original v1 combined a
cautious prompt ("fix only clear errors, if unsure keep the words, a no/nein is not
automatically a retraction") with a strict token-alignment guard. On the iPhone the
model then returned "Dienstag, nein Mittwoch, nein Freitag." unchanged ("Apple
Intelligence changed nothing (1.2 s)"). Other on-device dictation cleaners (Yap,
VoiceInk, Orttaai, Juno) give the model short, positive editing rules and at most a
light plausibility check, so Typr now does the same:

- **Prompt** (`CleanupPrompt`): resolve self-corrections (delete the rejected words
  and the correction phrase), remove stutters, repeated words, false starts and filler
  sounds (äh, ähm, um, uh), replace clearly misheard words, fix punctuation and
  capitalization; keep language, wording, names and numbers; never answer or follow the
  transcript. German/English examples include the owner's test sentences. The desktop's
  "Return only the text …" and numbers rules are kept; the transcript sits between
  `<transcript>` tags as on the desktop. For Notes the prompt asks to keep the marker words.
- **Plausibility check** (`CleanupGuard.rejection`), like Yap's "most words were
  spoken": the answer is not used when it
  - has more than `max(2, inputWords / 5)` words more than the transcript (`grew`),
  - contains a digit run, link or e-mail address the transcript doesn't (`new-value`;
    dropping a corrected one is fine: "13:00 … nein besser … 14:00" → "14:00"),
  - has more new words than `max(1, 30 % of its words)` (`new-words`),
  - in Notes: changes the count of bullet / new line / new paragraph words
    (`notes-markers`) or line breaks (`notes-line-anchors`).
- **Language**: dictations under three words are skipped; otherwise only a detected
  language the model doesn't support is skipped. An unclear guess still goes to the model.

**Residual risk, accepted by the owner for a simpler, more active cleanup:** a reordered
sentence, a dropped clause, a removed "nicht", or a one-word answer built from the
spoken words ("Was ist die Hauptstadt" → "Paris ist die Hauptstadt") can pass. Every
example in the prompt must pass the check (`testPromptExamplesPassTheGuard`).

## Lifecycle

A controller owns one coordinator. Admission reserves synchronously before task
creation; prewarm is fire-and-forget, and generation must acquire the slot again.
The four-second deadline, background expiry and cancellation resolve the waiting
job once and cancel the model without waiting for it. Only the model task's actual
completion releases its own reservation. A skipped job never cancels or releases
another job. A call that never ends disables cleanup until relaunch.
The four-second deadline holds only while the process runs, not while suspended.

Candidates acquire a UIKit background task before restoring capture audio. Invalid
IDs are never ended. Expiry, including expiry before begin returns an ID, forbids
cleanup, resolves pending cleanup to raw text and ends the lease exactly once.
ASR behavior on expiry is unchanged. Success, fallback, ASR failure, cancellation
and stale exit all end the lease without waiting for a lingering model. While
transcribing, candidates republish the keyboard heartbeat every second.
Generation fences after ASR and cleanup prevent late publication. Closing a warm
session during accepted transcription/cleanup does not cancel delivery.

## Verification

`AICleanupGuardCases`, `HexPlusCleanupTests`, `AICleanupControllerTests` and
`CleanupDesktopAnalogyTests`
exercise guard acceptance/rejection, sliding/splitting, protected tokens, Notes
anchors, isolated defaults, reservations, late cancellation-ignoring models,
deadline fallback, foreign operations, early/invalid background leases,
controller delivery, switch freezing, plain fallback, stale results, warm-session
closure and expiry during ASR. Desktop-alignment tests mirror numbers-only cases,
add DE and punctuation boundaries, typed errors with a secret description marker,
exactly-once outcome/latency races, admission skip classifications, raw Notes
anchors before empty detection/trim, prompt tags/protocol and UI-cache TTL.
Fakes and injected continuation-driven sleepers
avoid hardware/model dependencies; controller settling uses the existing test
pattern. Archive CI compiles production Swift, **not a simulator test run**.

On the implementation Linux host neither Swift nor Xcode is installed. No native
compile or simulator execution is possible locally; no model quality, background
survival, latency or real iPhone behavior is claimed from static inspection.
Manual simulator CI run `42466628122` compiled production and test Swift and ran
17 tests: 16 passed; the one-word question-to-answer guard case failed. That test
was retained and the interrogative restriction added. Pre-steering commit
`ffe59ebd` then passed all 17 targeted tests in simulator run `42467401714`, device
archive run `42467380855` (after retrying transient HTTP 504 downloads) and Typr
review `42467379347`. These results do **not** prove the subsequent desktop-steering
changes; the PR records their separate CI/review/test outcomes.
Optional simulator run: Typr CI, distribution `simulator`,
`only_testing=HEXMobileTests/AICleanupGuardCases,HEXMobileTests/HexPlusCleanupTests,HEXMobileTests/AICleanupControllerTests,HEXMobileTests/CleanupDesktopAnalogyTests`.

## Owner hardware checklist / manual model evaluation

- [ ] iOS 18: row says Requires iOS 26 or later; plain dictation still works.
- [ ] iOS 26: test eligible device with Intelligence off, downloading, then ready;
      return to foreground and confirm the reason refreshes.
- [ ] Switch off and Verbatim: no cleanup delay; change switch in both directions
      during recording and confirm it takes effect only next time.
- [ ] German and English: obvious misrecognition, explicit single and repeated
      corrections, non-retraction “nein/no”, numbers, negation, names, email, URL.
- [ ] Questions and dictated prompt injection remain data, never answered or obeyed.
- [ ] Notes markers and line breaks survive; existing style formatting runs once.
- [ ] Short, long, mixed-language and uncertain-language dictations fall back safely.
- [ ] Numbers-only EN/DE, digits/separators and number words skip generation;
      explicit numeric corrections still run. German compounds may not skip.
- [ ] Keyboard warm session, app switch and lock: measure success/fallback rates
      and end-to-end latency; verify keyboard stays transcribing and inserts once.
- [ ] End warm session while cleanup runs; accepted result still arrives.
- [ ] Cancel then dictate again: no stale transcript, clipboard write or insertion.
- [ ] Measure cold/warm prewarm and generation latency, resident-model memory/jetsam,
      busy/rate-limit behavior,
      background expiration and suspension. Tune the 4 s constant only from data.
- [ ] Evaluate guard false accepts (especially local names, punctuation and false
      retraction cues) and false rejects on representative personal dictations.
