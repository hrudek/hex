# Speech engines

Typr transcribes every dictation on this iPhone with one of three engines. The
app's **Speech engine** section lists all three with their languages and live
status, and lets the user choose one. Audio never leaves the iPhone; no engine
sends telemetry.

| Engine | Implementation | Languages in Typr | Install | OS |
| --- | --- | --- | --- | --- |
| Apple Speech | `SpeechTranscriber` (`Typr/AppleSpeechTranscriber.swift`) | German and English, as installed by iOS | iOS manages the assets; it may download them when first used | iOS 26+ |
| Parakeet V2 | FluidAudio 0.15.5, NVIDIA Parakeet TDT 0.6B v2 (`Typr/ParakeetTranscriber.swift`) | English only | FluidAudio downloads it from Hugging Face on first preparation | iOS 18+ |
| Whisper Large V3 Turbo | WhisperKit (argmax-oss-swift 1.1.1), Core ML (`Typr/WhisperTranscriber.swift`) | German, English, or automatic detection | Only through its **Download** button (about 629 MB in total) | iOS 18+ (Typr's deployment target) |

## Choosing an engine

- The choice is stored in the App Group as `typr.preferredSpeechEngine`
  (`TyprSettings.preferredSpeechEngine`, raw values `apple-speech`,
  `parakeet-v2`, `whisper-large-v3-turbo`, never renamed). No stored value means
  the user never chose: Typr keeps its original automatic behavior (Apple Speech
  when it is available for any candidate locale, else Parakeet V2) and the value
  stays empty until an explicit choice. There is no way back to "no choice" in
  the UI; choosing an engine is the only change.
- An explicit choice is never replaced by another engine. If it cannot work
  (older iOS, unsupported device or language, Whisper not downloaded) Typr
  shows the reason and stays on that choice.
- The section distinguishes the **chosen** engine from the engine **in use**
  (the one whose model is ready). They differ while switching, after a failed
  preparation, and when nothing was chosen ("In use · automatic").
- Choosing and direct preparation are refused while a dictation is being set
  up, recorded, transcribed or cleaned up (`DictationController.canChangeEngine`).
  Cancellation is cooperative: a drain fence keeps switching disabled until
  every cancelled/superseded inference really exits and releases its capture.
  A newer capture can still use the same engine (the existing generation-scoped
  capture behavior); it cannot allocate a different model. Every
  capture freezes its engine and language at start, so a change applies to the
  next dictation only.
- Switching first releases the previous engine (its transcriber is replaced
  before the next one is created); a superseded preparation finishes and is
  dropped before the next starts, and stale results are rejected by a
  generation counter. Typr never holds two Whisper models.
- The keyboard's `model.installed` flag follows the selected engine: ready
  after a successful preparation, otherwise whether that engine is installed
  (Parakeet's cache, Whisper's verified files; Apple Speech reports false until
  prepared). No choice keeps the original Parakeet cache check.
- At launch an explicit engine is prepared only without a download: Apple
  Speech (iOS manages its assets), Parakeet when cached, Whisper when verified.

## Languages

The **Language** picker (Automatic / German / English) applies to every engine:

- **Apple Speech:** Automatic tries the preferred languages, the current
  locale, then en-US. An explicit language prepares only that language
  (`de-DE`, or a preferred/current locale of the same language such as
  `de-CH`), never another one; if this iPhone lacks it, preparation fails
  with that reason. When no engine was chosen, the decision between Apple Speech
  and Parakeet still uses the original, broader candidate order
  (`DictationLanguage.availabilityLocaleCandidates`), but the locale prepared
  is the strict one. Changes during capture or preparation are deferred until
  idle; another capture cannot start with the previous locale.
- **Parakeet V2:** English only. With German or Automatic the section warns
  that German speech is not recognized correctly; Typr does not block German or
  change the engine.
- **Whisper:** German → `de`, English → `en`, Automatic → Whisper detects the
  language (`detectLanguage: true`; WhisperKit's default would force English).
  The language is passed with each captured dictation; it never translates.

## Whisper Large V3 Turbo

Everything that pins it lives in `Typr/WhisperModelSpec.swift`:

- Package: `https://github.com/argmaxinc/argmax-oss-swift.git`,
  `exactVersion: 1.1.1` (tag commit `1bbc57cb7fe6410248a685b1c5a3c6d56adc2ed4`),
  product `WhisperKit` linked to the **Typr app target only** (not the keyboard
  or widgets). Its Swift 6.2 manifest's only package dependency,
  swift-argument-parser, is used by its CLI products, not by WhisperKit. No
  `Package.resolved` is committed (the Xcode project is generated in CI), so
  the exact tag pin in `ios/project.yml` is the reproducible pin.
- Model: `argmaxinc/whisperkit-coreml` at revision
  `0f63a7800b00dd0226abd051b906c246e1907482`, folder
  `openai_whisper-large-v3-v20240930_626MB` (OpenAI's 2024-09-30 Large V3 Turbo,
  Argmax's 626 MB Core ML build): 17 files, 626,718,238 bytes, every size pinned.
- Tokenizer: `openai/whisper-large-v3` at revision
  `06f233fe06e710322aca913c1bc4249a0d71fce1`: `config.json` (1,272 bytes),
  `tokenizer.json` (2,480,617), `tokenizer_config.json` (282,843).
- Licenses: argmax-oss-swift MIT with Apache-2.0 swift-transformers portions;
  model MIT; tokenizer files Apache-2.0. See
  [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md) and [PORTS.md](../PORTS.md).
- Compute units: mel spectrogram `.cpuOnly`, audio encoder and text decoder
  `.cpuAndNeuralEngine`. No GPU: iOS denies GPU work in the background, where
  keyboard dictations finish. (WhisperKit forces `.cpuOnly` in the Simulator.)

### Download (explicit only)

`Typr/WhisperModelInstaller.swift` is the only code that downloads Whisper, and
only from the **Download** / **Retry** buttons. Launch, preparation, engine
selection, keyboard handoff, intents and the primary button never download it.

- Storage: `Application Support/Typr/Whisper` in the app's own container (not
  Documents, not the App Group), excluded from backup, in the Hugging Face
  cache layout (`models/<repo>/…`).
- Before downloading, free space must cover the missing files plus 500 MB
  (Core ML's specialization cache and system headroom).
- Each pinned file is fetched with WhisperKit's `HubApiWrapper.snapshot` at its
  exact revision, one file at a time; files already present at their exact size
  are skipped. Progress is byte-weighted over all files and never moves
  backwards. The current engine keeps working during the download.
- Then every size is checked and the tokenizer is parsed locally. Only then is
  the marker `typr-whisper-installed.json` written. **Installed** = marker for
  this exact spec + every file at its exact size; a partial or invalid folder is
  never selectable.
- A wrong-sized destination is removed before fetching it again (the Hub cache
  otherwise trusts matching commit/ETag metadata). An explicit Retry checks a
  complete local tokenizer first and replaces just its three files if parsing
  fails, keeping the large model. A tokenizer failure during local preparation
  invalidates the install marker, so the section offers Retry; it never downloads
  from preparation. The marker proves a successful parse at installation, not a
  fresh parse on every settings render: same-size damage after installation is
  detected at the next local preparation.
- One download at a time: a second tap joins the running one. **Cancel** stops
  it; **Retry** starts the download again after the cancelled one stops. Files
  already downloaded are kept, but Typr makes no promise to resume a partial
  file. Offline errors show "No internet connection".
- There is no Delete in this version. Removing Typr removes the model.

### Preparation (local only)

After the user chooses Whisper while idle, Typr releases the previous engine
and loads Whisper. The first load in an environment lets Core ML specialize
("optimize") the model for this iPhone, which takes a few minutes; later loads
reuse the system's cache. The path cannot reach the network:

1. Exact files and marker, else "not downloaded" (no download).
2. Storage guard, before any model work (`WhisperPreparationPlan`): Core ML
   offers no API to ask whether its specialization cache will be hit, so Typr
   keeps `typr-whisper-preparation.json` next to the marker: the environment
   (OS version and build, Typr version and build, model revision) of the last
   complete load, and whether a preparation was still running when Typr last
   stopped. Same environment and no interrupted preparation → **Loading
   Whisper**. Otherwise specialization is expected → **Optimizing Whisper for
   this iPhone**, but only with at least 4.5 GB free
   (`WhisperModelSpec.optimizationStorageBytes`,
   `volumeAvailableCapacityForImportantUsage`); with less, preparation stops
   before any model work: "Whisper must be optimized for this iPhone first,
   which needs about 4.5 GB of free storage (… is free). Free up storage, then
   prepare Whisper again." (logged as `modelNotReady`). Unknown free space
   does not block. The record is not part of the install and never changes
   "installed".
3. `AutoTokenizerWrapper.from(modelFolder:)` parses the three tokenizer files
   locally; `TyprWhisperTokenizer` resolves every special token by exact
   round trip (a damaged tokenizer is a local error instead of upstream's
   pre-V3 default IDs).
4. `WhisperKit(WhisperKitConfig(modelFolder:, tokenizerFolder:, computeOptions:,
   prewarm: false, load: false, download: false))`, then `kit.tokenizer = …`
   **before** loading, so WhisperKit's tokenizer loader (and its Hub fallback)
   never runs. Typr uses the public `WhisperMLModel.loadModel(prewarmMode: true)`
   API to specialize the three pinned `.mlmodelc` components one at a time
   (audio features, text decoder, audio encoder), releasing each before the next.
   This preserves the sequential prewarm semantics of WhisperKit 1.1.1 without
   its opaque whole-model `prewarmModels()` call. `loadModels()` then loads them
   from the cache: peak
   memory during specialization stays at one model instead of all weights plus
   the compiler's working memory (WhisperKit's documented trade-off: a cached
   load takes about twice as long, under a second).
5. The decoder's vocabulary must be 51,866 (V3), else a local error; then
   `isModelMultilingual = true` (skipped with that loader).

Core ML does not expose measured progress within a component's specialization.
Whisper preparation therefore has no percentage or fixed 15% bar: the engine
page, main recording stage and keyboard handoff show an animated indeterminate
indicator and the current real phase. The component phases say *Step 1 of 3*,
*Step 2 of 3* and *Step 3 of 3*; these are component counts, not equally weighted
time estimates. Tokenizer reading, loading the prepared models and validation
have their own phase text. The setup checklist says *Preparing* instead of an
invented percentage. No elapsed time, countdown or simulated progress is shown.
Measured download and other engines' progress bars are unchanged. Tests cover
step order, awaiting completion, failure/cancellation and indeterminate row
state; a simulator run and real-iPhone layout/animation checks remain required.

The `WhisperKit` instance stays inside the `WhisperTranscriber` actor and is
released by ARC, never by `unloadModels()` while a transcription may use it.

Why the guard exists (observed on an iPhone 16, iOS 27.0.1, November 2026):
with about 300 MB free, iOS repeatedly purged the specialization cache from
Typr's `Library/Caches` (CacheDelete), specialization could not finish, and
iOS terminated Typr (one Jetsam report at the 3.4 GB per-process limit). With
7.6 GB free, the first load specialized in about 85 seconds, free space fell
by about 3.9 GB at its lowest and about 1.4 GB stayed; a relaunch reused the
cache without specializing again. Specialization is repeated after OS and
Typr updates and whenever iOS purges the cache under storage pressure.

### Transcription

- The capture is read with `AudioProcessor.loadAudioAsFloatArray` (16 kHz mono).
- Amplitude gate first (`EnergyVAD`, explicitly 0.005 RMS / about -46 dBFS):
  no frame above the floor → "The recording is too quiet for Whisper" (logged
  as `noSpeech`). This is not a speech classifier. The upstream default of
  0.02 RMS / about -34 dBFS rejected valid quiet speech before the model ran;
  model re-optimization cannot change this gate. The floor still rejects
  digital silence and faint hum. WhisperKit 1.1.1's no-speech probability is
  not implemented, and removing the gate entirely risks invented text for silence.
  The lower floor can admit more background noise; it needs device validation.
- `DecodingOptions`: task `transcribe`, language `de`/`en`/nil with
  `detectLanguage` only for Automatic, prefill prompt, special tokens skipped,
  no timestamps, VAD chunking for captures longer than 30 seconds, no prompt
  tokens. Built from `WhisperDecodingPlan` so tests check it without WhisperKit.
- Chunk texts are joined and trimmed; an empty result now says "Whisper
  returned no text" (logged as `other`), not that the recording contained no
  speech. This distinguishes a decoder failure/empty result from rejection
  before inference. Neither error unloads the engine or prevents another capture.
- **Vocabulary:** Whisper gets no vocabulary prompt. Custom vocabulary and the
  tech glossary apply afterwards, exactly as for the other engines (spelling
  passes, AI cleanup, formatting); the section says so.

### Dictation log

Each entry records the engine of its capture (`speechEngine`) and, for Whisper,
the language it was asked for (`speechLanguage`: German, English, or
"Automatic (detected by Whisper)"; the detected language is not recorded).
Failures map to the existing reasons: not downloaded / not ready →
`modelNotReady`, below-floor recording → `noSpeech`, empty decoder result or
damaged model → `other`. Older entries retain their original classification.

## Quiet-recording investigation

The previous generic "Whisper did not detect any speech" message came from two
independent paths: the amplitude gate before inference and an empty decoder
result. A screenshot of that message cannot identify which path failed, and
neither path proves a corrupt Core ML optimization cache. No affected-device
audio or diagnostic log was available for this fix.

The committed speech fixture `term-hex-1.wav`, scaled to 2.5% and 5% amplitude,
has peak 100 ms frame RMS of about 0.0062 and 0.0124. Both fail the previous
0.02 gate and pass the explicit 0.005 floor. A Linux PCM calculation confirmed
those values; added Swift tests exercise WhisperKit's actual gate and the two
error paths, including a successful next capture with the same engine. They
still require a macOS test run. This establishes a pre-inference false rejection,
not successful recognition or the cause of the reported temporary improvement
after optimization. Repeated real-device dictations and noise checks remain
necessary; no automatic re-download or cache reset was added.

## What is and is not verified

- **Linux (this change's development host):** no Swift toolchain, no Xcode, no
  model download. Only repository checks ran (Python CI/tool tests, shell and
  workflow lint, `git diff --check`). Pinned sizes and revisions were checked
  against the Hugging Face tree API and the WhisperKit 1.1.1 source.
- **macOS checks still required:** an unsigned archive is needed to first compile WhisperKit
  1.1.1 with Typr (its Swift 6.2 manifest uses unsafe flags for library
  evolution; upstream reports version pinning works on Swift 6.2). Added
  simulator tests target selection, preference, installer, decoding plan,
  tokenizer and log logic with fakes; they have not run on Linux and do not
  prove a successful real-model load.
- **Requires an iPhone:** download, Core ML specialization time, memory,
  accuracy, background behavior and thermal behavior. Checklist below.

### iPhone 16 (A18) checklist

Record raw recognized text and the cleaned result separately (Dictation log
shows both) for each case, with the engine and language.

1. **Download:** Wi-Fi download completes, progress rises smoothly, size about
   629 MB; Cancel then Retry; airplane mode during download shows "No internet
   connection" and Retry works; low storage shows the free-space message;
   force-quit during download, relaunch: not installed, Retry completes.
2. **Offline:** airplane mode after install: choose Whisper, prepare, dictate.
3. **Restart:** relaunch with Whisper chosen: it prepares at launch without any
   network request; first optimization time vs later (cold vs warm). Repeat after
   an iOS update: Core ML can invalidate its specialization cache and optimize again.
4. **Languages:** German, English, Automatic with German and English speech;
   mixed German with English tech terms (Pull Request, GitHub, Branch).
5. **Content:** names, numbers, dates and times; short (1–2 words) and long
   (45–60 s) dictations; silence and background noise (expect "no speech", no
   invented text).
   Also speak quietly/farther from the microphone, then at normal volume, without
   re-optimizing between captures. Compare failures: "recording is too quiet"
   means the amplitude gate; "returned no text" means decoding produced nothing.
6. **Keyboard:** warm-session dictation from another app with Typr in the
   background (Neural Engine, no GPU), repeated dictations in a row, auto-return.
   Also test a cold keyboard launch: preparation may exceed the 10-second handoff
   window, which must time out rather than start a stale recording; finish preparing
   in Typr and retry. CPU/Neural Engine avoids GPU restrictions but is not a
   guarantee that iOS will allow unlimited background execution.
7. **Switching:** Apple Speech ↔ Parakeet ↔ Whisper while idle; attempt during
   recording/transcription (refused); memory in Xcode's gauge never shows two
   Whisper models.
8. **Memory and thermal:** peak memory during preparation and transcription;
   device temperature and battery over ten consecutive dictations.
9. **Parakeet with German:** warning shown, engine unchanged.
10. **Apple Speech on iOS 18:** row shows "Requires iOS 26 or later"; an explicit
    choice fails with that reason and does not fall back.
