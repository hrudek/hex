# Keyboard correction path

This is the correction-path reference for manual German/English typing in Typr's
full keyboard. [Touch evidence](KEYBOARD_TOUCH_INPUT.md) describes capture and
invalidation; [Personal typing learning and diagnostics](KEYBOARD_LEARNING.md)
defines trusted feedback, storage, settings and counters. Dictation, visible keys,
gestures and the three suggestion slots are unchanged. The separate
[bounded letter-gap attribution](KEYBOARD_TOUCH_INPUT.md#bounded-adaptive-letter-attribution)
layer can change immediate letter insertion, never drawn keycaps or function-key cells.

## Immediate letter attribution

Before submitting deferred suggestions, edits synchronously prepare a ≤26-entry
`KeyboardKeyMap`. It combines #114's frozen learned xy covariance/aim density with
exact prefix continuation masses from existing TSW1 tries and bounded personal
prefix sums. The map is revalidated at insertion order, including rollover; stale
text/layout/configuration/model/epoch or non-prose/off states use geometry. No
checker, prefix search, word decode or worker wait is part of map preparation.

See [touch input](KEYBOARD_TOUCH_INPUT.md#bounded-adaptive-letter-attribution) for
all gates and memory/work bounds. P8b is deliberately **gap-only, horizontal
neighbors only**, with a **1.5%-width/half-gap** ceiling (previously 10%). It needs
four letters of known continuation (previously two), a 90% uniform novelty floor
(previously 50%), >ln(4) density / >ln(16) posterior margins (previously ln(2)/ln(4))
and agreement of both neighboring learned clouds. Unknown prefixes stop adapting;
backspace suppresses attribution for the remainder of the word, even after loss of
samples/layout refresh. Every drawn-keycap point stays literal. Attributed words
cannot teach labels/counts/pair endpoints; explicit keep protections still work.

Observed Swift 6.4.2 Linux debug synthetic evaluation (same existing public words,
one right-shifted trained model, identical fixed gap coordinates for both paths):

| Mode | Words / taps | Static → P8 → P8b hit errors | Wrong P8b reattributions | Candidate recall@1 / @3, static and P8b |
| --- | --- | --- | --- | --- |
| DE | 128 / 683 | 126 → 5 → 92 | 0 | 128/128 at both cutoffs |
| EN | 128 / 659 | 132 → 8 → 97 | 0 | 128/128 at both cutoffs |
| Mixed | 256 / 1,342 | 251 → 17 → 191 | 0 | 256/256 at both cutoffs |

P8 numbers are the earlier recorded baseline, not a second production engine.
Candidate recall is decoder retrieval (shared calibrated density, above-literal
candidates followed by literal/edit suggestions), **not** final strip rank or Space
precision. It was already saturated. The safer policy sacrifices about three
quarters of the earlier gap-probe benefit: it fixes 34/35/60 errors, not 121/124/234.
Seventeen center-tapped valid/homograph/name/compound/code-switch controls retain
zero changed taps and unwanted Space changes. The original `thrax → theax` case
is now **0/1 harmed** because its prefix is too short.

### OOV harm and attribution trade-off

`KeyboardKeyMapEvaluationFixtures` is an original list filtered against **both**
TSW1 packs: **455 unique absent items**, broken down in the touch reference.
Each is typed with precise, Gaussian, shifted Gaussian and deliberate correct-side
gap noise in each language mode. The common in-vocabulary fixtures also receive
those profiles. All policies see identical coordinates and frozen learned density;
there is no learning from these probes. Lowercase names deliberately remove the
capitalization shortcut. The noise model and off-letter-tail handling are documented
in [touch input](KEYBOARD_TOUCH_INPUT.md#bounded-adaptive-letter-attribution).

Harm means changing a **correct geometric hit** to a wrong letter. Tap denominator
is correct geometric taps; word harm counts runs containing any such change divided
by all OOV runs (not just final text mismatch). Static attribution has zero attribution harm by definition,
though it still has hit errors. Per language mode: **1,820 OOV runs / 22,124 taps /
21,841 correct geometric hits**; known-word runs are 512 DE/EN or 1,024 mixed.

| Frozen policy | OOV harmed taps / words, DE / EN / mixed | Known errors fixed, DE / EN / mixed | Known correct taps harmed, DE / EN / mixed |
| --- | --- | --- | --- |
| Previous P8: 10%, 50% floor, two-letter prefix | 20 / 28 / 24 (one tap per harmed word) | 11 / 12 / 23 | 7 / 3 / 10 |
| Prefix ≥4 only, previous other gates | 1 / 4 / 4 | 5 / 5 / 11 | 0 / 0 / 0 |
| **P8b selected: 1.5%, 90% floor, ≥4, stronger margins + consistency** | **1 / 1 / 1** | **1 / 2 / 2** | **0 / 0 / 0** |
| 0.5%, 95% floor, ≥4, ln(8)/ln(32) + consistency | 1 / 1 / 1 | 0 / 0 / 1 | 0 / 0 / 0 |

For P8b, per-mode OOV tap harm is **1/21,841 = .00458%** and word harm
**1/1,820 = .05495%**, below .2% / 1%. This is not just dilution by precise taps:
precise/Gaussian/shifted profiles have **0 harm**; deliberate gap stress has
**1/5,531 correct taps = .01808%**, **1/455 words = .21978%**, also gated below the
same bounds. Residual harm is `fahrradlieferzeit`, a productive compound with a
known prefix before the gap. Within the compound gap-stress stratum that is **1/80
words = 1.25%**; no per-category ≤1% claim is made. Identical coordinates still
cannot prove intent. Prefix-only gives more gain but more EN/mixed harm; narrowing
further loses nearly all gain without fixing this residual case. Hence the selected
conservative setting, not a claim of optimal tuning or zero risk.

On these more natural-noise known fixtures, static errors are **25 / 25 / 55**,
P8b errors **24 / 23 / 53**: only **4% / 8% / 3.6%** fewer. The map helps a tiny
subset of gaps, not drawn-keycap-interior or vertical errors. A real-engine replay
of all 455 OOV items (noise profiles cycled, inside German `das ist …` context,
both languages) matches map-only errors exactly, with **0/5,472 correct taps and
0/455 words harmed**; static errors **59**, adaptive **56**. Retrieval and automatic
Space replacement are separate from these immediate-insertion metrics.

These are deterministic **development** fixtures, not an untouched distribution,
population harm estimate, human-benefit claim or proof of all names/compounds.
Final full Linux run map-call p95 was **.283 ms**, max **.343 ms**; insertion p95
**.79–1.17 ms**, max **1.67 ms**, report-only and excluding asynchronous ranking.
Map element payload remains **4,160 bytes**, plus a ≤64-byte policy and one RAM
recovery bit; new two-pack continuation indexes **1,962,224 bytes**, full personal
index **112,392 bytes**. Existing indexes and mapped bytes are additional; TSW1
total **7,358,388 bytes** before context/runtime overhead, not RSS. No wall-clock
assertions, new resources, persistence schema, switch, network or dictation changes.
UIKit compilation, Apple checker/traits, actual thumb gaps/grip changes, learning
coverage, correction burden and extension footprint still require real iPhone proof.

Final P8b full Linux harness (Swift 6.4.2, debug): **385 cases, 375 passed,
nine skipped, one known Foundation backup-metadata failure** (`isExcludedFromBackup`
reads nil). All **15 attribution tests** pass, including complete/partial-word
same-spot backspace/retyping, repeated retries and preservation of ordinary intact
real-Space boundary windows. Source status and input hashes remained unchanged.
Python repository/dictation/word/context checks passed **76/25/4/7** cases; shell
syntax, ShellCheck, Actionlint and diff checks passed. Scratch Swift warning build
passed with no P8 slow-expression warnings. These are Linux checks, not an iOS build.

## Imported literal protections

The app-built [personal names and terms](KEYBOARD_LEARNING.md#personal-names-and-terms)
snapshot is independent of corpus frequencies and typing counts. An exact
imported token is valid and vetoes all automatic corrections before shortcuts,
digraphs and contractions; unlisted tokens keep existing authority. Boundary
chips cannot split or join across imported original tokens, including spatial
boundary candidates. Imported binary-prefix completions are manual-only and
precede speculative alternatives without displacing explicit/automatic choices.
Changing the snapshot invalidates suggestion configuration/caches so stale worker
results cannot authorize an edit. Straight/curly internal apostrophes now share
word-token handling. Adaptive prefix veto and device limits are documented in
KEYBOARD_TOUCH_INPUT.md. The pre-existing unimported-name/OOV automatic gates
remain suggestion-only; this package does not enable automatic split/join.

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
Undo persists its rejected pair with a 64-trusted-word global veto and an exact
one/two-predecessor-context veto until event 256, with identity labels only for
intact evidence; undo itself never keeps or counts the original. A fresh independent
literal can subsequently confirm a keep; see [learning](KEYBOARD_LEARNING.md#undo-literal-confirmation-and-acceptance-r2-3).
Legacy migrated pairs keep their permanent veto. Rejected forms include straight/typographic apostrophes; text replacements
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
priors, plus a checker-free completion job (token, languages, resource revision, intact
evidence/calibration and the personal scan while learning is on). No mutable checker or
learning session crosses isolation; preparation calls no checker.

A private actor owns `SpatialWordRanking` and its personal/corpus memos. The existing
search/scoring code was extracted from the main-actor resource facade for #113;
#114's frozen covariance/aim density and tighter length/next-child bounds now live
in that same core for both worker and boundary. The
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
- Each tap uses a normalized full-covariance Gaussian in key-pitch units: frame
  width plus gap horizontally, frame height plus row gap vertically. Static sigma
  is 0.35 with xy=0; trusted personal calibration is optional. Density is
  `−½ dᵀΣ⁻¹d − log(2π) − ½ log(det Σ)`, so different spreads remain comparable.
  [Slow/fast aggregate aim](KEYBOARD_LEARNING.md#slow-covariance-and-fast-aim) supplies
  pooled/shrunk xx/xy/yy and shared drift, with eigenvalues in [.22², .50²] and
  each center component within ±.50 pitch. Physical covariance is tempered by
  (.35/.20)² before these bounds. All tap/key densities, inverses and normalizers
  are frozen before search; the max-path objective and completeness proof still apply. The candidate gate is
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
  best gated key density, without an intended-letter label. This single-word search
  does not split/join; the separate suggestion-only boundary stage is described below.
  No cross-word prediction, neural model or swipe. A missing final letter is flagged as
  a manual completion; separate bounded prefix retrieval is described below.
- One deterministic best-first heap interleaves both language tries. Shared caps:
  **6,000 pops, 12,000 generated states and 12,000 spelling-trail records**, depth
  at most 32; at most eight distinct above-literal alternatives. Subtree maximum
  priors and state dominance tighten bounds without changing scoring. Two additional
  resource indexes hold child alphabet masks (UInt32/node) and saturated terminal
  suffix-length spans (UInt16/node). Length-incompatible subtrees are pruned; when
  the edit is spent or disabled, the next tap's maximum must name a child, not any
  key on the keyboard. This bound uses the frozen full-covariance scores, including
  positive densities. Unedited paths keep the optimistic suffix bound because they
  may still skip/swap. No below-literal result gains automatic authority. Selected
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
their authority, including the center chip's auto-replace highlight when a text
replacement extends its shortcut (`sig → signature`). The highlight uses the
actual decision kind: `.autoRule` is exempt from inferred-completion exclusions.
Same-length held-letter alternatives are manual alternatives, not completions. Valid `schon/schön`, `uber/über`, and bilingual controls remain
protected from automatic changes; `fuer → für` and `Strasse → Straße` retain
their existing dictionary/digraph gates. No popup positions, new learned keys,
raw tap storage, layout/hit-target change, next-word prediction or network.

The prefix arena has a derived **294,912-byte payload ceiling** on this Linux
64-bit build (state values, heap indices and at most 64 UTF-8 spelling bytes per
state); this excludes allocator metadata/capacity rounding and is **not RSS**.
The mapped resources plus max-count indexes remain **3,924,496 bytes**. Prefix
state is per-call only, with no history. Prefix retrieval runs **in the suggestion
worker** beside the correction decode: one `KeyboardCompletionRetrieval` holds the
evidence-aware result, the exact (evidence-free) result and up to eight personal
prefix words. Whether the literal is trusted needs the checker, so the main-actor
finish chooses exact or evidence-aware candidates exactly as before. The engine keeps
only the latest retrieval and reuses it for an equal job (token, languages, resources,
evidence, calibration, personal scan identity); otherwise, as for synchronous logic
callers or injected test rankers, it runs the same bounded retrieval inline. Resource
preparation stays detached; nothing is persisted.

With Learn from my typing on, [personal completion ranking](KEYBOARD_LEARNING.md#personal-completion-ranking)
(#101) moves kept or frequently typed completions ahead of the other corpus/system
completions and can add missing personal words with the prefix; it never changes
automatic replacement, contacts, spatial alternatives or protections. Off, completions
keep exactly the order described above.

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

## Omitted spaces and exact joins

`KeyboardBoundaryDecoder` adds **manual-only** alternatives such as `greatday → great day`,
`ichhabe → ich habe`, `thisis → this is` and `Tasta tur → Tastatur`. It runs in the
serial suggestion worker after the existing whole-word decode, using #118's prepared
corpus bigrams when available and the original lexical policy otherwise.
Space, sentence punctuation and the Typr key **never apply
these hypotheses automatically**, even when the worker has a ready result. Existing
whole-word rules/corrections keep their precedence and automatic policy.

- Exactly two letter-only parts, each at most **20 letters**, total **3–32** for
  splitting; one extra space may be removed from two adjacent tokens of at most 32
  combined letters. These **exact** hypotheses use no space-key geometry or consumed
  taps; the spatial extension below can reinterpret one observed tap. Neither path
  performs per-part spelling correction, number/unit runs, generalized segmentation
  or selection rewrites.
- Examine every bounded split point. Parts must exist in selected TSW1 resources,
  a small hand-curated closed-class short-word list, or the enabled personal model
  (kept or counted twice). All selected language packs must be present. Short words
  such as `I`, `a`, `in`, `am`, `is`, `zu`, `es` were previously filtered out by the
  resource compiler. The **42 language-specific entries** are Typr original work,
  not new third-party data: only one/two-letter closed-class words, fixed `.01` pseudo-prior.
- Score exact parts with their best full lexical log priors (TSW1, short-word
  supplement, bounded personal bonuses) and charge **ln(.01)** for the missing space.
  With every selected #118 context pack ready, multiply by the corpus model's
  conditional **lifts** P(left|previous)/P(left) and P(right|left)/P(right), using the
  existing discounted bigram/backoff mixture and bilingual language weight. When the
  two corpora agree on unigram frequency this equals P(left|previous)·P(right|left);
  keeping the TSW1 scale matters because FrequencyWords (subtitles) and the Tatoeba
  context packs estimate unigrams on different scales. Directly substituting context
  probabilities lost `I am` and `as if` to their corpus wholes in development.
  Absent words and missing context back off to lift 1; |ln lift| is capped at
  **ln(1000)**. A pair absent from the ≤16 retained followers only pays its row's
  backoff weight. Missing selected packs preserve the original lexical-only policy,
  never an English-only substitute. For parts with opposite-sign DE/EN evidence only
  positive lifts count: sparse monolingual rows must not penalize `mit you`.
- Compare against the whole literal's lexical/OOV prior times its own context lift,
  and up to eight existing whole-word readings, retaining their relative spatial
  density, structural penalty and personal bonus exactly once (`.35` prior weight
  converted to full scale, plus the reading's context lift). Exact split letters'
  spatial density cancels. This is a ranking heuristic, **not a probability of
  correctness**.
- FrequencyWords includes merged junk such as `inthe`, `ofthe`, `inder`. Inside this
  ranking only, the literal's corpus prior drops to the OOV floor when the whole is
  absent from every selected context vocabulary and the split has a retained edge
  with P(right|left) ≥ .05, lift ≥ 2 and P(left) ≥ .001. Whole-word spatial
  competitors still compete. This never relaxes dictionary validity (next bullet):
  a scan of both TSW1 packs shows the rule also fires on real words and names such
  as `comeback`, `herein`, `beider`, `Anden`, `todo`, `ina`, `malin`.
  Thresholds are development-fixture choices, not calibrated confidence.
- Joins charge the same edit penalty and require a **ln(100)** lead over separate
  lexical/OOV readings. If both parts are known, abstain regardless of frequency.
  In particular **`some thing` stays separate**: without contextual evidence there
  is no authority to call that valid pair accidental. Exact joins need no previous taps.
- MainActor vetoes splits for literals valid in either enabled dictionary
  (including German noun casing) without exception: the system checker, not the
  ranking corpus, decides that `comeback` is a word and `inthe` is not.
  Exact joins of two dictionary-valid parts are vetoed. Spatial Space-as-letter joins
  additionally need a better letter-versus-Space tap likelihood when both lexical parts
  are known; they are manual-only, including the ambiguous `a out → about` case.
  Explicit keeps, counted personal whole words, Contacts/lexicon terms, shortcuts,
  shorthand, internal capitals, acronyms, identifiers and non-prose token contexts
  retain protection. German noun casing uses the existing checker, not corpus casing.
  Umlauts/ß stay distinct; NFC is normalized, not folded to digraphs.
- The quoted literal remains. Boundary alternatives precede speculative spatial and
  prefix alternatives, but not an authoritative automatic fix or immediate rejection
  reversal. Phrase slots are excluded from #118's unigram-candidate reranker:
  they already include both conditional terms and must not be treated as nonexistent
  unigram words. #117's explicit `.autoRule` prefix-replacement highlight exception
  remains; boundary chips still force `autoReplace: false`.
  A chip carries its exact original suffix as well as the existing full
  field/context/revision ownership. Acceptance rechecks both before one suffix edit.
  One immediate Backspace restores the entire original suffix, including a join's
  original space. No constituent-word counts, tap labels or personal word pairs are
  inferred from a pick; it also breaks the RAM next-word predecessor.

Undo records a **session-only FIFO of at most 64 boundary rejection pairs**. These
phrases cannot enter the existing letter/apostrophe-only persistent pair schema;
no schema, file, Full Access permission or retention change. The immediate undo
strip offers the explicit reversal, as for existing word rejections; picking it
removes the new session pair. New typing/discontinuities end that special offer,
not the bounded session protection. Learning reset clears it; ordinary learning-off
retains protection. See [learning](KEYBOARD_LEARNING.md#manual-boundary-choices).

Combined exact/spatial work is capped at **144 lexical queries** (exact-only ≤74),
each visiting at most 32 letters × 30 child edges in each of two tries
(**276,480 edge checks**, deliberately loose).
No per-part decoder calls or personal-word scans. At most three retained results
plus one insertion transient; deterministic 1e-9 score buckets and lexical ties.
With context: at most **142 mixture-probability queries** (two for the literal, two
per whole competitor, four per split point) plus **62 language-evidence queries**. Each uses ≤2 immutable packs, bounded binary key search (≤14 steps,
≤128-byte keys) and ≤16 retained row edges; no vocabulary/follower enumeration.
The job stores only a ≤128-byte previous-context key and finite language weight
(**152 bytes** element/string payload); context is recomputed from #118's capped
256-character/2,048-byte RAM suffix. The **694,793-byte** context file/index payload
is shared COW, not loaded/copied per job. No new resource, context history or file.
The per-call candidate element/string payload bound on Linux 64-bit is **1,032 bytes**
(including raw NFD originals: a join may retain two 64-byte inputs plus a space);
the short-word element/UTF-8 payload is **754 bytes**, the 32-character scratch
array payload **512 bytes**, and the session-pair element/string payload bound
**10,368 bytes**. Shared personal/resource snapshots, other temporary strings,
Swift container/capacity/hash/allocator
overhead and other stages are additional; these are **not RSS or extension peaks**.
The single latest retrieval is reused only for equal job/evidence/learning/resource
inputs, including previous-context key, language weight and pack readiness; this
preserves worker reuse on unchanged refresh. Geometry invalidation
clears it. Normal production retrieval stays off insertion and checker finish; the
synchronous logic API/injected rankers can use the same bounded fallback.

`KeyboardBoundaryDecoderTests`, `KeyboardBoundaryContextTests` and
`KeyboardBoundaryEvaluationTests` cover exact
splits/joins, short/personal words, DE/EN selection, NFC, caps/ties, whole spatial
competition, checker/contact/keep/identifier controls, ownership, one-step undo,
rejection/reversal, no learning, conditional-score math, context cache ownership,
missing selected packs, noisy-touch recall, controls, work and byte bounds.
Wall-clock samples remain report-only, following #117; no timing assertions.
Evaluation distinguishes decoder retrieval from the actual two alternative chips
and from automatic decisions. Automatic precision is **N/A**, not 100%: the policy
abstains on all boundary hypotheses. OOV productive compounds/names can still look
like omitted spaces, so manual suggestions are not an assertion that the original
is wrong. Apple dictionary behavior, UIKit compilation, rapid pick/Space/cursor
ordering, Full Access storage and physical latency/footprint need Apple/iPhone
checks; a Linux synthetic run does not prove real typing benefit.

### Spatial boundary-tap recovery (P6)

A `KeyboardBoundaryTouch` immutable job value carries only fully observed, intact,
matching-layout evidence: either one current word, or one previous word + the actual
Space sample + current word, **32 combined taps including Space**, two nonempty
words, at most one changed boundary. No generalized multiword search or earlier-text
rewrite. The existing serial worker, job/cache equality, field/revision/suffix checks,
one-step undo and RAM-only 64-pair rejection policy are reused. A current-word split
and previous+current join are competing alternatives, never a combined three-word edit;
retaining a prior word does not hide current-word split recovery. Invalidation discards
both current and previous evidence; no late held-tap release can recreate the window.

- **Letter-as-Space** (`greatvday → great day`): consider only an interior observed
  c/v/b/n/m tap whose key frame actually adjoins this layout's Space frame. Compare
  P(left)·P(right)·density(Space,tap)/density(observed letter,tap) against the whole
  literal/OOV and up to eight existing spatial word readings on the full lexical scale.
  Unchanged letters cancel; there is no missing-tap penalty for a consumed real tap.
  Each literal part must exist in enabled DE/EN/short/personal resources, ≤20 letters.
  Dictionary-valid whole literals, keeps/counts, contact/shortcut/identifier protections
  retain authority. This new path is lexical/spatial, not an additional context beam.
- **Space-as-letter** (`a out → about`, `ha en → haben`): require the actual retained
  Space coordinate and intact evidence for both adjacent words. Try at most five
  geometrically adjacent c/v/b/n/m keys, each with a hard one-pitch x/y gate. Compare
  P(joined)·density(letter,tap)/density(Space,tap) against separate lexical/OOV priors
  with a **ln(100)** margin. Two known parts also require density(letter)>density(Space),
  so frequency alone cannot join them. Historical personal keeps/counts, contacts and
  shortcuts remain vetoes. `gr at → great` needs a nonadjacent `e` and deliberately
  abstains; this is not arbitrary missing-letter insertion.
- **Gratuitous Space**: retain the exact-join protections/ln(.01) penalty. With real
  geometry, compare the deleted tap's best gated Space/adjacent-letter density against
  its as-Space density. Two known parts remain protected, including `some thing`.
  Without coordinates the existing exact-join policy is unchanged.

Space's predictive density is **uniform horizontally over its actual bar, Gaussian
vertically with .35 row pitch**, with hard x/y support. It does not make the centre
more plausible than either thumb's normal bar position. Existing sanitized frozen
letter covariance/calibration is used when learning is enabled. There is **no trusted
Space training channel**, and no Space labels are inferred: sparse and calibrated
letter fixtures both recover `about` with the same static Space prior. Wide covariance
cannot license a distant/nonadjacent tap. The 393-point layout's n/m centres lie above
the Typr region and abstain (retained in the evaluation denominator); this does not
silently treat a Typr-key tap as Space geometry or change layouts/hit targets.

Normal release retains its actual point; rollover commits a held real Space at the
next key-down exactly once with the last observed point. Trackpad and all invalidation
rules still apply; a committed Space cannot later start trackpad. A Typr quick tap
still types Space/double-space-period but has **no geometry**. Programmatic/chip-created
spaces likewise fabricate no points. Corrected first words, second spaces, punctuation,
backspace, selection/field/layout/cancel/lifecycle/memory-warning changes drop the window.
Leading/trailing reinterpretations intentionally abstain rather than consume deliberate
second Space; both parts must be nonempty. A geometrically ambiguous real Space cancels
the first fragment's pending literal-learning feedback and breaks the RAM trusted-word
chain. Manual picks/undo train neither inferred boundary labels, constituent counts nor
personal pairs, and supply no inferred pair endpoint. Ordinary centred word boundaries
preserve #122's predecessor while retaining P6 geometry; the follower still requires
independent next-letter settlement. Language/evidence discontinuities clear pending
feedback and predecessor as before. No new file/schema/network/settings.

Each boundary snapshot has a **32,768-byte element/string payload cap**, checked before
retrieval; the 32-sample limit includes the retained Space. Only one previous word is
kept and replaced at the next real Space. Job snapshots/cache use the existing one
running + one latest worker, shared immutable resources and no per-part decoder. At most
72 combined letter/Space density evaluations (≤60 for splitting, ≤12 for join/deletion), in addition to
the lexical/context bounds above. Payload arithmetic excludes allocator/container
capacity and is not RSS; iPhone physical footprint is unmeasured.

**All spatial hypotheses remain suggestion-only.** 72 synthetic valid-pair control
calls produced zero automatic changes, but one ambiguous English boundary chip for
`a out → about` at the adversarial top edge (1/24 EN, 0/24 DE, 0/24 mixed; centred
Space controls have none). No automatic gate is installed, and precision is N/A for
an always-abstaining automatic boundary policy. This chip is reported, not hidden as
an accuracy win. Existing within-word automatic policy is unchanged.

Linux Swift 6.4.2 debug synthetic evaluation (five deterministic ±.08/.04/0 horizontal-pitch /
vertical-row-gap jitter variants per constructed fixture; retrieval and actual two-alternative chips,
not Apple's real dictionaries or held-out human typing):

| Language | Case | n | Recall@1 / @3 / chip@3 | Without geometry @3 |
| --- | --- | ---: | --- | --- |
| EN | Letter as Space | 10 | .50 / .50 / .50 | 0 |
| DE | Letter as Space | 20 | .50 / .50 / .50 | 0 |
| Mixed | Letter as Space | 10 | .50 / .50 / .50 | 0 |
| EN | Space as letter | 10 | 1 / 1 / 1 | 0 |
| DE | Space as letter | 10 | 1 / 1 / 1 | 0 |
| Mixed | Space as letter | 20 | 1 / 1 / 1 | 0 |
| EN | Gratuitous Space | 5 | 1 / 1 / 1 | 1 |
| DE | Gratuitous Space | 5 | 1 / 1 / 1 | 1 |
| Mixed | Gratuitous Space | 10 | 1 / 1 / 1 | 1 |

Observed per-call decoder p95 was **.36–1.83 ms**, max **1.83 ms** in the final full run;
latency is report-only (no wall-clock assertions, #117). This excludes worker queue,
UIKit/checker finish and key latency. Observed maximum touch payload **9,346 bytes**,
lexical queries **17**, deterministic result comparisons exact on repeated calls;
conservative hard ceilings remain 32,768 bytes and 144 queries. Picks/undo in both
spatial directions report label/count deltas **0**, one undo step and zero stale edits.
`KeyboardBoundaryTouchTests` and its evaluation extension cover real versus Typr Space,
letter/Space densities, calibration/learning-off, geometry gates, endpoint abstention,
rollover ordering, invalidation/late release, combined caps, suffix ownership and undo.
UIKit compilation, Apple dictionaries, two-host real Space/thumb behavior, simulator,
physical latency/footprint and Full Access behavior remain unverified on Linux.

Original P6-only Linux run: **352 total, 342 passed, 1 known Linux Foundation backup-exclusion
metadata failure, 9 explicit skips**; all nine P6 tests passed. Scratch Swift 6 build/
nine-test run with `-Xfrontend -warn-long-expression-type-checking=100` passed with
no long-expression warnings (one pre-existing unused-variable warning in P5 evaluation).
Repository Python checks passed **76 + 25 tests**; bash syntax, shellcheck, actionlint
and `git diff --check` passed. No harness adaptations were needed. These are observed
Linux checks, not Xcode/UIKit compilation, simulator or real-iPhone proof.

**M6 merge verification with #122:** the full Swift 6.4.2 Linux harness ran twice:
**370 total, 360 passed, 1 known backup-metadata failure, 9 skips**. All 11 P6 tests
(including two new integration regressions) and all 16 personal-pair tests/evaluations
passed. Normal real-Space and Typr-key DE/EN/mixed fixtures learned six pairs only
after follower settlement; four spatial-pick/undo scenarios produced zero inferred
pairs, counts or touch labels. Retained current-only splits also preserved the prior
real-Space window without expanding the edited suffix. P6 recall/control/byte/work
metrics were unchanged; final retrieval p95 .38–1.94 ms (max 1.94 ms), report-only.
The incoming exhaustive personal-mixture oracle was split into explicitly typed
scoring/sorting steps after a diagnostic compile found an 846 ms expression;
subsequent 100 ms-warning compilation plus 23 focused tests passed without
long-expression warnings. Repository Python 76 + 25, shell syntax, shellcheck,
actionlint and diff checks passed. No harness adaptation or Apple/device proof.

### Original P5 Linux synthetic check (before context integration)

Swift **6.4.2**, Swift 6 language mode, x86_64 debug; **12 targeted tests passed**.
Two fixed synthetic touch seeds (σ .18), exact typed letters and corpus-membership
checkers, not Apple dictionaries or real typing. Recall counts:

| Group | n | Retrieval @1 / @3 | Final alternatives @1 / @3 | No-boundary strip @3 |
| --- | ---: | ---: | ---: | ---: |
| DE | 48 | 45 / 45 | 43 / 43 | 0 |
| EN | 48 | 36 / 36 | 20 / 20 | 0 |
| Mixed | 32 | 27 / 27 | 25 / 25 | 0 |

The final strip contains only two alternatives plus the literal; @3 is the requested
upper cutoff, not three new phrase slots. Corpus-whole controls number 4/22/2 by
mode; the checker protects even source-noise tokens like `inthe`/`iam`, explaining
some retrieval-to-strip loss. These are small development fixtures, not an untouched
independent benchmark. All **6 exact join fixtures** reached the strip; **12 plausible
pairs** had zero join chips. Across **604 valid controls (602 unique)**, unwanted
automatic changes and valid-literal split chips were zero (validity is explicitly
injected). The 312 separately untrusted OOV controls produced **3 split chips**:
productive compounds can be ambiguous, reinforcing suggestion-only policy. Boundary
automatic recall is **0**, precision **N/A**. Complete-evidence split/join picks each
left accepted labels, word counts and stored touch state unchanged; 100 rejection
attempts retained 64 session pairs and zero persistent phrase pairs.

Direct boundary retrieval mean/p95/max was **.512/.855/.937 ms DE**,
**.514/.691/.915 ms EN**, **1.020/1.475/1.761 ms mixed**; join mean/max
**.690/1.106 ms**. The 128 adversarial length calls with 2,000 personal words
averaged **.551 ms**, max **2.383 ms**, at most **25 lexical queries** (cap 74).
These exclude whole-word decode, prefix search, snapshot/checker/UI time, resource
loading and scheduling; they do not predict iPhone end-to-end latency or memory.
The final full Linux harness executed **317 tests: 307 passed, 9 existing platform
skips, one known Linux backup-metadata failure** (`isExcludedFromBackup` reads nil).
All 12 boundary tests and all existing worker/nonregression suites passed, with
source hashes/status unchanged during the run. No harness adaptation or new skip.
Repository Python suites passed 76 + 25 tests; word-data tooling passed 4 tests;
shell syntax, ShellCheck, Actionlint and diff checks passed. None is UIKit,
simulator or physical-iPhone verification.

### P5b context integration and automatic-policy experiment

Same two-seed noisy-touch fixtures, worker path, final strip @3, context vs. same-run
lexical-only P5 policy, under two stated validity proxies (neither is Apple's checker):

| Group | n | Retrieval @3 ctx / lexical | Strip @3, merge-noise premise ctx / lexical | Strip @3, corpus-as-dictionary ctx / lexical |
| --- | ---: | ---: | ---: | ---: |
| DE | 48 | 47 / 45 | **47** / 45 | 43 / 43 |
| EN | 48 | 40 / 36 | **40** / 36 | 20 / 20 |
| Mixed | 32 | 27 / 27 | 25 / 25 | 25 / 25 |

The **merge-noise premise** rejects the fixtures' merged literals (`inthe`, `ofthe`,
…; `indie` stays a word), modelling a dictionary that does not list FrequencyWords
junk. The **corpus-as-dictionary proxy** treats every TSW1 entry as valid; P5's
reported EN 20/48 used it. Because production validity is `UITextChecker`, not
TSW1, the premise is the closer model, but neither is device evidence. P5b does not
relax dictionary validity, so the pessimistic proxy cannot improve: an earlier P5b
draft lifted it to 36/48 only by bypassing the checker, which would have shown splits
on dictionary words such as `comeback`/`beider`; that bypass was removed.
Merge-noise weakening fired on 16 EN and 2 DE noisy calls. No-boundary baseline
remains zero. Context adds **no** OOV chips: the **312 OOV controls** keep three
(`redis`, `esbuild`, `sunhat`, same as lexical); sparse ≤16-follower rows give no
principled evidence to remove them. The **604 valid controls** keep zero split
chips and zero unwanted automatic changes.

Automatic-split trial (test-only, never installed): candidates required a lowercase
literal rejected by the dictionary, a strong retained pair and whole/runner margins.
Controls: 1,920 accepted literals, 936 OOV, 108 product/identifier and **27
corpus-name** calls (lowercase TSW1 names/terms a dictionary may not list: `ina`,
`malin`, `andi`, `todo`, …; found by scanning both packs), each in DE, EN and both.

| Gate (whole / runner margin) | Recall (n=64) | False automatic splits |
| --- | ---: | ---: |
| ln 100 / ln 10 | 28 (43.8%) | 14: 12 corpus names, `athome`, `withyou` |
| ln 1000 / ln 100 | 23 (35.9%) | 10: 8 corpus names, `athome`, `withyou` |
| ln 10⁴ / ln 10³ | 6 (9.4%) | 0 |
| merge-noise wholes only, ln 100 / ln 10 | 9 (14.1%) | 12 corpus names |

Useful gates make false automatic splits on names; the single false-free setting
recovers 6/64 with the adjacent setting already at ten false splits, i.e. no safety
margin on small synthetic fixtures. **No automatic gate is installed**: actual
boundary automatic recall **0**, precision **N/A**, false automatic splits **0** on
all control calls. The <10% recall cut-off was chosen during this evaluation.

Final full Linux harness (Swift 6.4.2, debug): **343 tests, 333 passed, 9 existing
platform skips, one known backup-metadata failure**; all 18 boundary tests passed.
Direct boundary retrieval mean/p95/max **.674/.875/1.143 ms DE**,
**.725/1.106/1.148 ms EN**, **1.485/2.026/2.135 ms mixed**; 128 adversarial
length/capacity calls max **2.448 ms**, ≤25 lexical and ≤10 context queries (caps
74/142). These exclude whole/prefix decode, checkers/UI and scheduling; they are
diagnostics, not pass/fail criteria or iPhone latency. No Apple SDK/UIKit compile,
simulator, real dictionary or iPhone typing/peak-memory verification was possible.

## Sources and checks

[WordData/README.md](TyprShared/FullKeyboard/WordData/README.md) records unchanged
TSW1 DE/EN data, revision, CC BY-SA 4.0 terms, hashes and offline reproduction.
[PORTS.md](../PORTS.md) records the rewritten MIT iikb ideas at
`08df5aa1e698d8587b6dcaef53f5e555ba1fac2a`, plus aggregate covariance/aim
at `09a2e9cdfbe851adff6c4646333c0a3f74ba8765`. No iikb resources or dependencies
are bundled. Learning storage is owner-approved and bounded; raw current-word
and pending-feedback taps remain RAM-only, not a persistent typing log.

Implemented XCTest coverage includes `SpatialWordDecoderTests`,
`SpatialTypoEvaluationTests`, `KeyboardTouchInputTests`,
`KeyboardLearningIntegrationTests` and existing autocorrect/keyboard suites:
edit alignment and repeated-letter ambiguity, Gaussian normalization, priors,
DP oracle, deterministic ties, caps/completeness, suggestion-only separation,
validation/protections, feedback and undo. Offline Python tests validate the
compiler and committed resources. Test presence is not a passing iOS run.

### Merge verification: aggregate aim with the suggestion worker

After merging #113 into #114, Swift 6.4.2 Linux debug ran **283 tests: 273 passed,
1 known backup-metadata failure, 9 baseline platform skips**. All **19 worker,
4 worker evaluation, 8 aim and 4 aim evaluation** tests passed. No harness adaptation
or new skip was needed. The worker/boundary comparison matched all outcomes on
2,560 DE/EN/mixed noisy snapshots, retaining recall@1/@3 of 592/596 out of 640 DE,
589/592 out of 640 EN and 1,163/1,166 out of 1,280 mixed. The current synchronous
and worker paths each retain one existing deterministic-rule error per mode;
624 valid integration controls had zero unwanted changes. These are same-current-core
scheduling comparisons, not equality to an old binary or an independent quality claim.

Additional merge regressions check nonzero xy calibration in immutable worker
requests, learning/reset stale-result refusal, 100 no-op resets without generation
churn, manual-choice fast-aim retention and whole-result equality with a calibrated
2,000-word personal snapshot. P7b's grip/search/oracle/migration suites remain passing.
Synthetic insertion mean/p95 was .020/.027 ms (160 keys), versus 4.634/8.825 ms
with explicit synchronous ranking; checker calls during deferred insertion were zero.
The per-arena element bound stays 1,632,000 bytes; shared files/indexes total
5,396,164 bytes, and slow/fast numeric aim payload stays 5,184/320 bytes. These
exclude allocator/transient/container costs and are not iPhone latency or RSS.
Python 76 + 25 + 4 tests, shell syntax, ShellCheck, Actionlint and diff checks passed.
UIKit compilation, simulator, actual system dictionaries and iPhone typing,
ownership/lifecycle ordering, Full Access and peak physical memory remain unverified.

### Observed Linux P1 worker regression (before #114)

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

### Aggregate-aim synthetic ablation (P7b)

This replaces P7's too-easy 20-word/small-translation evaluation.
`PersonalTypingAimTests` checks independent covariance/pooling/affine-ridge
references, prequential switching, normalization, eigenvalue/determinant floors,
nonfinite data, rare-key transfer, return/reset, migration and bounded memory.
The exhaustive frozen-score DP compares both search implementations, including
positive/negative xy and ±.50-pitch centers. Length-bound tests retain one edit and
reject deep saturated paths without integer wraparound.

`PersonalTypingAimEvaluationTests` uses **128 public fixture words per DE/EN/mixed
group**, both languages enabled, identical deterministic seeded Gaussian coordinates
for each variant/checkpoint, and static hit-testing to produce neighbor-typo literals.
Two scenarios start with 3,000 accepted two-thumb labels, switch for 120 labels, then
return: (1) right-thumb undershoot toward a base below the bottom-right corner,
growing to **.6 horizontal pitches** at the far side, with .21–.28 pitch noise;
(2) **4° posture tilt** plus .15 pitch vertical translation, .22 pitch noise.
Two-thumb noise is .21 pitch with a small fixed per-key bias. Checkpoints are
**0/5/10/20/30/60/120 accepted trusted labels**, not all physical taps. Training
words are disjoint from evaluation words; offered/rejected counts are printed.
Synthetic perfect intentions are not evidence of actual manual-feedback coverage.

The three primary columns are static/no learning, **origin/main's slow diagonal
contract** (same accepted slow updates, per-key n≥20, shrink n/(n+20), ±.25 centers,
.22–.50 sigma), and the new model. The legacy test path retains the original
per-pair diagonal scoring and suffix-only search bound; it is a same-process
algorithm ablation at origin/main `15754813`, not a second iOS binary. A fourth
control variant holds the new density fixed with legacy search; a fast-disabled
new-model ablation separates drift benefit from covariance tempering. No baseline
numbers from a previous machine/run are used in these comparisons.

Recall denominators include **typo words only** (correct hit-tested words have no
reason to suggest themselves). One-hand has 312/384 typos: 105 DE, 107 EN, 100 mixed;
tilt has 169/384; return has 59/384. At 10/20/30 labels, one-hand pooled recall@1
is **304/307/299 of 312**, versus old **155/171/172** and static **236**; recall@3 is
**307/309/305** versus old **157/173/173** and static **241**. This is discriminative
but still synthetic/development evidence. Much of the gain precedes shift labels:
new is already 257 at label 0, and fast-disabled new is 249 versus old 154. Most
of that initial gap is the new slow density/tempering, not new grip evidence.
Holding the new slow model fixed but disabling fast drift gives **258/264/264** at 10/20/30, so the measured fast contribution is **46/43/35**
additional top-1 words, not the entire old-to-new gain. Tests require ≥8 percentage
points of typo recall benefit per language group from fast drift in that window.

On return, one-hand new recall@1/@3 stays **59/59** at every checkpoint versus old
54/59. Tilt return has one DE top-1/top-3 loss at **0 labels** (21/22 versus 22/22),
recovered by **5 labels**; the pooled new result is still 58/59 versus old 52/59.
There are no extra wrong typo autos in these curves. Declared regression tolerances
are two words per group (also two pooled) and at most one extra wrong typo auto,
at every checkpoint; these are deterministic fixture tolerances, **not confidence
intervals or calibrated human error bounds**. Observed unwanted changes of
correctly typed controls remain zero, including the existing 14-word adversarial
integration control (42 decisions, 2,600 allowed labels, zero self-training).

**A** disables structural edits (same-length spatial substitutions only).
**B** enables one missing/extra/swapped letter plus best-effort below-literal
edit suggestions for out-of-corpus literals. Thus outside B explores hundreds of
states even with learning off, whereas A takes about 20: most of this gap predates
P7, not a covariance regression. The new density can broaden search further, so
P7b adds length/next-child pruning, cheap finite-mask rejection and once-per-key
inverse/normalizer preparation. The performance evaluation prints mean/p95/max,
visits, completeness and ratios against both static and slow-diagonal legacy
paths on identical evidence; no incomplete result authorizes replacement.
Tests bound outside-B mean visits to old +10% and A to old +10%+8 pops, with
per-call visit/generated-state caps. Control latency ratios remain diagnostic
EVAL output only; the former old ×1.20 +.5 ms assertion was sensitive to shared
simulator scheduling rather than deterministic decode work. The original
total/spatial/runner-up margins are retained only with these quality/safety
ablations and the oracle; they are not posterior probabilities.

Observed Swift 6.4.2 Linux x86_64 debug control timings, same run (ms):

| Controls | Static legacy mean/p95 | Slow diagonal legacy mean/p95 | New mean/p95 | Mean visits static / slow / new |
| --- | --- | --- | --- | --- |
| In corpus A (437) | .715 / 1.049 | .681 / .940 | .751 / 1.108 | 12.5 / 11.5 / 11.8 |
| In corpus B (437) | 1.266 / 1.897 | 1.063 / 1.365 | 1.337 / 2.056 | 13.5 / 16.0 / 12.9 |
| Outside A (352) | 1.038 / 1.460 | .789 / 1.084 | 1.036 / 1.438 | 21.5 / 12.6 / 16.1 |
| Outside B (352) | 10.133 / 15.060 | 6.674 / 10.931 | 7.685 / 11.528 | 422.3 / 291.2 / 195.2 |

Outside B with the **new density but legacy search** takes 10.912 / 16.593 ms,
454.8 mean visits: the added bounds reduce its visits by 57% and mean latency by
30%. New beats the original static baseline, but **does not beat the old learned
narrow diagonal density in wall time**: outside-B mean is +15.2%, p95 +5.5%; other
small control groups have up to .274 ms mean overhead. On grip fixtures new versus
old means are 4.947 versus 3.933 ms (one-hand) and 3.083 versus 2.622 ms (tilt),
while visits fall to 114.4 versus 140.5 and 61.8 versus 85.4. Better recall explores
more plausible readings and the lookahead itself costs time. These remaining costs
are explicit, not a universal speedup claim. All measured searches are complete.
Snapshots average .535 ms and trusted single-label updates .048 ms separately.

Numeric slow/fast payload ceilings are **5,184 / 320 bytes**, excluding dictionaries,
strings, snapshots and allocator overhead. Shipping lexical files plus subtree
priors, child masks and length spans occupy **5,396,164 bytes** (<8 MiB); this is not
RSS, and loading/validation transients are extra. Four populated layouts encode to
20,363 bytes, under the unchanged 256 KiB store ceiling. The full Linux harness ran
**260 tests: 250 passed, 9 baseline skips, 1 known Linux-only backup-exclusion
metadata failure**; no new failure. No harness adaptation was needed. Apple SDK compilation, simulator, actual dictionaries, real feedback
coverage, physical grip recovery and extension latency/memory remain unverified.

## Offline corpus context suggestions

P4 additionally layers [trusted personal word-pair counts](KEYBOARD_LEARNING.md#personal-next-word-pairs)
over this corpus distribution for predictions and bounded display reranking.
The mixture, schema 3, privacy/deletion, trust gates and bounds live in that
reference. Prediction picks honor sentence auto-capitalization without lowercasing
German nouns. Automatic correction is unchanged.

`KeyboardContextModel` adds **suggestion-only** corpus context, not a new
correction objective. The corpus layer itself does not learn personal contexts. At a trailing space the strip
can show three next words; tapping inserts that word plus the existing separator.
No keep chip or automatic highlight is used for predictions. While typing with usable
context and all selected packs, existing spatial/spelling/completion alternatives
enter a bounded rerank of at most 32 items;
the literal slot, Contacts/lexicon slots and existing automatic/explicit-revert
first choice stay pinned.
Every strict prefix extension still carries completion provenance (no tap labels).
No second spelling engine or new switch is introduced. Autocorrect off, no selected
language, non-prose fields and host autocorrection refusal suppress predictions.
Missing selected sidecars abstain, never quietly prefer the other language.

The [TBG1 sidecars and notices](TyprShared/FullKeyboard/WordData/README.md#corpus-context-sidecars-tbg1)
are independent Common Voice CC0 + Tatoeba CC BY 2.0 FR statistics: 8,000 lexical
words/language, K=3 retained followers, min-count=10, **662,793 bytes combined**.
Off-main-actor preparation checks regular-file type and byte size before mapping
(or Foundation's safe-copy fallback), then validates every header, CRC, UTF-8
spelling, sorted row, offset and count before installation. Two UInt16 unigram
orders add **32,000 bytes**. File+index payload is **694,793 bytes**, not actual
resident pages, allocator overhead, high-water RSS or an extension footprint.

Scoring uses discounted backoff: `p0=(u+.5)/(U+.5*N)`;
`P(w|h)=lambda*p0(w)+max(c(h,w)-.5,0)/C(h)` for retained edges,
`lambda=1-sum(retained boosts)`. Full row totals include OOV/pruned targets, so
missing continuation mass backs off rather than disappearing. Nil/unknown context
uses unigram; explicit sentence punctuation uses `<s>`, never a cross-sentence
lexical edge. Corpus stock names `tom/mary/maria/john` are skipped by prediction
ranking only; they remain valid contexts/evidence. User contact, text replacement,
keep/revert and system spelling names remain available as before.

Bilingual weights now use the [R2-4 sentence posterior](KEYBOARD_LEARNING.md#sentence-language-posterior-r2-4)
with Float64 natural logs. The D3b lexical likelihood remains
`M=union lexical size`, `q_l(w)=(u_l(w)+.5)/(U_l+.5*(M+1))`,
`e=clip(log(q_de/q_en),-3,3)` (both OOV gives zero). Umlaut/ß and English
apostrophe cues add ±2 before clipping; known mid-sentence capitalized German nouns
with corpus ratio >4:1 add .6 after clipping. Fold at most eight recent observations
with `.75*S+e`, then clip S to ±6; `a_de=.05+.90/(1+exp(-S))`, `a_en=1-a_de`.
Two consecutive contrary cues, the latest of magnitude ≥1 (or an explicit umlaut/apostrophe
cue) clear old observations and discount the sentence's starting prior by .2.
One isolated loan word therefore does not discard the sentence. Sentence boundaries
clear observations and use `.25*S + .5*personalPrior`. The personal prior is ±1
at most, derived only from existing deletable counts while learning is on; see the
learning reference for caps/privacy. Numeric/non-prose barriers break adjacency
and add no evidence. Single-language selection uses only that pack, not the bilingual floor.
Exact top-three merges keys, seeds all row boosts, then scans descending unigram
orders until the third score is **strictly greater** than the next-background
bound. Ties use UTF-8 key order; display uses the larger weighted language
component, German on ties. At most **16,000 lexical visits plus 32 boosted
followers**; request-local seen keys are capped by the two 8,000-word vocabularies,
not a growing cache. Returned top-three storage is fixed size. Strings are ≤128
UTF-8 bytes/32 characters. No approximation is described as the exact oracle.

Current-token display candidates gain `.35 * clip(log(P_mix(w|h)/P_mix(w)), 0, log(20))`,
at most **+1.05 nats**, with the same language weights in numerator/denominator.
OOV names/compounds and non-followers receive zero gain, not a frequency penalty.
Spatial readings use `candidate.score + gain`; unscored spelling/completion alternatives
use `-.2*rank + gain`. Each evidence kind is sorted **only within its existing slots**,
never across kinds; ties retain original order. The .35 coefficient matches the spatial
decoder's language-prior scale. At most 32 candidates may enter the pure reranker
(integration assembles fewer than eight preceding alternatives plus at most eight
personal promotions, eight trie results and eight system completions). The completion
union is assembled before display truncation, so a full trie list cannot hide system
completions from context scoring. Personal promotions keep #115's count/keep order
as their baseline; completion provenance and personal-pick diagnostics survive the
rerank. **Learn from my typing off supplies no personal candidates, calibration or
count influence**; the public-corpus context gain remains active independently of
that switch. The corpus layer itself stores no personal context; P4's separate
approved follower counts participate only while learning is on. Without usable context, with Autocorrect off, or without
every selected pack, retrieval keeps the old two-alternative/checker-work budget.
This ranker cannot authorize any replacement: `decide`, automatic spatial scores/
completeness, German casing validation, protections, margins and Space/punctuation/
undo transactions are unchanged. Names and productive compounds remain protected
from automatic frequency chasing.

Corpus context extraction remains independent of stored personal follower counts.
Only the last **256 characters / 2,048 UTF-8 bytes** before the caret are
read in RAM; the active token is excluded from completed-word evidence. A clipped first word is discarded. The state is recomputed from that
suffix on each request (no repeated-word double consumption, retained cross-field
posterior, checkpoint history, new schema, file, log or network). R2-4 additionally
uses a generation-cached weak prior from existing trusted word counts; this does
not persist the reconstructed posterior or field suffix. Long fields therefore
use a bounded approximate history, not all earlier words. Unknown/empty fields
are not invented BOS. URL/email/identifier/number spans, malformed apostrophes and
non-whitespace control/format scalars are conservative barriers; ordinary tabs separate
words and newlines start sentences. Resource readiness requests a strip refresh;
while loading, old spelling behavior continues. Context scoring runs on MainActor in
the existing deferred suggestion **finish**, not on key insertion or in
`replacementOnSpace`. The serial worker still owns spatial ranking; no new queue or
checker adapter is added. Predictions inherit its revision/field/settings ownership,
including rejecting stale picks after a host edit without a callback.

### Observed P3 Linux checks and limits

Swift 6.4.2 debug Linux harness (12 November 2026): **14 context tests passed**;
all 47 D3b vector events reproduce state/weights and both top-three variants to
**1e-12**. All **20 worker tests** also pass, including a new blocked-current-word →
after-space prediction job/undo test. Original continuation-gated worker-policy
fixtures explicitly omit corpus context, so asynchronous resource readiness and the
new legitimate after-space job cannot contaminate their frozen pre-context contract.
The full run executed **298 tests: 288 passed, one known Linux
backup-metadata failure, nine skips**. File preflight/sliced data, malformed input,
large Unicode suffixes, prediction ownership and no-context checker-work guards
are included. The local harness additionally redirects the exact bundled context
resource initializer to its SwiftPM resource bundle; no algorithm/assertion/skip
adaptation was added. The new 128-sentence CC0 global-test fixture measured DE R@3 **14.06%** versus unigram
**4.91%** (448 lexical pairs), EN **17.74%** versus **6.68%** (434 pairs); truncated
MRR@3 **.0967 / .1359**. This tiny, SHA-ordered held-out fixture is digest-disjoint
from training, not author/template-independent or natural messaging. Runtime
stock-name suppression is applied in these figures.

Independently authored synthetic sequences measured DE/EN/mixed R@3
**50.00% / 40.00% / 33.33%** (14/15/12 pairs). Mixed wrong-language slots were
**36.11%** versus **44.44%** for 50/50, using D3b's fixed smoothed 4:1 unigram-ratio
proxy and all suggestion slots as denominator. This intentionally abrupt tiny
mixed sample remains poor: no natural multilingual quality claim. Nine synthetic
neighbor-typo fixtures (three/group) retained 3/3 first-choice recall per group,
zero changed automatic decisions; 20 injected-valid literal/name/compound/homograph
controls had zero unwanted autos. The validity checker is injected, **not Apple**;
this checks integration/nonregression, not production precision or a ranking gain.
A controlled `ich ha` completion test demonstrates promotion while Space leaves
`ha` unchanged. Existing larger spatial evaluations remain unchanged.

An additional integrated evaluation synthesizes one-/two-neighbour typos for held-out
CC0 words in their left contexts, with both languages selected. DE/EN/mixed recall@1
and strip recall@3 remain **688/722, 669/686, 717/746**, respectively, identical to
no-context. The centre first choice is pinned whenever automatic policy chooses it;
only two DE strips changed their other slots. There is **no measured noisy-touch
recall improvement**, and no automatic-policy change. All 2,154 typo decisions and
1,077 correctly typed controls match baseline; wrong/unwanted autos are zero in both
variants under the injected held-out-vocabulary validity proxy. Serial call latency
(suggestions + cold per-engine spatial/checker path, excluding the boundary call)
mean/p95/max is **11.712/20.620/29.963 ms** baseline and
**12.668/21.690/30.620 ms** context. This is not key-handler latency or an Apple checker.

Alternating held-out DE↔EN sentences (417 pairs, both selected) measure posterior
recall@3 **15.11%** versus **13.43%** neutral and **15.11%** hard switch. Wrong-language
slots are **3.12% / 27.74% / 2.00%**; the first three predictions after a switch are
**6.42%** wrong versus **25.17%** neutral. The hard-switch comparison uses the same
corpus-ratio proxy and can still make code-switched words unreachable; no human
multilingual accuracy claim follows.

41 warm prediction calls measured mean **.342 ms**, p95 **.664 ms**, max **.983 ms**
on the original P3 Linux debug run. Timings are reported only, never test pass/fail
criteria (including cold preparation and integrated noisy-touch calls), following
#117. Deterministic result, candidate/work and byte bounds are the gates.
Detached preparation/cold mapping/checksum work is excluded; a separate
detached readiness test measured **867 ms** with filesystem pages potentially warm.
The production offline compiler freshly rebuilt both packs, the owner roster and
credits from all six hash-pinned raw inputs, then independently recounted/compiled
byte-identically. The generated CC0 fixture also matches byte-for-byte.
No UIKit compile, simulator, iPhone, system dictionaries, natural code-switch quality,
content-safety/DRM review, actual RSS or main-thread key latency was verified here.
Those remain owner/Apple checks. These figures describe the original P3 run before
integration of #115–#117; the M3 verification below records the combined tree.
## Evaluation regression gates

Keyboard evaluations introduced with #113–#115 gate deterministic work and behavior,
not shared-runner wall time. Aim/control and worker comparisons assert decoder
visits/generated states (6,000/12,000 caps); prefix tests assert 512/2,048 caps,
including broad prefixes. Existing recall, unwanted-change, complete-search,
learning/trust, exact worker equivalence and byte-bound assertions remain.
Deferred insertion asserts zero checker calls; a continuation-gated worker stays
blocked while Space completes and undo remains linked, proving boundary independence
without a one-second deadline. Personal completion tests retain result/2,000-entry
and payload bounds. Timing samples, percentiles and same-process ratios are still
printed in `EVAL` lines, including aim snapshot/update timings, but are not test
pass/fail criteria. Async readiness timeouts are synchronization safeguards, not
latency budgets. This avoids runner pauses failing a quality/work regression test;
actual latency and peak memory still require measured iPhone acceptance checks.
No settings, resources, storage, learning policy or privacy contract changed.

### M3 merge verification with #115–#117

Merged freshly fetched `origin/main` at `8d376dd7` into the context branch, retaining
#115's offline prefix/holder candidates and personal completion ranking, #116's
storage-test setup fix and #117's deterministic evaluation gates/text-replacement
highlight. Context reranks the assembled system/trie/personal completion union in
the deferred worker finish, never on ordinary key insertion or in `decide`.
New worker-path regressions cover all three completion sources and their union,
learning-off identity versus an empty personal model, count-only completion feedback,
contact precedence and explicit text-replacement authority/highlight. The four source
fixtures all promote the contextual target; worker and synchronous strips match.

Full Swift 6.4.2 Linux debug harness: **325 tests: 315 passed, one known Linux
`isExcludedFromBackup` metadata failure, nine baseline skips** (338.788 s).
All **18 context, 20 worker, 12 personal-ranking and 11 prefix tests** passed.
No new harness adaptation or skip. Python infra/dictation/context/word suites passed
**76/25/7/4**; bash syntax, ShellCheck, Actionlint and whitespace checks passed.
Context timings are now report-only, consistent with #117; result/call counts,
search work and byte bounds remain deterministic gates.

Held-out next-word R@3 remains **14.06% DE / 17.74% EN**, versus unigram
**4.91% / 6.68%**. The 2,154 held-out noisy calls have identical context/no-context
automatic decisions and zero wrong/unwanted automatic changes under the injected
validity proxy, including 1,077 clean controls. Current merged-baseline recall@1 is
**684/722 DE, 669/686 EN, 713/746 mixed**, recall@3 **688/722, 669/686, 717/746**,
identical with/without context. Unlike the original P3 run, #115 now recognizes
more candidates as manual-only completions; these are same-current-core comparisons,
not equality to the pre-#115 automatic baseline. No noisy-touch recall gain is claimed.
The larger worker equivalence evaluation matches all 2,560 noisy snapshots; all
624 valid/name/compound/code-switch controls have zero unwanted changes. Its existing
one deterministic-rule error per language mode remains unchanged, not hidden.

Prediction mean/p95/max **.336/.649/.957 ms**, cold preparation **904.706 ms**;
integrated noisy-call mean/p95 **12.211/21.389 ms** baseline and **13.735/22.842 ms**
context. These are Linux debug observations, **not timing assertions or iPhone
latency**. Context file/index payload stays **694,793 bytes**, not RSS. The combined
lexical files/indexes plus context payload are **6,090,957 bytes**, below 8 MiB
before arenas, containers, personal snapshots, checkers and rendering. Full EVAL
lines and exact commands are in the P3/M3 research handovers. No UIKit/SwiftUI Apple
SDK compile, simulator, real dictionaries, iPhone typing/Full Access or peak physical
memory was verified; all owner checks below remain required.

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
   pooled influence (or 20 per key in a migrated legacy-only model), separate layout
   models, shift/shift-back recovery, no automatic-output self-training,
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
