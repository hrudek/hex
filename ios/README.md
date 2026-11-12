# Typr for iPhone

Typr is a standalone iPhone dictation keyboard.

**Status:** Internal TestFlight app (`Typr`), custom keyboard extension
(`TyprKeyboard`), and Live Activity + Control Center widget extension
(`TyprWidgets`). The containing app records a generation-scoped temporary WAV,
transcribes on-device with Apple Speech (`SpeechTranscriber` on iOS 26+),
FluidAudio Parakeet V2 (iOS 18+) or Whisper Large V3 Turbo (WhisperKit, downloaded
only on request); see [SPEECH_ENGINES.md](SPEECH_ENGINES.md). It removes each capture's file after
inference, cancellation, or failure. The keyboard extension sends commands and
inserts completed text over the shared App Group (`group.dev.rudek.typr`);
it never accesses the microphone, speech model, or network. Manual typing can
persist bounded local personal word collections, aggregated per-key statistics
and text-free diagnostics with Full Access; current-word/pending-feedback and the
bounded two-word/real-Space boundary-window raw taps remain RAM-only. See [KEYBOARD_LEARNING.md](KEYBOARD_LEARNING.md) for the
owner-approved privacy, retention and reset contract.

## Capabilities

- **One-tap keyboard dictation (`TyprKeyboard`):**
  - **Setup:** The keyboard needs Full Access to reach Typr through the App
    Group. Without it, the keyboard shows the Settings path and an **Open Typr
    setup** button (`typr://keyboard/setup`). The app's setup card
    shows live status for the keyboard, Full Access, the microphone, and the
    speech model, and opens Typr's page in Settings. Full Access shows as on
    once the keyboard has run with it (`keyboard.fullAccessSeenAt`).
  - **Opening Typr:** SwiftUI `Link`, `openURL`, and `extensionContext.open`
    do nothing in a keyboard extension, so the keyboard opens Typr through
    the `UIApplication` at the end of its responder chain
    (`ContainingAppOpener`).
  - **Cold start and automatic return:** Without a warm mic, tapping
    **Dictate** opens the containing app (`typr://keyboard/record?...&host=<bundle ID>`)
    with a 10-second handoff window. Typr starts recording, then returns to
    the app the keyboard was typing in, with no setting to choose:
    1. **Host detection (keyboard, private API):** since iOS 26.4 a keyboard's
       own properties no longer name its host. `KeyboardArbiter.c` switches on
       UIKit's `_UIKeyboardArbiterClient` as the keyboard binary loads;
       `KeyboardHost` keeps the arbiter's process ID → bundle ID pairs in
       memory (`HostProcessTable`) and answers with the name under the
       keyboard's `_hostProcessIdentifier`, never the arbiter's latest answer,
       which can name an app already left. Unknown means no bundle ID.
    2. **Return (app):** `HostReturner` opens the bundle ID through
       `LSApplicationWorkspace` (private API; resumes the app as it was left),
       else the app's resuming URL from `HostReturnCatalog` (`ichat://` for
       Messages, `whatsapp-consumer://`, `slack://open`, …), else the
       bottom-edge swipe cue appears within ~1 s. An unknown host gets the
       swipe cue directly; a field in Typr itself is not returned from.
    3. **Hosts Typr cannot return to:** a share sheet, a notification's reply,
       Spotlight and similar surfaces close when left, taking their text. There
       the keyboard does not open Typr and says *Turn on Keep mic warm in Typr
       first*; with a warm mic, dictation works in place as anywhere.
    None of the private calls is linked; each is resolved by name and degrades
    to the next step. Translated from iikb and Dictus (see `PORTS.md`).
  - **GPU Dot Scope (`TyprShared/DotScope.swift`, `DotScopeShader.metal`):**
    Both `Typr` and `TyprKeyboard` render Hex's desktop menu-bar braided
    oscilloscope (in `anomalyco/hex` at `cae389a8`: `src/rune_hud/dot_scope.rs`,
    `src/rune_hud.wgsl`) at native display
    refresh via `CAMetalLayer` + `CADisplayLink`, pausing at 0% CPU/GPU once
    settled in idle. Lock Screen / Dynamic Island Live Activities render a
    matching `Canvas` dot-matrix badge (`TyprDotMatrixBadge`) because WidgetKit
    archives static view snapshots rather than hosting live `CAMetalLayer`s.
    Meter polling stays alive through a temporary non-recording state of the
    same capture; it resumes app levels and keyboard snapshots when the recorder
    is ready again. Capture completion, interruption, and Stop end polling.
  - **Warm session (`Off`, `5m`, `15m`, `1h`):** Picking a duration on **Keep
    mic warm** starts an `AVAudioEngine` input session immediately (default
    `15m`) so subsequent taps on **Dictate** record directly inside the
    keyboard with zero app switches; picking `Off` or tapping the header timer
    ends it. Captures record from that running input (a tap writing a 16 kHz
    WAV) instead of switching to a recorder, so the input never stops between
    dictations: iOS won't start microphone input while Typr is in the
    background, and restarting it there ended the session after each one.
  - **Styles:** `Polished` (sentence case + punctuation + filler trim),
    `Casual` (chat with natural capitalization, preserving recognized names and nouns),
    `Very casual` (the former Casual: lowercase chat), `Notes` (spoken
    `"bullet"` / `"new line"` / `"new paragraph"` markers), and `Verbatim`, with cursor-aware
    insertion spacing and repeating backspace. Both chat styles drop the final period
    even after multiple sentences, keeping internal punctuation and final `?` / `!`.
    They share the same informal AI cleanup; without AI, Casual preserves recognition
    casing and capitalizes sentence starts rather than running keyboard autocorrect.
    Existing saved Casual selections become Very casual. Historical log entries labelled
    `Casual` mean the old lowercase style and are not rewritten; new logs distinguish
    `Casual (natural case)` from `Very casual`. Filler trim removes äh/ähm/öhm/hm
    always, but English um/uh/er/ah only from text that reads as English ("um 13 Uhr",
    "was er sagt" stay); a period after bzw., z. B., d. h., ca., usw. and similar
    abbreviations does not capitalize the next word. In every style, Verbatim
    included and before AI cleanup, hyphens between words become spaces
    ("Pull-Request", "Feedback-Menü", "Know-how"); E-Mail, 5-10, links and
    hyphenated Custom vocabulary terms keep theirs. An accepted AI answer may
    write hyphens again ([AI_CLEANUP.md](AI_CLEANUP.md#language-context-and-hyphens)).
  - **Speech engine:** Apple Speech, Parakeet V2 or Whisper Large V3 Turbo, with
    languages, live status and an explicit Whisper download; an explicit choice
    never falls back to another engine ([SPEECH_ENGINES.md](SPEECH_ENGINES.md)).
  - **Language (Automatic / German / English):** picks the Apple Speech locale
    (an explicit language never falls back to another) and Whisper's language,
    and tells Typr AI cleanup which language to write (English terms in German
    speech stay English). A warm-session start also sends up to 300 characters
    of the field's text before the cursor to the app as cleanup context (never
    logged); see [AI_CLEANUP.md](AI_CLEANUP.md#language-context-and-hyphens).
  - **Full keyboard Typr key (Settings › Keyboard › Full keyboard):** Adjacent space
    and Typr keys share an outlined keycap with a sloping S-shaped decorative seam,
    matching the owner's 2026-11-11 reference: it leaves the top edge just inside
    the Typr key and meets the bottom edge inside the space bar. The Typr key
    shows a smaller wordmark slightly left of centre and a thin ↗ in the top-right
    corner when cold (white in dark, faded in light). Dark keycaps are opaque
    `#2D2D2D` with a `#767676` joined outline over the dark platter. Their
    touch targets and gesture thresholds are unchanged; URL/email fields keep
    separate keycaps because punctuation sits between them. A quick tap
    types a space, exactly like the space bar (autocorrect, double-space
    period). A still hold of 0.35 s starts dictation in a warm session (or
    opens Typr without one), with a haptic. Moving at least 60 pt before
    then opens the style menu (up, sideways or diagonally); releasing over a row
    picks it, and releasing elsewhere leaves the menu open for taps. A mostly
    downward slide shows the compact dictation bar instead at 30 pt
    (`TyprKeyGesture`). Distances are measured from touch-down; smaller movements
    do not open either surface. Tap and hold behavior is unchanged. VoiceOver activation
    dictates; the **Space**, **Dictation styles** and **Show dictation bar**
    actions do the rest.
  - **Autocorrect (below Full keyboard):** **Deutsch** and **English** are
    independently selectable when autocorrect is on; both default on. German
    includes ae/oe/ue/ss → ä/ö/ü/ß and typo fixes. English includes contractions
    and typo fixes. Turning autocorrect off keeps the language choices for later.
    iOS Text Replacement and contact suggestions remain language-independent.
    Retired German-autocorrect and keyboard-switch experiment values are ignored.
  - **[Keyboard correction path](KEYBOARD_SPATIAL_DECODER.md):** the full keyboard uses
    [current-word touch evidence](KEYBOARD_TOUCH_INPUT.md) and bundled, separately licensed
    German/English frequency data for bounded spatial substitution and at most one
    missing/extra/swapped-letter edit. Existing rules and protections retain precedence;
    automatic replacement requires complete search, margins and system validation.
    Below-literal edit candidates are manual suggestions only. Missing evidence/resources
    permit cautious spelling fallback; incomplete search never authorizes inferred replacement.
    Suggestions use a serial spatial/personal-scan worker with revision-checked main-actor
    checker completion, rather than ranking during ordinary insertion. Stale chips cannot edit
    a newer field/token. Space/punctuation keep authoritative bounded synchronous fallback
    and never await the worker; see the correction-path reference for bounds/proof limits.
    Dictation, visible keys and gestures are unchanged. Trained models can conservatively
    attribute horizontal letter-gap taps using a known prefix of at least four letters;
    stricter novel-word/density gates limit harm, and backspace keeps retyping geometric
    for the rest of that word. Drawn-keycap and function-key taps stay literal. See [the attribution bounds and risks](KEYBOARD_TOUCH_INPUT.md#bounded-adaptive-letter-attribution).
  - **[Personal typing learning and diagnostics](KEYBOARD_LEARNING.md):** default-on
    **Learn from my typing** uses trusted unchanged literals and explicit feedback, never
    automatic output alone. Full Access allows bounded protected local snapshots of per-key
    statistics, kept words, counts, rejected pairs and text-free counters/histograms; otherwise
    session RAM only. No raw tap archive, ordered typed-text/context history, backup or network.
    Off stops new touch/count learning and personal scoring, retains saved data and explicit
    keep/rejection protection; statistics are independent. **Typing diagnostics** shows saved
    summaries and separate learning/statistics resets, not accuracy. Synthetic Linux decoder
    evaluation is not real typing; iPhone quality, evidence coverage, latency and memory remain
    unverified.
  - **AI cleanup (Settings › AI & vocabulary, iOS 26+):** On by default. Typr's on-device
    Apple Intelligence rewrite runs before formatting in every style but `Verbatim`,
    with plain-transcript fallback. The inherited cleanup experiment has been removed;
    turning **AI cleanup** off runs no model-based cleanup. See [AI_CLEANUP.md](AI_CLEANUP.md).
  - **Custom vocabulary (Settings › AI & vocabulary › Custom vocabulary):** Off by default.
    A local list of up to 100 names and phrases, applied to every engine. After
    transcription, matching words are rewritten to the listed spelling across
    case, spaces, tabs, a single hyphen, and possessive apostrophes, before
    cleanup and again after formatting, so a style cannot undo a spelling. The
    listed spelling is kept exactly, even at a sentence start (an all-lowercase
    term stays lowercase), and a term that spells its own boundaries ("iPhone 7",
    "X-ray") matches those boundaries exactly. A word that carries its own
    apostrophe only matches a term that has one, several transcript words are
    joined only when the term reads as a compound, and compound terms like
    "WeChat" can also match the plain phrase ("we chat"). On iOS 26 Apple Speech
    the list is also sent as a best-effort recognition hint; Parakeet's batch
    path gets no hint. Each term can carry **sounds-like** forms (what the
    speech engine writes instead, e.g. Herder for herdr), replaced by the term.
  - **Built-in tech glossary (always on):** known mishearings of developer terms
    ("Pulrequest" → "Pull Request", "Gitub" → "GitHub", "Pay Agenten" → "pi Agenten")
    are fixed before cleanup; real words only when the dictation's context fits
    ("gemerkt" → "gemergt" next to PR/Branch/merge). Its terms are Apple Speech hints
    after the user's terms. See [AI_CLEANUP.md](AI_CLEANUP.md).
- **Resilient capture & expiry contract (`DictationController`):**
  - Monotonic `jobGeneration`, retained `transcriptionTask`, and unique
    per-capture WAV filenames ensure an expiring warm session never drops an
    already-accepted transcription (deliverable for 30s), while a stale
    winding-down inference can never overwrite a newer capture or delete its
    audio file.
  - Phone/FaceTime/Siri audio interruptions finalize captures `>= 300 ms` so
    spoken words are not lost, cancel shorter taps cleanly out of `Listening`,
    and resume warm keepalive when iOS signals `.shouldResume`. Bluetooth HFP
    input is opt-in (**Use Bluetooth headphones**, default off) so AirPods stay
    in full-fidelity output by default.
  - **Audio-route startup safety:** `TyprAudioInput` owns the input graph in
    Objective-C. A start creates a fresh engine after session activation and uses
    the native tap format (`nil`), avoiding a pinned format from an old route.
    AVFAudio exceptions during graph setup become recoverable errors; failed
    graphs are discarded, including when cleanup raises. Swift `do/catch` alone
    cannot catch these exceptions. A running warm input is still reused.
- **Action Button, Control Center, Back Tap & Live Activity:**
  - `DictateWithTyprIntent` (`AudioRecordingIntent` + `LiveActivityIntent`) and
    `TyprDictationControl` (`ControlWidget`) start recording on first press with
    a Dynamic Island / Lock Screen Live Activity (`Stop` and `Cancel` buttons)
    and transcribe + copy to the clipboard on second press.

## Settings interface

The app is primarily the keyboard's settings companion. A dark, compact overview
puts **Dictation** before **Preferences**. Dictation contains microphone controls
and compact links for **Speech engine**, **Language** and **Style**, each showing
the current selection. Language sits beside its engine because compatibility depends
on that choice. Preferences contains Keyboard, AI & vocabulary and History & feedback.
The overview has no redundant navigation title. Detail pages use compact inline
titles, consistent disclosure chevrons and semantic, aligned status/retention footers.
Purpose-based detail pages replace the old Typr/Experiments split:

- **Keyboard:** full keyboard, suggestion bar, conditional autocorrect/languages,
  Learn from my typing, Typing diagnostics, Manage learned words and the link to iOS keyboard settings.
- **AI & vocabulary:** on-device AI cleanup with availability, an editable cleanup
  prompt (Default/Custom, explicit Save and conditional Reset to default), and editable
  vocabulary/sounds-like forms. No last-result summary or What changes disclosure.
  Prompt overrides stay in app-local preferences; language/style/vocabulary/context,
  safety checks and formatting still apply. See [AI_CLEANUP.md](AI_CLEANUP.md).
- **Speech engine:** explicit selection, status, downloads, retry/cancel, language
  warnings and expandable engine details. No automatic engine switching changes.
- **Style:** Polished, Casual, Very casual, Notes and Verbatim, each with a short explanation
  and a checkmark for the current choice. The page explains that AI cleanup skips
  Verbatim but vocabulary corrections still apply.
- **Language:** single-line, label-only Automatic, German and English choices,
  a checkmark for the current selection and the same Parakeet compatibility warning
  as the overview.
  Both choice pages apply selections through the existing controller setters and
  stay open so users can compare options; returning shows the updated overview value.
- **History & feedback:** collection, archive/export/delete and keyboard ratings.
  Feedback URLs still open the requested archive entry from any settings page.

Existing dictation settings, archive retention and privacy rules are unchanged.
Manual keyboard learning adds `keyboard.personalLearning` (default on) and the
bounded local storage contract above. **Keyboard → Full keyboard** reveals
**Typing assistance → Autocorrect**; enabling Autocorrect reveals the independent
Autocorrect languages link directly below it. Its summary shows ISO 639-1 codes
(DE, EN, or both in code order; None when neither is selected). The destination uses
independent Deutsch/English checkmark rows, matching the dictation language page. Learn from my typing, Typing diagnostics
and the direct Manage learned words link below diagnostics remain reachable with Autocorrect off. When Full keyboard is off, a footer explains this path.
`SettingsComponents.swift` provides shared
surfaces, scalable text and navigation routes; keyboard colors remain untouched.
Menu entry points use 50 pt single-line rows with standalone symbols, trailing
values where useful, and aligned separators. Descriptions live on the detail
pages (and remain available as accessibility hints), not under every menu title.
At accessibility text sizes, rows may grow and wrap instead of clipping. Warm
microphone durations stay inline when space allows, with a stacked fallback for
narrow widths/large text and repeat-tappable controls in every layout. At standard
text sizes, their backgrounds are vertically inset for breathing room without
shrinking the 44 pt button hit targets; accessibility sizes retain full-height paint. Engine
names are primary card headings; important status and language warnings remain visible.
`SettingsPresentationTests` checks route parsing and compact/large-text layout.
Manual simulator screenshots can request `settings-keyboard`, `settings-writing`,
`settings-history`, `settings-speech-engine`, `settings-style` and `settings-language`,
plus `settings-overview`.
The existing `settings-writing` scene name now opens **AI & vocabulary**.
`settings-keyboard-typing` explicitly enables Full keyboard and Autocorrect in the
snapshot fixture, with Deutsch and English enabled, to capture the correction-language
summary on the Keyboard page; `settings-autocorrect-languages` opens the multi-select
language page directly; ordinary launches never set these preferences.
`settings-keyboard-diagnostics` renders a deterministic in-memory synthetic dashboard,
without reading/writing/resetting personal snapshots or seeding preferences.
**Keyboard → Manage learned words** (also linked from Typing diagnostics) explicitly opens
the private saved keeps, rejected pairs and counts for individual swipe/Edit deletion.
An always-visible search field filters all three lists, including both sides of rejected
corrections, with case/diacritic-insensitive partial matching. Reset learning and Reset
statistics in diagnostics use red labels and keep their confirmation dialogs. The dashboard
itself still shows totals only. A deletion advances the learning epoch so dirty
keyboard RAM cannot restore it. The optional `settings-keyboard-learned-words`
scene shows synthetic fixture data only. Immediate Backspace after a new keep,
or immediately picking the replacement after undo, reverts that new protection;
see [KEYBOARD_LEARNING.md](KEYBOARD_LEARNING.md#manage-learned-words).
The existing Keyboard setup checklist retains its selective visibility: it appears
for incomplete keyboard/Full Access, microphone or model setup, or an explicit
setup request. Once complete it is absent on ordinary launches. Each explicit
setup URL returns from any pushed page to the checklist (also for repeated requests);
permission actions, live progress and refresh behavior are unchanged. The `setup`
scene captures the incomplete-setup checklist, while `settings-overview` captures
the completed state without it.
Parakeet's non-English warning also remains beside the overview's language controls,
even though the full engine list now lives on its own page.
These are opt-in launch fixtures, not app/runtime data collection. A simulator
render does not prove interaction or layout on a physical iPhone.

## Build & Test

Prerequisites: Xcode 26+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) 2.46.0+.

```sh
cd ios
xcodegen generate
xcodebuild test -project Typr.xcodeproj -scheme Typr -destination "id=<SIM_UDID>"
```

## Simulator vs. Physical iPhone Proof Limits

- **Verified in Simulator (`TyprTests` + `--snap-state` scenes):** Compilation
  across `Typr`, `TyprKeyboard`, and `TyprWidgets`; App Group command/snapshot
  framing; the `DictationController` generation/expiry race and 30s post-close
  transcript delivery; 10s handoff window + URL-scheme auto-return fallback;
  interruption handling; meter recovery after injected startup and mid-capture
  recorder unavailability (including keyboard levels and heartbeat); deterministic
  style formatting; host-return order (bundle ID → resuming URL → swipe),
  host process table and share-sheet refusal logic with injected openers;
  and UI layouts.
- **Audio-input regression coverage (requires a simulator test run):**
  `AudioInputTests` injects Objective-C graph failures (tap installation,
  preparation, startup and cleanup), verifies error conversion, native-format
  taps, graph disposal and a successful retry. This does not reproduce CarPlay.
- **Requires a physical iPhone:** Real `AVAudioSession` background keepalive
  survival across lock/app switches, live orange indicator behavior, on-device
  `SpeechTranscriber` / Neural Engine Parakeet latency, the Whisper download,
  Core ML optimization, accuracy, memory and thermal behavior
  ([checklist](SPEECH_ENGINES.md#iphone-16-a18-checklist)), keyboard-arbiter host
  detection, `LSApplicationWorkspace` and URL-scheme return into installed
  apps (and where each lands), share-sheet refusal, Dynamic Island
  Live Activity interaction, and hardware Action Button invocation. Transient
  `AVAudioRecorder.isRecording` changes during warm handoff or Bluetooth route
  changes have not been reproduced on hardware; the meter recovery tests inject
  that condition through `ActiveAudioCapture`.
- **Manual keyboard correction/learning:** Implemented tests and Linux synthetic
  decoder runs are described in [KEYBOARD_SPATIAL_DECODER.md](KEYBOARD_SPATIAL_DECODER.md).
  They are not an observed iOS build/test pass or real typing evaluation. Owner
  iPhone checks still include host-callback evidence coverage, quality/latency/memory,
  Full Access, protected storage, resets and cross-process refresh; see its checklist.
- **Apple Speech hint:** Custom vocabulary is covered by unit tests only.
  Its contextual strings are best effort and unverified on a physical iPhone.
  Apple documents contextual strings only for `DictationTranscriber`, Typr sets
  them on `SpeechTranscriber`, and
  Parakeet's batch path gets no hint. Whisper gets no vocabulary prompt; for it
  vocabulary is post-processing only (spelling passes and cleanup).
- **Typr CI:** PRs run Linux checks and a required current-commit AI review,
  with no automatic macOS builds or tests. App changes on `main` build the
  TestFlight archive and run simulator tests in parallel; tests do not gate
  upload. New automatic app runs cancel older archive/test jobs, not active
  signing/uploads. Pipeline-only and documentation changes allocate no macOS
  jobs. Manual `distribution=simulator` runs are available before merge;
  see [TYPR.md](../TYPR.md). These checks do not prove physical-iPhone
  behavior; a test's presence is not evidence of a passing run.

### CarPlay microphone-start regression check

The 2026-11-10 crash in TestFlight build 88.1 was an uncaught AVFAudio
exception in `installTapOnBus` at approximately 16:54 local time. The private
report identifies the failing operation, but not the assertion text or active
route; a CarPlay route/format transition is suspected, not proven. No raw device
reports or identifiers are committed.

On a real iPhone, connect CarPlay and start dictation both cold and with **Keep
mic warm** enabled; repeat while connecting/disconnecting CarPlay and with **Use
Bluetooth headphones** both off and on. Verify that speech is captured on a
stable route, an unavailable route gives a recoverable failure rather than an
app exit, the next attempt can succeed, and repeated warm dictations do not
restart microphone input. Also check built-in mic and Bluetooth headphones
without CarPlay. These hardware checks have not yet been performed for this fix.
