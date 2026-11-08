# Hex+ AI cleanup

## Contract

The **AI cleanup** switch in Hex+ settings is on by default, stored as
`hexplus.aiCleanup` in the App Group. Each recording freezes the switch and style.
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
English instructions with German/English examples, and a JSON-encoded transcript
as data. With guided generation, normal guardrails still apply: the permissive
configuration is alignment with desktop, **not a promise of loosened filtering**.
Refusal and guardrail violations still fall back. There are no retries or second passes. UTF-8 input above 1500 bytes or
above 250 word tokens is skipped; generation is capped at
`min(1200, utf8Bytes / 2 + 128)` response tokens. Unconstrained language detection
requires at least three words and top confidence 0.80, then a supported model
locale. Unclear detection is skipped; mixed language may go undetected; very
short dictations are not cleaned.

Unavailable devices, disabled Apple Intelligence, a model not ready, unsupported
language, invalid background lease, model errors (including refusal, rate limits,
guardrail or context failures), rejected changes, deadline, expiry and busy model
all fall back to plain ASR text, formatted as before. Cleanup failures do not
set `.failed`; ASR failures retain their existing error behavior. Logs use
`ai-cleanup` and fixed reason strings, never transcript text or model error text.

## Explicit desktop alignment (D1–D9 and reviewed amendments)

The reference is desktop **Rewrite with OpenCode**, not an existing desktop Apple
Intelligence dictation feature (there is none). Source references:
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
  the sole explicit-self-correction exception. Preserve the existing DE/EN
  few-shots, Notes markers and line rules. Keep JSON-string-literal framing, not
  desktop transcript tags; do not adopt desktop's numbered-list conversion rule
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
  deadline, expired, empty-output, guard-rejected(notes-line-anchors/alignment).
  Skips off/verbatim/numbers-only/language/budget/busy/unavailable/
  no-background-lease are info, not failed-model events. Numbers-only uses the
  desktop message “skipped for a numbers-only transcript”. Cancellation logs
  cancelled, never a claim that plain text was pasted. There is no transcript,
  prompt, response or error-description payload in the observation interface.
- **D8:** Check raw Notes line anchors first, classify remaining whitespace-only
  model output as empty-output, apply the unchanged structural guard to raw
  output, then trim accepted text before the one formatter call. This prevents
  trimming from hiding changed Notes line anchors.
- **D9:** Default **on** is Hex+ policy (desktop rewrite defaults off). The key
  remains `hexplus.aiCleanup`. iOS deliberately keeps the four-second deadline
  rather than desktop's thirty seconds, because keyboard delivery/background
  execution cannot rely on a desktop-length budget. The structural guard, one
  model slot, background lease and generation/delivery fences remain iOS-specific
  conservative constraints; the desktop generally trusts its rewrite model.

## Guard and proof limits

Protected tokens are numbers (including signs, separators, time and percentages),
URLs, emails, @handles and #tags. Their comparison is case-sensitive. Other words
are case-folded. Notes markers and the explicit cues `nein`, `ich meine`,
`ich korrigiere`, `korrektur`, `no`, `i mean`, `scratch that`, `correction` are
longest-first, non-overlapping phrase tokens. Negation overlaps those classes.
Original string spans are retained. Punctuation is ignored.

LCS alignment keeps earliest matches and forms deletion/insertion hunks. A local
replacement permits at most two old and two new words, no protected, negation,
marker or cue tokens, and at most `max(1, inputWords / 10)` replacement hunks.
As an additional conservative restriction discovered by the simulator test, local
replacements also preserve German/English interrogatives (e.g. `was`, `what`,
`wer`, `who`, `wie`, `how`). Otherwise a single replacement can answer a question:
“Was ist die Hauptstadt von Frankreich” → “Paris ist die Hauptstadt von Frankreich”.
This tightens the plan's A rule rather than weakening its mandatory reject test.
Ambiguous words (e.g. English `was`) can therefore cause false rejections. This is
not a general detector of questions or answers; other local answer-like changes
can still pass.
Pure insertion is rejected. Pure deletions slide left over identical keys without
crossing neighbouring hunks or Notes line anchors; reconstruction must still match
the output. Deletions split after every cue into 2–8-token segments, each ending
in its cue, each with a retracted non-cue token. No leftover tail, adjacent cues,
Notes markers, or terminal deletion is permitted. There are at most four
retraction segments per dictation. Notes are diffed line-by-line with identical
line counts. Empty output is rejected. As in language admission, the pure guard
also rejects changed word keys for inputs shorter than three words (so “Hallo”
→ “Alles erledigt” cannot be accepted).

**Many changes beyond local word fixes and cued retractions are rejected
(reordering, swapped values, inserted content, tail truncation). Local replacements
(≤ 2 words) and cue-based deletions remain fallible: a cue not meant as a retraction
can remove content including numbers and negations; punctuation changes (e.g. a
lost question mark) are not checked; names are not protected beyond the 2-word
limit.** The guard is structural, not a semantic guarantee. Instructions and
JSON quoting are not a guarantee against prompt injection.

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

`AICleanupGuardCases`, `TranscriptCleanupTests`, `AICleanupControllerTests` and
`CleanupDesktopAnalogyTests`
exercise guard acceptance/rejection, sliding/splitting, protected tokens, Notes
anchors, isolated defaults, reservations, late cancellation-ignoring models,
deadline fallback, foreign operations, early/invalid background leases,
controller delivery, switch freezing, plain fallback, stale results, warm-session
closure and expiry during ASR. Desktop-alignment tests mirror numbers-only cases,
add DE and punctuation boundaries, typed errors with a secret description marker,
exactly-once outcome/latency races, admission skip classifications, raw Notes
anchors before empty detection/trim, prompt JSON/protocol and UI-cache TTL.
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
archive run `42467380855` (after retrying transient HTTP 504 downloads) and Hex+
review `42467379347`. These results do **not** prove the subsequent desktop-steering
changes; the PR records their separate CI/review/test outcomes.
Optional simulator run: Hex+ CI, distribution `simulator`,
`only_testing=HEXMobileTests/AICleanupGuardCases,HEXMobileTests/TranscriptCleanupTests,HEXMobileTests/AICleanupControllerTests,HEXMobileTests/CleanupDesktopAnalogyTests`.

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
