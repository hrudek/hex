# Adopted sources

Typr is a standalone iPhone dictation keyboard. It is based on Hex by Kit
Langton (https://github.com/kitlangton/hex / https://github.com/anomalyco/hex),
MIT; [LICENSE](LICENSE) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)
preserve attribution. The commits and source links below are provenance, not
sync instructions or local dependencies.

| Feature | Source (repo) | Paths there | Last adopted commit | Files here | License |
| --- | --- | --- | --- | --- | --- |
| Hex iPhone app (base) | [anomalyco/hex](https://github.com/anomalyco/hex) (`dev`) | `ios/`, `app/AppIcon.icon/`, `tests/fixtures/vocabulary/audio/term-hex-1.wav` | `cae389a833178c5e104e6d00db894078afc29ea0` (`split/hex-upstream`) | `ios/` except Typr-specific files in the [feature table](TYPR.md#typr-features); icon at `ios/AppIcon.icon/`, WAV at `ios/TestFixtures/term-hex-1.wav` and [provenance README](ios/TestFixtures/README.md) | MIT, © Christopher Langton; [LICENSE](LICENSE) |
| iOS 26 full keyboard parity, 3-slot suggestions and cautious autocorrect | [anomalyco/hex PR #938](https://github.com/anomalyco/hex/pull/938), not merged upstream at split | 17 iOS paths listed below | `9029d2bcafb5504019d9ad979fa3883dd1659161`, via `ad1a58f4` / [hrudek/typr #28](https://github.com/hrudek/typr/pull/28) | The same 17 paths, with Typr conflict resolution and subsequent changes | MIT, © Christopher Langton |
| Automatic return to the host app: host detection via UIKit's keyboard arbiter, return by bundle ID | [AVGVSTVS96/iikb](https://github.com/AVGVSTVS96/iikb) (`main`) | `Packages/KeyboardModules/Sources/FullKeyboard/KeyboardHost.swift`, `Packages/KeyboardModules/Sources/KeyboardArbiter/KeyboardArbiter.c`, `App/Voice/HostApp.swift` | `f0f1e1f7a29ba915918729115d782ae494fc7244` | `ios/TyprKeyboard/KeyboardHost.swift`, `ios/TyprKeyboard/KeyboardArbiter.c`, `ios/Typr/HostReturner.swift`, `ios/TyprShared/HostReturnCatalog.swift` (translated, not copied; no `APP_STORE` stripping) | MIT, © Bassim Shahidy |
| AI cleanup prompt structure (role, "the speaker is never talking to you", cleanup / conversions / formatting / examples / output sections, output rule repeated after the transcript, German language instruction) and the duplicated-transcript output check | [OpenWhispr/openwhispr](https://github.com/OpenWhispr/openwhispr) (`main`) | `src/locales/en/prompts.json` (`cleanupPrompt`), `src/config/prompts/index.ts` (`wrapCleanupTranscript`), `src/config/languageRegistry.json` (`de`), `src/utils/cleanupOutput.ts` | `2e4768a603ec368a0ff11fdd25eb10a31c65b89b` | `ios/Typr/CleanupPrompt.swift` (structure and ideas adapted, wording rewritten for Typr: free rewriting, German tech examples, hyphen rule, spellings, data-only context), `ios/Typr/CleanupGuard.swift` (`duplicatesTranscript`, translated) | MIT, © 2024 OpenWhispr Team |
| Host detection safety (process-ID table) and the resuming URL table | [getdictus/dictus-ios](https://github.com/getdictus/dictus-ios) (`main`), which ports the table from [n0an/VivaDicta](https://github.com/n0an/VivaDicta) at `fac7599517d9110d0e8fc7b439b4e60709547144` | `DictusKeyboard/HostAppResolver.swift`, `DictusKeyboard/HostArbiterActivation.m`, `DictusCore/Sources/DictusCore/KnownAppSchemes.swift` | `8804c3629741b9aebe9475e0b2103769eb969dc5` | `ios/TyprShared/HostReturnCatalog.swift` (custom-scheme entries only; universal links left out), `ios/TyprKeyboard/KeyboardHost.swift` | MIT, © PIVI Solutions; VivaDicta MIT, © Anton Novoselov |
| Whisper tokenizer special tokens: the special-token table (end, English, no-speech, no-timestamps, start-of-previous, start-of-transcript, first timestamp, transcribe, translate, whitespace) and the `allLanguageTokens` set built from `Constants.languages` | [argmaxinc/argmax-oss-swift](https://github.com/argmaxinc/argmax-oss-swift) (`v1.1.1`) | `Sources/WhisperKit/Core/Models.swift` (`WhisperTokenizerWrapper.init`) | `1bbc57cb7fe6410248a685b1c5a3c6d56adc2ed4` | `ios/Typr/WhisperTokenizer.swift` (`TyprWhisperTokenizer`: translated, not copied; every token must round-trip or loading fails instead of upstream's pre-V3 default IDs, the whitespace token is the byte-level `Ġ`, and the word split is Typr's own minimal one, not upstream's) | MIT, © 2024 argmax, inc.; notice in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) |

## Keyboard correction, personal learning and diagnostics (iikb)

Owner-approved translation of selected ideas from
[AVGVSTVS96/iikb](https://github.com/AVGVSTVS96/iikb/tree/08df5aa1e698d8587b6dcaef53f5e555ba1fac2a)
at **`08df5aa1e698d8587b6dcaef53f5e555ba1fac2a`**, **MIT, © 2026 Bassim Shahidy**.
This extends the static decoder adoption at `9c74e51f0218a814e2e99756087d3f38ef003614`;
the reviewed Correction/Typing/MemoryStore/Stats sources are unchanged between
those revisions. The host-return adoption above retains its own historical pin.
No upstream package is built or added as a dependency.

Exact source and destination paths (multiple source ideas may share a destination):

| Source path at the pinned revision | Adopted/adapted idea | Destination files |
| --- | --- | --- |
| `Packages/KeyboardModules/Sources/KeyboardCore/Correction/Decoder.swift` | Best-first trie states, spelling trails, missing/extra/transposed-letter transitions | `ios/TyprShared/FullKeyboard/SpatialWordDecoder.swift` |
| `Packages/KeyboardModules/Sources/KeyboardCore/Correction/Lexicon.swift` | Compact trie traversal and corpus unigram priors; not its binary format | `ios/TyprShared/FullKeyboard/SpatialWordDecoder.swift` |
| `Packages/KeyboardModules/Sources/KeyboardCore/Correction/Corrector.swift` | Separate literal score, spatial/prior components and candidate provenance; not its automatic replacement policy | `ios/TyprShared/FullKeyboard/SpatialWordDecoder.swift`, `ios/TyprShared/FullKeyboard/AutocorrectEngine.swift` |
| `Packages/KeyboardModules/Sources/KeyboardCore/Correction/TouchModel.swift` | Layout-separated, pitch-normalized sufficient statistics, rewritten as bounded per-key diagonal mean/variance | `ios/TyprShared/FullKeyboard/TypingModelTypes.swift`, `ios/TyprShared/FullKeyboard/PersonalTypingModel.swift` |
| `Packages/KeyboardModules/Sources/KeyboardCore/Correction/TypingMemory.swift`, `Packages/KeyboardModules/Sources/KeyboardCore/Correction/LanguageModel.swift` | Explicit keeps, personal word counts and rejected corrections; only bounded unigram influence | `ios/TyprShared/FullKeyboard/TypingModelTypes.swift`, `ios/TyprShared/FullKeyboard/PersonalTypingModel.swift` |
| `Packages/KeyboardModules/Sources/KeyboardCore/Typing/TypingEngine+Words.swift` (`PendingWord`, keep/revert/settle) | One delayed feedback transaction and explicit choices, with stricter Typr trust/alignment rules | `ios/TyprShared/FullKeyboard/AutocorrectEngine.swift`, `ios/TyprShared/FullKeyboard/FullKeyboardEngine.swift`, `ios/TyprShared/FullKeyboard/KeyboardLearningSession.swift` |
| `Packages/KeyboardModules/Sources/KeyboardStore/MemoryStore.swift`, `App/Stats/TapsPage.swift` | Saved snapshot + Darwin notification + foreground reload; not private/shared upstream memory files | `ios/TyprShared/FullKeyboard/KeyboardLearningStore.swift`, `ios/Typr/KeyboardDiagnosticsModel.swift`, `ios/Typr/KeyboardDiagnosticsView.swift` |
| `Packages/KeyboardModules/Sources/KeyboardCore/Correction/Aim.swift`, `App/Stats/TapsPage.swift` | Pitch-to-point model display and layout selection, not raw recent points or an accuracy layer | `ios/Typr/KeyboardDiagnosticsModel.swift`, `ios/Typr/KeyboardTouchModelView.swift` |

Typr-specific adaptations and boundaries:

- Checked Unicode TSW1 DE/EN resources remain; one interleaved search has 6,000-pop,
  12,000-state/trail caps and an explicit above-literal completeness proof. At most
  one structural edit; incomplete search never authorizes inferred replacement.
  Below-literal structural retrieval is suggestion-only and best effort.
- Static hit-testing remains. Gaussian calibration uses shrunk/clamped means and
  diagonal variance, not iikb's NIW/Student-t mixture, pooled covariance or drift
  memories. No automatic-output touch/word-count training; manual labels must
  have independent unambiguous alignment and finite/distance/layout checks.
- Typr keeps deterministic rules, valid-literal/contact/keep protections,
  total/spatial/runner-up margins and English/German system validation. No borrowed
  posterior-best replacement policy or lowercased-frequency noun capitalization.
- Owner-approved local persistence is schema/epoch validated, byte/collection
  bounded and protected in the existing App Group, gated by actual Full Access;
  otherwise session RAM only. App read/reset UI, diagnostics definitions and
  `KeyboardDiagnostics.swift` are Typr's bounded design, not an upstream stats port.

Excluded from this adoption:

- Neural prediction/fine-tuning and contextual/app histories:
  `Packages/KeyboardModules/Sources/KeyboardCore/Correction/Network.swift`,
  `LanguageModel.swift`, `AppWords.swift`, and
  `Packages/KeyboardModules/Sources/KeyboardStore/PersonalNetwork.swift`
  (the three Correction files share the preceding Correction directory).
- Swipe (`Packages/KeyboardModules/Sources/KeyboardCore/Correction/Swipe*.swift`),
  dynamic hit targets (`Packages/KeyboardModules/Sources/KeyboardCore/Correction/KeyMap.swift`),
  split/join/space reinterpretation and decoder completions (`Corrector.swift`,
  `Decoder.swift`, `Packages/KeyboardModules/Sources/KeyboardCore/Typing/TypingEngine+Words.swift`).
- Raw recent-tap reservoirs (`TouchModel.swift`), unbounded JSONL statistics
  (`Packages/KeyboardModules/Sources/KeyboardStore/TypingStats.swift`), low-level
  trace (`Packages/KeyboardModules/Sources/KeyboardUI/TouchTrace.swift`), and
  “Accuracy = 1 − deletes/keys” (`App/Stats/Overview.swift`).
- Backup/network sources (`Packages/KeyboardModules/Sources/KeyboardStore/Backup.swift`,
  `Packages/KeyboardModules/Sources/KeyboardStore/Source.swift`), upstream voice,
  branding, entitlements and build/signing configuration. No keyboard network.
- **All** iikb resources, including
  `Packages/KeyboardModules/Sources/KeyboardEnglish/Resources/`; no model, lexicon,
  swipe weights or test corpus is copied. Typr's separate FrequencyWords data
  stays **CC BY-SA 4.0**, not MIT; exact provenance/hashes/reproduction remain in
  [WordData/README.md](ios/TyprShared/FullKeyboard/WordData/README.md).

The existing iikb MIT notice in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)
was checked against the pinned LICENSE and covers these adaptations; no duplicate
notice is needed. Short source comments credit translated ideas. Behavior,
synthetic Linux evidence and outstanding Apple/device proof are in
[KEYBOARD_SPATIAL_DECODER.md](ios/KEYBOARD_SPATIAL_DECODER.md); privacy, limits,
reset and switch semantics are in [KEYBOARD_LEARNING.md](ios/KEYBOARD_LEARNING.md).
Implemented regression suites include `SpatialWordDecoderTests`,
`SpatialTypoEvaluationTests`, `KeyboardLearningIntegrationTests`,
`PersonalTypingModelTests`, `KeyboardLearningStoreTests`, `KeyboardDiagnosticsTests`,
`TypingModelTypesTests`, `KeyboardDiagnosticsPresentationTests` and offline
`ios/tools/keyboard_words/test_build.py`. These listings do not claim an iOS pass.

## Offline corpus context suggestions (iikb)

Owner-requested P3 scoped translation, pinned separately to
**`09a2e9cdfbe851adff6c4646333c0a3f74ba8765`**, MIT, © 2026 Bassim Shahidy.
The source checkout was read only, never built/run. Historical adoptions above
retain their own pins and exclusions.

| Source paths at this pin | Translated ideas | Destination files | Exclusions / license |
| --- | --- | --- | --- |
| `Packages/KeyboardModules/Sources/KeyboardCore/Correction/LanguageModel.swift` (discount/backoff), `Packages/KeyboardModules/Sources/KeyboardCore/Correction/Corrector.swift` (prediction pool / contextual completion scoring) | Corpus-only absolute-discount backoff, bounded merged next-word suggestions and additive display-candidate scoring; rewritten for Typr TBG1 sidecars and D3b bilingual evidence, not copied files | `ios/TyprShared/FullKeyboard/KeyboardContextModel.swift`, `AutocorrectEngine.swift`, `FullKeyboardEngine.swift`; `ios/TyprTests/KeyboardContextModelTests.swift`, `KeyboardContextEvaluationTests.swift` | MIT, © 2026 Bassim Shahidy; no personal context counts, per-app histories, trigrams, neural weights/training, automatic-best policy, dynamic targets, swipe, emoji, themes, layouts, clipboard, network or dictation changes |
| Common Voice sentence collectors at `cd9dbfeeed7f2c377d6e9792f4d7a583c0ad3538`; Tatoeba DE/EN detailed exports 7 November 2026 (hash-pinned, named owners only) | Independently prepared training-only sparse bigram statistics and observed display spellings, fixed N=8,000/K=3/min=10; Typr's explicit offline deterministic compiler, input hashes and test fixture | `ios/tools/keyboard_context/`, `ios/TyprShared/FullKeyboard/WordData/keyboard-{de,en}.tbg`, `ATTRIBUTION.md`, `tatoeba-contributors.tsv`, reference/test JSON | CC0 1.0 + CC BY 2.0 FR, **not MIT**; no FrequencyWords counts/casing, no iikb resources or executable dependency. Full attribution/source-ID mapping and licenses linked from WordData and THIRD_PARTY_NOTICES.md |

Only a ≤256-character/2,048-byte suffix is read ephemerally; no field context,
posterior, pair counts or history is serialized. Automatic decisions/margins and
personal storage schema remain unchanged. New corpus suggestions follow selected
Autocorrect languages; no new switch. Existing contact/system name suggestions
remain independent of the corpus stock-name suppression list. See
[context behavior and proof limits](ios/KEYBOARD_SPATIAL_DECODER.md#offline-corpus-context-suggestions).
The existing full iikb MIT notice applies without duplication.

## Carried keyboard PR paths

The second row's current destination paths are listed below. In the adopted
source revision, targets used `HEXMobile`, `HEXKeyboard`, `HEXMobileTests` and
`HEXShared`, and the key view file was `HexKeyViews.swift`; Typr renamed these
locally without changing their provenance:
`ios/TyprKeyboard/KeyboardViewController.swift`, `ios/Typr/KeyboardSettingsCard.swift`, `ios/Typr/FullKeyboardSnapshotStage.swift`, `ios/Typr/KeyboardPreviewHost.swift`, `ios/TyprTests/AutocorrectEngineTests.swift`, `ios/TyprTests/FullKeyboardEngineTests.swift`, `ios/TyprTests/KeyboardLayoutTests.swift`, `ios/TyprShared/DotScope.swift`, `ios/TyprShared/FullKeyboard/AccentPicker.swift`, `ios/TyprShared/FullKeyboard/AutocorrectEngine.swift`, `ios/TyprShared/FullKeyboard/FullKeyboardEngine.swift`, `ios/TyprShared/FullKeyboard/FullKeyboardPalette.swift`, `ios/TyprShared/FullKeyboard/FullKeyboardView.swift`, `ios/TyprShared/FullKeyboard/TyprKeyViews.swift`, `ios/TyprShared/FullKeyboard/KeyboardKeyPlaneView.swift`, `ios/TyprShared/FullKeyboard/KeyboardLayout.swift`, `ios/TyprShared/FullKeyboard/KeyboardStripView.swift`.

The adopted keyboard settings controls moved from `ExperimentsCard.swift` into
`KeyboardSettingsCard.swift` in #85; the adopted commit and license are unchanged.

This list was derived with `git diff --name-only bbab250d^ 9029d2bc -- ios/`.
An upstream PR's status and head may later change; the adopted commit above
is the reference, not the current PR head.

At the split analysis, upstream `dev` was 11 commits ahead at `350c42db`;
none of those commits touched `ios/`. This is a historical observation,
not a claim about the current remote tip.

`src/…` paths in comments under `ios/` refer to `anomalyco/hex` at `cae389a8`.
In particular, unchanged comments in `TyprShared/DotScope.swift` and
`DotScopeShader.metal` name the desktop spring, scope and shader sources.
Some comments retain pre-reorganization names: at that commit,
`src/spring.rs`, `src/dot_scope.rs` and `src/dot_scope/scope.rs` correspond to
`src/rune_hud/spring.rs`, `src/rune_hud/dot_scope.rs` and
`src/rune_hud/dot_scope/scope.rs`. `src/rune_hud.wgsl` still has that exact path.
The old names are not literal file locations at the split commit; no Swift or
Metal comment was changed as part of the standalone split.
The scope also credits OpenCode's iOS port (`DotScopeView.swift`,
`DictationScopeBar`, `DotScopeShaders.metal`) from
[anomalyco/opencode](https://github.com/anomalyco/opencode), MIT, inherited
through the Hex base. Those references are provenance, not local dependencies.

`ios/appstoreconnect.json` and `ios/ExportOptions.plist` are inherited
configuration, updated to Typr's identity. Typr CI uses
`.github/typr/` for configuration and export options.

## How to adopt changes

1. Inspect the specific source revision in a separate checkout or on GitHub.
   `origin` stays `hrudek/typr`; no source/sync remote is required.
   Start each comparison at the feature's saved commit and restrict it to
   source paths, including icon/test resources where relevant.
2. Classify each candidate as a bug fix, improvement, irrelevant change, or
   dependent change (requires another adoption or desktop code). The owner
   decides what to bring over; there is no bulk merge.
3. Translate foreign code into the project's current architecture; do not
   blindly copy it. Inspect the exact source commit, dependencies, privacy
   contract and tests. Check the license first: **GPL, AGPL and LGPL are
   prohibited**. Update [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for
   new dependencies or attributions and preserve required license notices.
4. Use one cohesive PR per adoption, with tests and honest verification limits.
   Update this table in the same PR (source paths, last adopted commit,
   destination files and license). A normal adoption needs no switch; only
   a genuine experiment or owner-requested switch follows [TYPR.md](TYPR.md).
