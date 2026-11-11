# Keyboard correction path

This is the correction-path reference for manual German/English typing in Typr's
full keyboard. [Touch evidence](KEYBOARD_TOUCH_INPUT.md) describes capture and
invalidation; [Personal typing learning and diagnostics](KEYBOARD_LEARNING.md)
defines trusted feedback, storage, settings and counters. Dictation, visible keys,
gestures, static hit-testing and the three suggestion slots are unchanged.

## One boundary, one decision

`AutocorrectEngine.decide` serves both suggestions and replace-on-Space.
`replacementOnSpace` records one decision transaction; tapping the Typr key uses
the same Space path. Return never autocorrects or records a new decision boundary;
it does not settle learning feedback either. Unchanged literals settle only on the
next word's first unambiguous letter with the previous word still intact. A second
Space, double-space-period and punctuation never teach. The existing Autocorrect and independent Deutsch/English
settings apply; both languages default on. Autocorrect off disables spatial decoding
and boundary decisions, not explicit suggestion feedback or diagnostics inspection.

For a prose token in a text field permitting autocorrection, precedence is:

1. Session suppressions, explicitly kept words and the shorthand allowlist veto
   automatic changes, including rules and text replacements.
2. Explicit iOS Text Replacement wins over inferred correction.
3. Internal-capital identifiers are protected. German umlaut/digraph rules run
   before deterministic English contractions/typos. All-caps words get only the
   existing narrow rule exceptions, not inferred spelling/spatial correction.
4. Inferred correction requires at least three letters and no apostrophe. Contacts/
   lexicon terms and a literal valid in **either** enabled system dictionary are
   protected. German validity includes title-case checking, so lowercase `haus`
   is not changed to a different word just because the dictionary knows `Haus`.
5. Spatial decoding may replace only after the completeness, margin and system
   validation checks below.
6. Otherwise the existing cautious spelling fallback runs, German guesses first,
   then English. Missing evidence, a missing selected-language resource or word
   data still loading permits this fallback. An **incomplete search blocks inferred automatic replacement**.

Rejected typed→replacement pairs veto every automatic path. After a complete
spatial refusal, the spelling fallback is blocked only when an above-literal
same-length or transposition candidate has a **nonnegative spatial-only lead**
over the literal. A prior-promoted but geometrically worse neighbor no longer
vetoes spelling fallback (the PR #96 finding). A recorded spatial refusal may
therefore coexist with a successful spelling-fallback decision. The dashboard calls
these “Paths that declined to replace”, not reasons the final word stayed unchanged.
Undo suppresses the original for the session and persists its rejected pair, with
identity labels only for intact evidence; it never permanently keeps or counts the
original. Rejected forms include straight/typographic apostrophes; text replacements
with spaces, digits or other punctuation get session-only undo suppression (no saved pair).
The explicit keep chip still permanently protects it, including while
learning is off; off supplies no labels/counts.

## Evidence, scoring and bounded search

- Decode only a fully observed word with 3–32 aligned letter taps, matching the
  current token and captured letter layout. The tracker itself retains at most
  64 samples. Apostrophes, popup accents, slides, missing document context and
  non-prose fields do not create substitute geometry.
- Each tap uses a normalized diagonal Gaussian in key-pitch units: frame width
  plus gap horizontally, frame height plus row gap vertically. Static sigma is
  0.35; trusted personal calibration is optional. Density includes
  `-log(2πσxσy)`, so different spreads remain comparable. The candidate gate is
  radius 1.6 pitches from the model center and within six log units of the best
  key for that tap. The literal is scored separately, without the relative gate.
- Score = spatial log density + structural edit penalty +
  `0.35 × log(count / retained language total)` + bounded personal word bonus.
  Absent literal/candidate counts use floor 1; the literal takes its best prior
  across selected sources. Bundled membership is **not** spelling validity.
  Candidate scoring uses immutable calibration/lexicon snapshots, never updates
  learning, and uses the best alignment score, not summed alignment probability.
- Match/spatial substitution can consume each observed tap. At most **one**
  structural edit is allowed: missing candidate letter, extra observed tap, or
  adjacent transposition. Each costs `log(0.01)`. An extra tap contributes its
  best gated key density, without an intended-letter label. No split/join,
  cross-word context, neural model, swipe or predictive decoder completion.
- One deterministic best-first heap interleaves both language tries. Shared caps:
  **6,000 pops, 12,000 generated states and 12,000 spelling-trail records**, depth
  at most 32; at most eight distinct above-literal alternatives. Subtree maximum
  priors and state dominance tighten bounds without changing scoring. Selected
  resources are mapped, fully validated and subtree-indexed in a detached task
  started on keyboard appearance with Autocorrect on, then installed on the main
  actor. Until ready, decode immediately reports unavailable(resource), so spelling
  fallback runs without blocking typing. Boundaries count `resourceLoading`
  (“Word data still loading”), separately from missing/invalid data. Missing either
  selected language is resource unavailability, not a preference for the other.
  Injected lexicons remain synchronous for deterministic tests. The engine caches
  the current evidence/languages/learning-generation result, not an unbounded word
  history. Resource-loading outcomes are not cached across readiness.
- The personal scan considers at most 2,000 sorted kept or count≥2 words,
  retaining only those absent from all selected corpora and passing length/alphabet/
  first-letter geometry filters. Normalization, sorting, alphabet labels and maximum
  bonus are prepared once per immutable snapshot, normalizing each word once.
  Filtered entries track snapshot identity so count bonuses stay current. A separate
  word-level corpus-absence memo survives snapshot/count changes, keyed by selected
  language set (at most three sets, each capped at 4,096 words; cleared at capacity
  before inserting an unseen word). Installing resources clears both caches.
  New snapshots only repeat corpus lookups for unseen/evicted words; a first decode
  with a new language set still populates its memo. Per-decode scan work is otherwise
  length/geometry filtering and scoring only the absent words. The model validates
  and enforces one combined kept ∪ counted bound of 2,000 words, evicting unkept
  counts before keeps. Thus
  personal snapshot size within that bound never invalidates completeness. An
  oversized externally supplied snapshot is still refused as incomplete, not
  silently truncated and called complete. Today's drawn keys
  have no direct ä/ö/ü/ß centers: Unicode data is preserved, but no centers are
  invented. Existing digraph rules and popup fallback remain responsible.

`complete` certifies the exact top-eight distinct **above-literal** spellings
under this bounded candidate universe and frozen max-path objective. Ordering uses
rounded 1e-9-log-unit score buckets, then spelling and language; pruning retains
that tie window. This avoids platform-dependent key-center/libm/sum rounding
breaking mathematical ties, with a transitive comparator. It is not
an accuracy estimate. Essential arena truncation or unfinished search prevents
that proof; partial results can still supply manual suggestions, never automatic
replacement.

## Automatic versus display-only candidates

Same-length automatic replacement requires total lead ≥3 over literal,
spatial-only lead ≥2, and runner-up gap ≥1.6. Structural replacement requires
literal invalidity in every enabled dictionary, no protection, total lead ≥3 and
runner-up gap ≥1.6; its edit penalty is already in the total. Both require a
complete search. These are initial safety constants, not calibrated probabilities.

English candidates must pass the system spelling checker. German candidates
must exactly match a German checker guess case-insensitively and use that
validated spelling; lowercase frequency data cannot establish noun casing.
Personal-only candidates need the same German match or enabled English
validation. Personal priors never authorize invalid automatic insertion.

The left slot stays the quoted literal; center/right use the existing pool of
automatic fix, spatial alternatives, lexicon terms and system guesses/completions.
The decoder additionally retrieves up to **two display-only structural candidates**
at or below literal score, within one edit penalty of it, only for literals absent
from every selected corpus. They follow above-literal candidates and use remaining
search budget with half-arena limits. Retrieval is **best effort**, not covered by
`complete`, and never feeds automatic decisions or the geometry veto. The engine
filters structural suggestions for valid/kept/contact literals and rejected pairs.
The decoder's display list is not a guarantee of the final two visible alternatives.
Every strict prefix extension is a completion regardless of retrieval source
(including spatial `keyboar → keyboard` or spelling guesses); picking it records
manualCompletionPick and a word count but no touch labels. Internal missing-letter
alternatives such as `helo → hello` still use conservative alignment labels.
Deleted/retyped words can retain decoding evidence but supply no labels or counts.

## Sources and checks

[WordData/README.md](TyprShared/FullKeyboard/WordData/README.md) records unchanged
TSW1 DE/EN data, revision, CC BY-SA 4.0 terms, hashes and offline reproduction.
[PORTS.md](../PORTS.md) records the rewritten MIT iikb ideas at
`08df5aa1e698d8587b6dcaef53f5e555ba1fac2a`. No iikb resources or dependencies
are bundled. Learning storage is owner-approved and bounded; raw current-word
and pending-feedback taps remain RAM-only, not a persistent typing log.

Implemented XCTest coverage includes `SpatialWordDecoderTests`,
`SpatialTypoEvaluationTests`, `KeyboardTouchInputTests`,
`KeyboardLearningIntegrationTests` and existing autocorrect/keyboard suites:
edit alignment and repeated-letter ambiguity, Gaussian normalization, priors,
DP oracle, deterministic ties, caps/completeness, suggestion-only separation,
validation/protections, feedback and undo. Offline Python tests validate the
compiler and committed resources. Test presence is not a passing iOS run.

### Observed Linux x86 synthetic evaluation

These are P1b/P1c standalone Swift 6.2 `-O` runner results on Linux x86_64
(AMD Ryzen 5 PRO 5675U), using the real bundled data and repository fixture
logic. **Not iPhone, not simulator, not real typing, not accuracy.** The validity
proxy is selected-corpus membership, **not UITextChecker** or German casing.
Personal learning was off. Synthetic neighboring-key symbols can differ from the
key center the generated tap aims at; this does not validate physical hit-testing.

P1b's full 256-public-word, five-error-class run found structural display recall
only 21/768 (seed 1, σ .18) and 29/768 (seed 2, σ .22), with zero structural
would-auto replacements. The `log(.01)` penalty suppresses many otherwise
plausible edits below literal score. Subtree indexing/dominance preserved all
non-timing results while reducing mean edit-search pops from 860.2 to 232.0
(seed 1) and 886.5 to 236.9 (seed 2). This is a search-work measurement only.

P1c kept scoring, penalties, margins and caps unchanged and added suggestion-only
retrieval. The final tests use even-index fixture words for tune (seed
`0x545950525f503031`, σ .18), odd-index words for holdout (seed
`0x545950525f503032`, σ .22). Both are halves of the same public word set, not
an independent lexical corpus. Each half has 384 structural and 256 neighbor
samples; both variants also run all 789 controls (437 in-corpus, including 145
rare words; 352 outside) and 830 prefix calls per seed.

| Final synthetic metric | Tune | Holdout |
| --- | ---: | ---: |
| B structural display recall@3, before → after retrieval | 12 → 318 / 384 | 13 → 341 / 384 |
| B structural correct would-auto replacements | 0 | 0 |
| B neighbor recall@3 | 256 / 256 | 255 / 256 |
| Neighbor correct would-auto, A same-length / B edits | 243 / 243 | 228 / 227 |
| Wrong typo autos / unwanted control autos, A and B | 0 / 0 | 0 / 0 |
| Incomplete searches, A and B | 0 | 0 |
| Unavailable samples per variant | 0 | 1 |

The holdout unavailable sample is one EN neighbor evidence-distance failure,
not exhaustion; all controls/prefixes were available. Recall@3 refers to the
decoder display list, not final strip placement or user choice. Zero unwanted
autos on these controls is not a false-positive guarantee. Structural autos
remain **zero**; no real typing quality improvement has been demonstrated.

P1c final B prefix mean/p95 was .43/1.39 ms tune and .45/1.47 ms holdout;
maximum observed work was 3,046 pops / 4,113 generated states. Fresh-process
read/validation/index cost was about 60–62 ms, excluded from decode timings;
filesystem caches may be warm. The derived index alone is 981,112 bytes
(~958 KiB); whole runner peak RSS was about 26 MiB, **not extension memory**.
P3c's integrated Linux rerun matched all P1c non-timing results. These historical
runs are not checks performed by the documentation task and establish no Apple
SDK build, system-checker behavior, iPhone latency or learning benefit.

### Observed Linux personal-snapshot change latency

P11 measured Swift 6.2 `-O` on the same Linux x86_64 Ryzen host, bundled DE+EN,
393 pt, synthetic `keyboar` taps offset +3/−2 pt, and 2,000 public dictionary words
each initially counted twice. After an initial decode populates the corpus cache,
each of **40 count changes** increments one existing word, builds a new snapshot,
decodes once, then decodes again. Medians from the same probe before/after P11:

| Step | Before | After |
| --- | ---: | ---: |
| Snapshot / ScanList construction | 6.75 ms | 3.65 ms |
| First decode after count change | 30.49 ms | 2.37 ms |
| Warm decode, unchanged snapshot | 2.10 ms | 2.09 ms |

These are separate operations, not end-to-end keystroke measurements. The initial
corpus-cache-populating decode still took **31.12 ms before / 30.54 ms after**, with
snapshot construction and resource read/validation/indexing excluded. Capacity
clears and previously unseen language sets/words can incur fresh corpus lookups.
The earlier P9 warm-only timings excluded snapshot construction and first-cache
work, so did not establish responsiveness after a word count changed. This probe
covers that gap; it is **Linux-only, not iPhone or simulator latency**. Both fixed
evaluation seeds retain all non-timing metrics (including search work); no typing
quality improvement or extension-memory measurement is claimed.

### Observed iOS simulator synthetic evaluation

GitHub run **42954810678**, `sim1.log` `TYPR-EVAL` output:
**iOS simulator on GitHub macOS runner, synthetic taps, not iPhone**.
The Apple SDK build succeeded; the full run executed 560 tests with three failed
assertions in two decoder tests (deterministic ties and undo boundary labels).
The evaluation tests themselves passed. P7 fixes those assertions' causes and
adds Linux regression checks; a new Apple simulator run is still required.

The same tune/holdout seeds, noise, corpus-membership validity proxy, learning-off
setting, 384 structural + 256 neighbor samples, 789 controls and 830 prefixes per
seed were used. A is same-length; B includes edits/display-only retrieval.

| Simulator metric | Tune | Holdout |
| --- | ---: | ---: |
| B structural display recall@3 | 318 / 384 | 341 / 384 |
| B neighbor display recall@3 | 256 / 256 | 255 / 256 |
| Neighbor correct would-auto, A / B | 243 / 243 | 228 / 227 |
| Structural correct would-auto, B | 0 | 0 |
| Wrong typo autos / unwanted control autos, A and B | 0 / 0 | 0 / 0 |
| Incomplete searches, A and B | 0 | 0 |
| Unavailable samples per variant (EN neighbor evidence-distance failure) | 0 | 1 |
| B prefix mean / p95, ms | 2.77 / 9.08 | 2.88 / 9.62 |
| B DE two-neighbor mean / p95, ms | 23.51 / 32.67 | 22.57 / 30.88 |
| B EN two-neighbor mean / p95, ms | 19.36 / 29.53 | 21.01 / 32.61 |
| Maximum pops / generated states, all groups | 2,419 / 3,113 | 2,990 / 4,113 |

All controls/prefixes were available. Aggregate recall/automatic outcomes match
the Linux summary; simulator timing and search work are separate observations,
not iPhone performance. Resource preparation is excluded from these decode
timings. No real typing or personal-learning benefit is established. P7's Linux
Swift 6.2 optimized rerun on both seeds preserved every recorded non-timing
metric (including pops/generated summaries) versus the prior Linux final runs.

## Required owner iPhone checks

First compile app/keyboard/widgets and run the actual iOS test target in Apple
CI/simulator, including system spelling/casing and settings/navigation tests.
Then check on the owner's iPhone:

1. Evidence coverage during ordinary and fast two-thumb rollover in several host
   apps; host callbacks, selection moves, paste/dictation, popup accents, slides,
   trackpad, orientation/strip/globe changes, dismissal and memory warnings.
2. DE/EN and mixed-language valid neighbors, lowercase German nouns/compounds,
   names, technical terms, shorthand/caps, missing/extra/swapped letters; suggestion
   selection, explicit keep and immediate undo. Separate unwanted automatic
   replacements from candidate recall; do not infer correctness from silence.
3. First-word resource load, suggestion and Space latency distributions, extension
   high-water memory, repeated keyboard recreation and responsiveness during saves.
4. Trusted learning association and outlier rejection; at least 20 labels before
   per-key influence, separate layout models, no automatic-output self-training,
   learning off/on, retained keep/rejected protection and independent resets.
5. Full Access granted/revoked, RAM-only behavior, restart retention, file protection
   before first unlock and backup exclusion, lock contention, concurrent keyboard
   controllers, reset/save races and stale-state handling. Same-epoch writers are
   last-writer-wins, not merged deltas.
6. Dashboard save notification/foreground/pull refresh, stale/no-snapshot wording,
   touch model accessibility, both reset confirmations, compact and large text;
   optional `settings-keyboard-diagnostics` snapshot scene is synthetic only.

Do not collect a raw tap/text archive for these checks. Learning, diagnostics and
synthetic recall do not establish improved typing accuracy or iPhone performance.
