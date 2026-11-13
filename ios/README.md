# Typr for iPhone

XcodeGen project (`project.yml`) with these targets:

- `Typr`: containing app that records, transcribes and serves as settings.
- `TyprKeyboard`: keyboard extension.
- `TyprWidgets`: Live Activity and Control Center.
- `TyprShared` / `TyprActivity`: shared code.
- `TyprTests`: tests.
- Plus app icon and test fixtures.

## How dictation works

- **Keyboard ↔ app:** the keyboard sends commands and inserts finished text over the
  App Group `group.dev.rudek.typr`. It needs Full Access. Without it, it shows the
  Settings path and **Open Typr setup** (`typr://keyboard/setup`).
- **Cold start:** without a warm mic, **Dictate** opens
  `typr://keyboard/record?...&host=<bundle ID>`. Typr records and returns to the host.
  - The host comes from UIKit's keyboard arbiter (`KeyboardArbiter.c`, `KeyboardHost`).
  - It returns via `LSApplicationWorkspace`, then the resuming URL
    (`HostReturnCatalog`), then a swipe cue.
  - Both are private APIs, resolved by name and degrading safely; translated from
    iikb and Dictus.
  - Share sheets, notification replies and Spotlight close when left. There the
    keyboard asks for **Keep mic warm** instead.
- **Warm session** (`Off`, `5m`, `15m`, `1h`):
  - Keeps an `AVAudioEngine` input running, so dictation starts inside the keyboard.
  - `TyprAudioInput` (Objective-C) builds a fresh graph per start and turns AVFAudio
    exceptions into recoverable errors.
  - Brief audio refusals after other apps' audio are retried for about 5.5 s.
- **Capture contract** (`DictationController`): a generation counter and unique WAV
  names ensure a stale inference never overwrites a newer capture or deletes its file.
  - Accepted transcripts stay deliverable for 30 s.
  - Interruptions finalize captures ≥ 300 ms.
  - Bluetooth HFP input is opt-in.
- **Speech engines:** Apple Speech (`SpeechTranscriber`, iOS 26+), Parakeet V2
  (FluidAudio, iOS 18+), Whisper Large V3 Turbo (WhisperKit, explicit download only).
  An explicit engine or language choice never falls back to another.
- **Text pipeline:**
  1. Hyphens between words become spaces (except E-Mail, ranges, links,
     hyphenated vocabulary).
  2. Built-in tech glossary and Custom vocabulary (up to 100 terms with
     sounds-like forms) fix spellings.
  3. On-device Apple Intelligence **AI cleanup** runs (iOS 26+, all styles except
     Verbatim, editable prompt, output check, plain-transcript fallback).
  4. The style formats the text (Polished, Casual, Very casual, Notes, Verbatim).
  5. Vocabulary is applied again.
- **Entry points:** keyboard Typr key (tap = space, hold = dictate, slide = styles
  menu, slide down = dictation bar), Action Button/Control Center intent with Live
  Activity, Back Tap. The scope animation is a Metal port of Hex's dot scope.
- **Full keyboard:** autocorrect (German/English) and a bounded spatial decoder from
  current-word touch evidence plus bundled frequency data (`WordData/`).
  - It allows at most one missing/extra/swapped letter.
  - Automatic replacement requires complete search, margins and system validation.
  - Suggestions come from a serial worker; Space/punctuation never wait for it.
  - Personal learning adapts per-key aim, kept words and rejected pairs.

## Switches

| Switch | Settings page | Default | Key |
| --- | --- | --- | --- |
| Learn from my typing | Keyboard | on | `keyboard.personalLearning` |
| Hide suggestion bar | Keyboard | on | `typr.hideSuggestionBar` |
| AI cleanup | AI & vocabulary | on | `typr.aiCleanup` |
| Dictation log (also gates keyboard quick feedback) | History & feedback | on | `typr.dictationLog` |

## Privacy and storage

These rules are normative; changes need the owner's approval.

- The keyboard never accesses the microphone, speech model or network.
- **Audio:** each capture is a temporary WAV, deleted after inference,
  cancellation or failure. No audio is stored anywhere else.
- **Cleanup context:** the preceding field text (≤ 300 characters) and recent
  dictations stay in RAM only. The log stores context metadata and counts, never
  context text. Ordinary cleanup diagnostics contain no transcript or model-error text.
- **Dictation log** (owner-approved retention exception):
  - Durable, on-device, with no automatic eviction.
  - Off stops new collection and keeps history.
  - Only explicit Delete/Clear removes entries.
  - No audio, prompts, device names or uploads.
  - Clear also removes legacy data and owned temporary exports. Already shared
    copies cannot be retracted.
- **Keyboard learning:**
  - Only trusted unchanged literals and explicit feedback train; automatic output
    alone never does.
  - With Full Access, bounded aggregated snapshots are kept (per-key statistics,
    kept words, counts, rejected pairs, text-free counters). Otherwise data stays in
    session RAM.
  - Raw taps and the current word are RAM-only. There is no ordered typed-text or
    host history.
  - Off stops new learning and personal scoring but keeps saved data and keep/reject
    protection.
  - Personal-name sources (contacts, vocabulary) are explicit opt-ins. The keyboard
    reads imports only with Full Access. Deleting a source or resetting removes its
    derived data and disables imports.
- **Storage:** log and learning data are file-protected
  (`completeUntilFirstUserAuthentication`) and excluded from backup.
- **Deletion:** Delete/Clear/reset fence callbacks and writes, so stale work cannot
  resurrect data. A failed deletion is never reported as success.
- Transcripts, log exports and private tool stores never go into Git or public issues.

## Build and test

Xcode 26+ and XcodeGen 2.46.0+:

```sh
cd ios
xcodegen generate
xcodebuild test -project Typr.xcodeproj -scheme Typr -destination "id=<SIM_UDID>"
```

Screenshots come from `--snap-state` scenes (`KeyboardPreviewHost.swift`,
`FullKeyboardSnapshotStage.swift`). They are launch fixtures only and never touch
real user data.

## Proof limits

- **Simulator tests cover:** compilation of all targets, App Group framing, capture
  generation/expiry, handoff and return order with injected openers, interruption and
  meter recovery, audio-graph failure injection, formatting, vocabulary, decoder
  logic and layouts.
- **Only a real iPhone proves:**
  - Background keepalive and the orange indicator.
  - Speech latency, accuracy, memory and heat; the Whisper download.
  - Host detection and return into real apps; share-sheet refusal.
  - Live Activity and Action Button.
  - CarPlay/Bluetooth route changes.
  - Typing quality and latency, Full Access storage, resets and cross-process refresh.
  - The Apple Speech vocabulary hint.
