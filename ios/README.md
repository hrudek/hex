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
it never accesses the microphone, speech model, or network.

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
    `Casual` (lowercase chat without trailing period), `Notes` (spoken
    `"bullet"` / `"next line"` markers), and `Verbatim`, with cursor-aware
    insertion spacing and repeating backspace. Filler trim removes äh/ähm/öhm/hm
    always, but English um/uh/er/ah only from text that reads as English ("um 13 Uhr",
    "was er sagt" stay); a period after bzw., z. B., d. h., ca., usw. and similar
    abbreviations does not capitalize the next word.
  - **Speech engine:** Apple Speech, Parakeet V2 or Whisper Large V3 Turbo, with
    languages, live status and an explicit Whisper download; an explicit choice
    never falls back to another engine ([SPEECH_ENGINES.md](SPEECH_ENGINES.md)).
  - **Language (Automatic / Deutsch / English):** picks the Apple Speech locale
    (an explicit language never falls back to another) and Whisper's language,
    and tells Typr AI cleanup which language to write (English terms in German
    speech stay English). A warm-session start also sends up to 300 characters
    of the field's text before the cursor to the app as cleanup context (never
    logged); see [AI_CLEANUP.md](AI_CLEANUP.md#language-context-and-hyphens).
  - **Full keyboard Typr key (Settings › Keyboard › Full keyboard):** A quick tap
    types a space, exactly like the space bar (autocorrect, double-space
    period). A still hold of 0.35 s starts dictation in a warm session (or
    opens Typr without one), with a haptic. Moving more than 10 pt before
    then opens the style menu (up or sideways); releasing over a row picks
    it, and releasing elsewhere leaves the menu open for taps. A mostly downward
    slide always shows the compact
    dictation bar instead (`TyprKeyGesture`). VoiceOver activation
    dictates; the **Space**, **Dictation styles** and **Show dictation bar**
    actions do the rest.
  - **Autocorrect (below Full keyboard):** **Deutsch** and **English** are
    independently selectable when autocorrect is on; both default on. German
    includes ae/oe/ue/ss → ä/ö/ü/ß and typo fixes. English includes contractions
    and typo fixes. Turning autocorrect off keeps the language choices for later.
    iOS Text Replacement and contact suggestions remain language-independent.
    Retired German-autocorrect and keyboard-switch experiment values are ignored.
  - **AI cleanup (Settings › Writing, iOS 26+):** On by default. Typr's on-device
    Apple Intelligence rewrite runs before formatting in every style but `Verbatim`,
    with plain-transcript fallback. The inherited cleanup experiment has been removed;
    turning **AI cleanup** off runs no model-based cleanup. See [AI_CLEANUP.md](AI_CLEANUP.md).
  - **Custom vocabulary (Settings › Writing › Custom vocabulary):** Off by default.
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
- **Action Button, Control Center, Back Tap & Live Activity:**
  - `DictateWithTyprIntent` (`AudioRecordingIntent` + `LiveActivityIntent`) and
    `TyprDictationControl` (`ControlWidget`) start recording on first press with
    a Dynamic Island / Lock Screen Live Activity (`Stop` and `Cancel` buttons)
    and transcribe + copy to the clipboard on second press.

## Settings interface

The app is primarily the keyboard's settings companion. A dark, compact overview
keeps dictation language, style and microphone controls immediately accessible.
Purpose-based detail pages replace the old Typr/Experiments split:

- **Keyboard:** full keyboard, suggestion bar, conditional autocorrect/languages,
  and the link to iOS keyboard settings.
- **Writing:** on-device AI cleanup with availability/last outcome, and editable
  vocabulary/sounds-like forms. Technical explanations expand on demand.
- **Speech engine:** explicit selection, status, downloads, retry/cancel, language
  warnings and expandable engine details. No automatic engine switching changes.
- **History & feedback:** collection, archive/export/delete and keyboard ratings.
  Feedback URLs still open the requested archive entry from any settings page.

Settings keys, defaults, full-keyboard/autocorrect dependencies, archive retention
and privacy behavior are unchanged. `SettingsComponents.swift` provides shared
surfaces, scalable text and navigation routes; keyboard colors remain untouched.
`SettingsPresentationTests` checks route parsing and compact/large-text layout.
Manual simulator screenshots can request `settings-keyboard`, `settings-writing`,
`settings-history` and `settings-speech-engine`, plus `settings-overview`.
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
- **Apple Speech hint:** Custom vocabulary is covered by unit tests only.
  Its contextual strings are best effort and unverified on a physical iPhone.
  Apple documents contextual strings only for `DictationTranscriber`, Typr sets
  them on `SpeechTranscriber`, and
  Parakeet's batch path gets no hint. Whisper gets no vocabulary prompt; for it
  vocabulary is post-processing only (spelling passes and cleanup).
- **Typr CI:** PRs compile an unsigned device archive (app, keyboard and
  widgets); they do not build the test bundle or automatically run simulator
  tests. App changes on `main` run simulator tests after merge, beside
  TestFlight. Manual `distribution=simulator` runs are available before merge;
  see [TYPR.md](../TYPR.md). These checks do not prove physical-iPhone
  behavior; a test's presence is not evidence of a passing run.
