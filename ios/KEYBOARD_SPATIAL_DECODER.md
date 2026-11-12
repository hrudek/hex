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

## Suggestion worker and boundary authority

Ordinary key insertion no longer calls suggestion ranking synchronously.
`FullKeyboardEngine.refreshSuggestions` validates current evidence, advances a text
revision, replaces stale alternatives with safe current-literal/keep chips and
submits a replaceable request. Refreshing an unchanged finished word/evidence/configuration
keeps its ranked chips visible and reuses its compatible decode rather than searching again;
checker/policy finalization still runs separately. One owned `KeyboardSuggestionWorker` has **one
running job and one latest pending preparation**, not a task/queue entry per key.
Preparation coalesces after key handling returns (including lazy personal snapshot
construction). Its immutable Sendable request includes revision, engine/field
ownership, bounded context/token, language configuration, learning generation,
feedback/reset epoch, resource revision, layout/evidence, calibration and personal
priors. No mutable checker or learning session crosses isolation.

A private actor owns `SpatialWordRanking` and its personal/corpus memos. The existing
search/scoring code is extracted unchanged from the main-actor resource facade;
immutable mapped resources and indexes are shared copy-on-write, not rebuilt or
expanded per request. Resource preparation remains detached. On completion the
main actor checks the entire ownership stamp **before** touching policy or UI,
adopts only an exact-compatible decode and runs the existing spelling/casing,
lexicon-completion and suggestion policy in a separate main-actor step.
`UITextChecker`/`GermanAutocorrect` never leave MainActor. This avoids checker
work on the insertion call stack, not every possible main-thread scheduling stall:
lazy snapshot construction and the checker finish can still occupy the main
actor between keys. Hardware event-to-insertion latency needs device measurement.

Space, the Typr key and sentence punctuation **never wait for the worker**.
A matching ready decode is reused by the existing synchronous authoritative
decision; if absent/stale, that boundary runs the same bounded synchronous search
and checker decision as before. Full ranking/automatic-policy semantics are
unchanged for a frozen eligible snapshot. Incomplete/below-literal results retain
their existing refusal/display-only rules; no partial result gains authority.
The final checker/policy decision is always made on MainActor, not cached as an
unconditional replacement. Immediate undo and learning association are unchanged.

Each published chip carries the originating ownership stamp. Picking checks
revision, context/token, current field routing/autocorrection permission, settings,
layout, learning generation and epoch again before deleting text or learning.
A held chip retains its touch-down choice rather than reading a possibly newer
slot on touch-up (at most three held choices); cancellation cannot select a new
slot. VoiceOver activation selects the current chip without a touch-down. An old
chip is refused even if a new field contains the same word after a field callback. No proxy API can identify an unreported field switch with identical
text/traits; actual host callback behavior remains an iPhone proof requirement.
Text/selection/field/layout changes, cancellation, hidden strip, dismissal,
remount, host backgrounding and memory warnings drop pending/stale work.
Discarding touch evidence (layer/width changes, key slide, trackpad or selection move)
republishes current-token chips without geometry instead of leaving the strip blank.
A refused chip refreshes the strip once, without editing or learning; a subsequent tap
uses current ownership. The existing 4 Hz settings poll compares published ownership
against current learning/configuration/resource revisions, including changes already
consumed by a chip's learning sync and newly installed resources.

Dismissal/backgrounding suspend suggestions; late jobs/warmup cannot read a hidden
proxy. Appearance prepares a field; host activation only resumes the strip, preserving
layer, caps lock, held touches, undo and menus. Key touch or keyboard-originated edit
(including a Typr-key Space) also resumes after a missed activation notice. A genuine
field/text callback still invalidates the previous association. In-flight search is
bounded but not preempted; cancellation releases the latest pending snapshot and
discards the old completion without starting overlapping searches.

Additional suggestion bounds: **256 context characters / 2,048 UTF-8 bytes**,
**64 token characters / 256 UTF-8 bytes**. Context uses the longest whole-character
suffix within both caps, so a large emoji/ZWJ prefix does not suppress literal chips.
An oversized final grapheme or token gets no strip ranking; boundary policy is unchanged.
The existing 64-tap and 2,000-personal-word bounds remain. Current/pending worker snapshots stay RAM-only and are
not a text/tap history. Each core retains at most three language-set corpus memos
of 4,096 entries; the worker and boundary have separate mutable memos, so their
memo payload can roughly double, while word-file/index backing stays shared.
Search arena **element payload** is capped at 1,632,000 bytes per active search
on the measured 64-bit Linux ABI (states, trails, heap indices and key/value
payload for dominance entries). A cache-missing synchronous boundary can overlap
one worker search, so budget two active arenas (3,264,000 bytes of element payload).
This excludes Swift container/capacity/allocator overhead, strings, other
matrices/caches and resources; it is not RSS, a
physical-footprint ceiling or an iOS ABI claim.

`KeyboardSuggestionWorkerTests` covers delayed/reordered completions, stale chips,
field/context/trait/language/layout/learning/reset changes, cancellation,
suspension, latest-only queueing, blocked-worker boundary fallback and held-tap
rollover. `KeyboardSuggestionEvaluationTests` compares complete search outcomes
(all scores/alignments/work), final strips and boundary decisions on the shared
DE/EN/mixed noisy-touch generator and reports recall, valid-control unwanted
changes, maximum-capacity personal scans, synthetic main-actor time and payload
bounds using `EVAL P1_...` lines. The injected corpus checker is deterministic,
not Apple's dictionaries; guessed intended words are fixture-supplied, so recall
is a scheduling-equivalence regression, not independent accuracy evidence.
Exact observed Linux checks are recorded below; the PR description carries the full
verification record. Test existence is not a pass.
Real-device checker timing, event-loop delay, rapid Space overlap in two hosts,
Full Access/lifecycle races and peak physical footprint remain unverified.

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
  cross-word context, neural model or swipe. A missing final letter is flagged as
  a manual completion; separate bounded prefix retrieval is described below.
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
  silently truncated and called complete. Today's drawn keys have no direct
  ä/ö/ü/ß centers: these letters share a/o/u/s density and calibration through
  `KeyboardLetterMap`, without invented popup centers. Popup gestures still
  invalidate evidence; existing digraph rules retain precedence.

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

## Prefix completions and physical letter holders

`SpatialPrefixSearch` reuses the validated TSW1 tries and their existing
max-descendant-count indexes; no new word data or resource limits. With
Autocorrect enabled and selected data available, the strip can extend a **2–31
letter** current prefix into a word of at most **32 letters**. Exact retrieval
requires no touch evidence, including NFC-normalized accented prefixes. An
intact word can additionally supply the decoder's same gated Gaussian densities
for at most **one noisy physical-key substitution** in the prefix. There are no
structural edits in this separate prefix search. A trusted valid/kept/contact
literal permits exact/holder extensions but not noisy-prefix reinterpretation.

The interleaved best-first queue ranks by relative prefix touch density plus
`0.35 × log(count / language total)` and an explicit equal selected-source
weight. Shared words retain their best component after deduplication; this is a
ranking heuristic, not a calibrated bilingual posterior. The max-count index
bounds the remaining suffix; terminal entries
compete with subtree entries rather than taking the first DFS leaves. Results
are deterministic, lowercase NFC/case-deduplicated across languages. At most
**512 pops, 2,048 generated states (including terminals), eight results**;
truncation is display-only best effort, unrelated to the authoritative decoder's
`complete` proof. Equal-frequency subtrees use lexical tie ordering without
expanding every tied subtree first. Requested bilingual data must all be present.

The existing literal/keep slot and correction/contact priority remain. Up to two
remaining alternatives can come from the corpus search before system guesses.
German noun casing is established only by the selected system dictionary, never
by lowercase frequency data. Completions, including noisy-prefix suffixes and a
missing-final-letter edit candidate, are flagged as such, never auto-applied at
Space/punctuation/Typr-key boundaries, and manual picks count the word without
labeling **any** taps. Explicit text replacements and deterministic rules keep
their authority. Same-length held-letter alternatives are manual alternatives,
not completions. Valid `schon/schön`, `uber/über`, and bilingual controls remain
protected from automatic changes; `fuer → für` and `Strasse → Straße` retain
their existing dictionary/digraph gates. No popup positions, new learned keys,
raw tap storage, layout/hit-target change, next-word prediction or network.

The prefix arena has a derived **294,912-byte payload ceiling** on this Linux
64-bit build (state values, heap indices and at most 64 UTF-8 spelling bytes per
state); this excludes allocator metadata/capacity rounding and is **not RSS**.
The mapped resources plus max-count indexes remain **3,924,496 bytes**. Prefix
state is per-call only, with no history/cache. This standalone P2 integration
runs bounded prefix retrieval in the existing suggestion assembly; its pure search
and immutable shared resources can also be scheduled by the separate suggestion
worker. It does not move resource preparation onto typing or alter FullKeyboardEngine.

`SpatialPrefixSearchTests` covers exact/noisy/held prefixes, NFC, frequency and
language-normalized order, equal-frequency broad tries, missing data, caps,
capitalized nouns, homographs/digraphs, manual completion feedback and actual
strip selection versus Typr-key Space. Its synthetic evaluation uses odd-index
common fixture words of length ≥5 with two letters withheld, original data and
an empty system-completion proxy, not a new independent lexical corpus. Printed
`EVAL P2_*` lines report recall@1/@3, the existing correction-only retrieval
baseline, work, wall time, controls and payload bounds. These measure retrieval,
not guaranteed final strip rank or real human accuracy. Apple checker/casing,
UIKit compilation, actual popup behavior, extension memory and iPhone latency
still require Apple/device verification.

Observed P2 Linux harness run (Swift **6.4.2**, debug, x86_64):

| Retrieval group | n | Recall@1 | Recall@3 | Correction-only baseline@3 |
| --- | ---: | ---: | ---: | ---: |
| DE, centered-noise / noisy-symbol prefix | 49 each | 32 each | 45 each | 0 |
| EN, centered-noise / noisy-symbol prefix | 39 each | 34 each | 38 each | 0 |
| Both, centered-noise / noisy-symbol prefix | 88 each | 63 each | 81 each | 0 |

Per-group prefix mean was **0.51–0.81 ms**, largest p95 **1.45 ms**, maximum
**1.71 ms**; at most **95 pops / 148 states** on these fixtures. Ten broad
prefixes without evidence averaged **0.68 ms**, max **54 pops / 207 states**.
These exclude correction search, checker calls, UI assembly and resource loading.
The new engine-level validity-proxy controls had **0/376** unwanted automatic
changes, and two explicit completion picks supplied two counts and **zero** touch
labels. The full harness executed **255 tests: 245 passed, 9 skipped, one known
Linux backup-metadata failure** (`isExcludedFromBackup` reads nil). Existing typo
recall@3 remained 318/384 tune and 341/384 holdout structural, 256/256 and 255/256
neighbor; both seeds retained zero wrong/control autos. Accent competitors can
increase ambiguity: neighbor correct-auto totals were 237 tune / 225 holdout,
versus historical 243 / 227, not an asserted improvement. No iOS build or device
performance/accuracy follows from this Linux run.

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

### Observed Linux P1 worker regression

Swift **6.4.2**, Swift 6 mode, Linux x86_64 **debug**, synthetic data, not iPhone
or simulator. The review-fix full harness run executed **266 tests: 256 passed,
1 known Linux backup-metadata failure, 9 platform skips**. All **17 worker and
4 evaluation tests** passed; the known failure remains visible, not weakened.
The repaired autocorrect-off, touch-input equivalence and repeated-literal tests
await final rankings, checking replacement, kind and completion status rather than
interim literals. Review regressions cover layer/width/gesture/selection refresh,
learning-toggle/reset refusal recovery, resource-install poll recovery, caps lock,
held touches, undo, key-touch/Typr-edit resume and unchanged-refresh reuse.
On 2,560 noisy snapshots, worker outcomes (including scores/alignments/search
work), strips and boundary decisions matched the synchronous API exactly.
The injected checker uses corpus membership and fixture-provided intended-word
guesses, not Apple's actual dictionaries or an independent quality benchmark.

| Frozen mode | Samples | Final-strip recall@1 / @3 | Wrong automatic changes, worker / baseline |
| --- | ---: | --- | --- |
| DE | 640 | 592 / 596 | 1 / 1 |
| EN | 640 | 589 / 592 | 1 / 1 |
| Mixed DE/EN | 1,280 | 1,163 / 1,166 | 1 / 1 |

The fixed noisy-case bound is one existing policy error per mode: intended
`aber` with transposed `baer` takes the German rule to `bär`; intended `live`
with missing first letter `ive` takes the English rule to `I've` (also in mixed
mode). This scheduling PR deliberately preserves both rather than changing rules.
**624 synthetic-valid word/name/compound/code-switch controls had zero unwanted
changes**. The 2,000-personal-word/calibrated snapshot test matched the synchronous
search; its cold worker scan took 164.242 ms here, reinforcing why it is not on
the ordinary insertion path.

A 160-key synthetic main-actor probe (20 × `keyboard`) simulated the old insertion
plus synchronous ranking versus current insertion: mean **5.363 → 0.019 ms**,
p95 **10.423 → 0.027 ms**, p99 **10.502 → 0.031 ms**, max **10.553 → 0.036 ms**.
English fixture-checker calls during insertion were **1,160 → 0**. Mean remaining suggestion-ready
wait after the burst was 1.099 ms across both variants. This deliberately excludes
host delivery/event-loop waiting, rendering and real checker costs; it is not an
iPhone speedup claim. Reproduction commands (run from this worktree):

```sh
/home/hrudek/code/typr-research/iikb-parity/harness/run.sh "$PWD"
python3 -m unittest discover -s .github/typr/tests -v
python3 -m unittest discover -s ios/tools/dictation_log/tests -v
git diff --check
```

The two Python suites passed **76 / 25 tests**. Shell syntax, ShellCheck and
Actionlint also passed. Harness exit **1** deliberately retains
`KeyboardLearningStoreTests.testRoundTripSummaryAndFileMetadata`: Linux Foundation
reads `isExcludedFromBackup` as nil. No other failure occurred; source status/hashes
were unchanged. The PR description records the full `EVAL P1_...` output, including
memory payload limits (not RSS); the harness test log also contains the original
spatial tables. UIKit strip/accessibility tests were not compiled or run here.
Real iPhone checks must include one insertion per chip tap/VoiceOver activation;
the accessibility override now calls its private activation callback directly,
not the touch control's primary-action event.

### Observed Linux x86 synthetic evaluation

These are standalone Swift 6.2 `-O` runner results before and after adding
suggestion-only retrieval on Linux x86_64 (AMD Ryzen 5 PRO 5675U), using the real
bundled data and repository fixture logic. **Not iPhone, not simulator, not real typing, not accuracy.** The validity
proxy is selected-corpus membership, **not UITextChecker** or German casing.
Personal learning was off. Synthetic neighboring-key symbols can differ from the
key center the generated tap aims at; this does not validate physical hit-testing.

The initial full 256-public-word, five-error-class run found structural display
recall only 21/768 (seed 1, σ .18) and 29/768 (seed 2, σ .22), with zero structural
would-auto replacements. The `log(.01)` penalty suppresses many otherwise
plausible edits below literal score. Subtree indexing/dominance preserved all
non-timing results while reducing mean edit-search pops from 860.2 to 232.0
(seed 1) and 886.5 to 236.9 (seed 2). This is a search-work measurement only.

The addition of suggestion-only retrieval kept scoring, penalties, margins and
caps unchanged. The final tests use even-index fixture words for tune (seed
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

With suggestion-only retrieval, B prefix mean/p95 was .43/1.39 ms tune and
.45/1.47 ms holdout; maximum observed work was 3,046 pops / 4,113 generated states. Fresh-process
read/validation/index cost was about 60–62 ms, excluded from decode timings;
filesystem caches may be warm. The derived index alone is 981,112 bytes
(~958 KiB); whole runner peak RSS was about 26 MiB, **not extension memory**.
An integrated Linux rerun matched all non-timing results after suggestion-only
retrieval. These historical runs are not checks performed by the documentation
task and establish no Apple
SDK build, system-checker behavior, iPhone latency or learning benefit.

### Observed Linux personal-snapshot change latency

The corpus-memo evaluation used Swift 6.2 `-O` on the same Linux x86_64 Ryzen host,
bundled DE+EN, 393 pt, synthetic `keyboar` taps offset +3/−2 pt, and 2,000 public dictionary words
each initially counted twice. After an initial decode populates the corpus cache,
each of **40 count changes** increments one existing word, builds a new snapshot,
decodes once, then decodes again. Medians from the same probe before/after the
corpus memo and snapshot-construction changes:

| Step | Before | After |
| --- | ---: | ---: |
| Snapshot / ScanList construction | 6.75 ms | 3.65 ms |
| First decode after count change | 30.49 ms | 2.37 ms |
| Warm decode, unchanged snapshot | 2.10 ms | 2.09 ms |

These are separate operations, not end-to-end keystroke measurements. The initial
corpus-cache-populating decode still took **31.12 ms before / 30.54 ms after**, with
snapshot construction and resource read/validation/indexing excluded. Capacity
clears and previously unseen language sets/words can incur fresh corpus lookups.
The earlier warm-only timings excluded snapshot construction and first-cache
work, so did not establish responsiveness after a word count changed. This probe
covers that gap; it is **Linux-only, not iPhone or simulator latency**. Both fixed
evaluation seeds retain all non-timing metrics (including search work); no typing
quality improvement or extension-memory measurement is claimed.

### Observed iOS simulator synthetic evaluation

Final GitHub run **42967899400** at `1c191b5a`, `TYPR-EVAL` output:
**Debug iOS simulator on GitHub macOS runner, synthetic taps, not iPhone**.
The Apple SDK build succeeded; the full run executed **580 tests with 0 failures**,
including the evaluation tests.

The same tune/holdout seeds, noise, corpus-membership validity proxy, learning-off
setting, 384 structural + 256 neighbor samples, 789 controls and 830 prefixes per
seed were used. A is same-length; B includes edits/display-only retrieval.

| Simulator metric | Tune | Holdout |
| --- | ---: | ---: |
| B structural display recall@3 | 318 / 384 | 341 / 384 |
| B neighbor display recall@3 | 256 / 256 | 255 / 256 |
| Neighbor correct would-auto, A / B | 244 / 244 | 228 / 227 |
| Structural correct would-auto, B | 0 | 0 |
| Wrong typo autos / unwanted control autos, A and B | 0 / 0 | 0 / 0 |
| Incomplete searches, A and B | 0 | 0 |
| Unavailable samples per variant (EN neighbor evidence-distance failure) | 0 | 1 |
| B prefix mean / p95, ms | 4.07 / 13.72 | 3.68 / 12.79 |
| B DE two-neighbor mean / p95, ms | 27.84 / 40.54 | 27.15 / 42.52 |
| B EN two-neighbor mean / p95, ms | 20.60 / 31.72 | 27.44 / 45.19 |
| Maximum pops / generated states, all groups | 2,419 / 3,113 | 2,990 / 4,113 |

All controls/prefixes were available. Aggregate recall and holdout automatic
outcomes match the Linux summary; tune neighbor correct would-auto totals are
244 per variant here versus 243 in the historical Linux run. Simulator timing
and search work are separate observations, not iPhone performance. Resource preparation is excluded from these decode
timings. No real typing or personal-learning benefit is established. A later Linux
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
