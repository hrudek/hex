# Static spatial word recognition

Step 2 consumes [current-word touch evidence](KEYBOARD_TOUCH_INPUT.md) for manual
German/English typing. It does not change dictation, visible keys, gestures,
hit-testing, field tracking, settings or the three-slot suggestion layout.
The owner approved this bounded scope after PR #95. No iikb package, pretrained
model, swipe code or personal touch model is imported.

## Contract

- The existing Autocorrect and independent Deutsch/English settings apply. Both
  selected languages participate; there is no inferred language or prior-word
  context. With Autocorrect off, spatial decoding does not run.
- Only an exactly aligned, fully observed word of 3–32 letters is decoded.
  Candidates have the same length, one tap per letter. Several spatially plausible
  substitutions may be recovered, but no missing/extra/reordered taps, word splits
  or predictive completions are introduced. The tracker still caps at 64 samples.
- Each tap is scored with a fixed isotropic Gaussian (sigma 0.35 key pitches)
  around the captured layout's key centers, with width/height normalization.
  No tap updates any parameter, even hypothetically during candidate scoring.
- Candidate score = sum of spatial log scores + 0.35 × log(count / corpus total).
  Both resources use their own retained count totals. The literal is scored even
  when absent from the word list (count floor 1); its frequency is not used as a
  spelling-validity signal. Each letter must be within 1.6 key pitches and within
  6 log-score units of the nearest key. No umlaut-to-ASCII folding occurs.
- Trie traversal has a shared 6,000-visited-node budget across selected languages,
  depth <= 32, and retains only the best eight distinct alternatives. Budget
  exhaustion discards the partial search: it cannot establish a safe runner-up.
  Missing data for either selected language also means full fallback, not an
  accidental preference for the one available language. Files are lazy-mapped;
  there is no retained word-result cache.
- The literal remains the left suggestion. Only alternatives scoring above the
  literal use the existing center/right slots; worse neighbors do not displace
  the usual completions of a correctly typed word. A new automatic replacement needs a >= 3 log-score lead
  over the literal, >= 2 spatial-only lead over it, and >= 1.6 score lead over the
  runner-up. These are conservative initial constants, not calibrated accuracy
  claims. If a complete spatial search is ambiguous, spelling-only guessing must
  not bypass its refusal to auto-replace.
- Existing explicit iOS Text Replacement, German umlaut rules and deterministic
  contraction/typo rules retain precedence. Otherwise valid words in either
  enabled system dictionary, contact/lexicon terms, kept words, shorthand,
  acronyms and internal-capital identifiers are not spatially auto-replaced.
- English candidates require system spelling validation for auto-replacement.
  Lowercase frequency entries do not establish German noun casing: German
  auto-replacement additionally needs an exact case-insensitive match among the
  German checker's guesses, using that validated spelling. Otherwise the word
  can be offered for manual selection, not silently capitalized or inserted.
- Today's drawn letter layout has no direct ä/ö/ü/ß keys. The data preserves these
  letters, but the spatial decoder cannot assign them invented key centers.
  Existing umlaut/digraph rules and accent-popup fallback remain responsible.
- No usable evidence/search result means the existing spelling-only behavior.
  Email/URL/no-autocorrection contexts, missing document text, invalidated evidence
  and unsupported input keep the step-1 fallback contract. Selecting a suggestion,
  space, deletion/undo and lifecycle invalidations still clear/alignment-check it.

## Learning and privacy

No new training, word/touch history, surrounding context retention, serialization,
logging, export, UserDefaults writes or network access. Word data is bundled,
public and immutable. Touch evidence remains the RAM-only current word.

The existing `LearnedWordsStore` and session suppression only protect explicitly
kept words, as before. Neither supplies priors or touch labels to this decoder.
The owner reports no legacy typing data that would need migration if that old
store is removed in a later change; this PR does not remove it or migrate data.

## Sources and checks

[WordData/README.md](TyprShared/FullKeyboard/WordData/README.md) records source
revision, CC BY-SA 4.0 terms, hashes, transformations and offline reproduction.
[PORTS.md](../PORTS.md) records the narrow MIT iikb algorithm adoption. Neither
resource's license is inferred from its repository's code license.

`SpatialWordDecoderTests` covers point-dependent ranking, DE/EN selection,
Unicode preservation, deterministic ordering, budget/length bounds, resource
corruption, geometry/strip offsets, literal/keep protection, language/off/field
rules, German spelling and actual app-bundle resources. Existing touch tests
isolate tracking with the spatial dependency disabled; the new suite covers
integration with it enabled, including space/undo and manual acceptance. A fixed
8-pair public-word fixture set checks bundled-data candidate recall and centered
controls. It uses synthetic points, not collected typing data. Offline Python
tests check the compiler and all
committed trie records/digests. Test presence does not imply a passing iOS run.

Still required before claiming improved typing quality:

1. Simulator compilation and suites, including suggestion selection and undo.
2. Real iPhone evidence coverage: confirm host callbacks leave fully observed
   words available during ordinary and fast two-thumb typing. No durable tap
   collection or analytics is introduced to obtain this proof.
3. Real iPhone cold mapping, per-word latency and extension memory measurements.
4. Fixed non-personal DE/EN typo/control evaluation, recording candidate recall
   and unwanted automatic replacements separately. Synthetic point fixtures are
   algorithm checks, not evidence of real typing accuracy or calibrated margins.

Linux provides none of the iOS/iPhone proof above. Learning, contextual language
models, dynamic hit targets and more permissive correction policies are separate
future decisions, not hidden extensions of this change.
