# Current-word touch evidence

PR #95 preserved information that fixed key hit-testing otherwise discards.
The tracker still changes no hit-testing, visible keys, gestures or dictation.
Its evidence now serves the [keyboard correction path](KEYBOARD_SPATIAL_DECODER.md)
and bounded [personal learning through trusted feedback](KEYBOARD_LEARNING.md).
The tracker itself has no settings or serialization; the separate default-on
learning switch controls personal model/count updates and inference.

## Ownership and coordinates

`AutocorrectEngine` owns `KeyboardTouchInput`. `FullKeyboardEngine` supplies each
unambiguous letter's inserted text, committed point and key, plus the complete
`KeyboardLayout` snapshot. Points use keyboard-view coordinates, including the
suggestion strip. A normal release uses its release point; rollover uses the
last point available when the earlier letter is committed, exactly once and in
insertion order. Shifted letters retain their inserted case.

Only a fully observed, contiguous prose word is available through
`touchInput.evidence(beforeInput:)`. It must match
`AutocorrectEngine.currentToken` exactly. Suggestions and replace-on-Space
validate that association before spatial ranking. Missing evidence preserves
the cautious spelling-only path. Hidden suggestions and disabled autocorrect
do not prevent tracking. Email/URL fields and missing document context do.

## Conservative invalidation

- Single-character backspace removes the last sample only if pre/post-edit tokens
  match; the remaining current word can survive. It cancels pending feedback and
  never relabels an erased tap. Any deletion/retyping disqualifies the entire word
  from learning labels and word counts, even if evidence remains useful for decoding
  or the word is reconstructed after deletion.
- Word deletion, unsupported inserts and unalignable edits clear current evidence.
  Accepted suggestions and autocorrect undo capture any usable evidence **before**
  clearing/replacing the current word. Space clears the tracker after the decision;
  the engine can retain that word in one bounded pending-feedback transaction.
  Earlier words are never restored from a touch history.
- Popup accents and slides between keys still invalidate evidence; their positions
  are not ordinary tap labels. The decoder can now interpret an ordinary a/o/u/s tap
  as a held ä/ö/ü/ß using that physical key's existing density and calibration, not a
  new popup center. This changes inference, not capture, hit-testing or label trust.
  Numeric/symbol input still falls back. Exact corpus prefixes need no touch evidence;
  noisy-prefix completion uses only an intact, fully observed word.
- External text changes (including dictation/paste), selection changes, field
  preparation, keyboard dismissal, memory warnings, canceled gestures and layout
  changes discard current and pending evidence. Held taps become unusable too,
  so a late release cannot recreate an invalidated word.
- After invalidation in the middle of a word, later letters cannot create evidence
  for just its suffix. Tracking resumes at a new, fully observed word.
- At most 64 samples are retained; overflow clears evidence until a new word.

The token parser excludes handles, paths, identifiers attached to punctuation
and other non-prose contexts. Apostrophe sequences have no tap alignment path.

## Feedback and privacy boundary

Current-word touch evidence and its single pending-feedback transaction stay
**RAM-only**: no raw tap serialization, UserDefaults, file, log, export or network
path. No surrounding field-text history is retained by the tracker. Its
`KeyboardTouchWord`/`TouchLabel` values are not Codable.

Automatic corrections **alone never teach** touch labels or word counts. Explicit
keep, associated undo and uniquely aligned manual alternative picks can supply
bounded labels; unchanged valid literals can settle only after an intact suffix
check when the next word's first unambiguous letter is inserted. A second Space,
double-space-period, Return or punctuation never settles a literal. Prefix completion picks supply word counts,
not labels. Full signal rules, distance/layout/finite guards and reset epochs
are defined in [KEYBOARD_LEARNING.md](KEYBOARD_LEARNING.md#trusted-signals).

For touch data, **only slow aggregated per-key/global counts, offsets and full
xx/xy/yy covariance are persisted**, not the word's points or order. The shared
~40/~8-label affine drift regressions and predictive weights stay RAM-only with no
per-key fast banks or recent-point reservoir;
they use exactly the same independent labels and reset on evidence discontinuities
(field/host/layout/lifecycle, ambiguous gestures, etc.), not ordinary word boundaries.
These memories change frozen word-recognition densities, never immediate hit attribution. The separate personal lexicon also
stores bounded kept words, trusted word counts and rejected pairs; diagnostics
store text-free counters/histograms. With real keyboard Full Access these files
are local, protected and excluded from backup; otherwise session-only. This is
not a persistent typing log and does not change the dictation-log exception.

## Deferred suggestions

The [suggestion worker](KEYBOARD_SPATIAL_DECODER.md#suggestion-worker-and-boundary-authority)
may hold a frozen copy of current-word evidence for one running job and one
replaceable latest request. These bounded snapshots are Sendable, RAM-only,
never Codable/persisted/exported, and not an ordered tap/text history. Their
captured layout and learning generation/epoch must still match before use. Frozen
calibration includes the complete covariance and aggregate affine-aim prediction;
trusted updates or actual fast resets invalidate the old ranking. Snapshot reads
and repeated empty resets do not themselves change learning ownership.
Cancellation drops queued copies immediately; an already running bounded search
may finish, but cannot publish, edit text or teach after invalidation. Discarding
geometry while visible (layer/layout change, key slide, trackpad, selection callback
or canceled touch) republishes current-token chips without taps; invalidation must
not leave the strip blank. Host resign/activate only suspends/resumes suggestions,
not the field: it preserves touches, caps lock/layer and immediate undo. Real
dismissal or an external text/selection callback still discards evidence as above.
A key touch or keyboard-originated edit resumes after a missed activation notice.

Rollover still commits a held letter synchronously exactly once. It only schedules
suggestions; neither the touch tracker nor insertion awaits ranking. Space retains
evidence through its existing authoritative synchronous decision, using an exact
ready cache if available. Accepting a chip revalidates its token/field/revision
before capturing evidence for feedback. Delayed completion, suspension, blocked
worker and overlapping-held-tap tests live in `KeyboardSuggestionWorkerTests`;
Linux does not prove real host callback/lifecycle ordering or iPhone latency.

## Exact boundary suggestions

The suggestion worker can compare exact two-part splits without new touch evidence.
It can use #118's immutable corpus model and bounded previous-context/language-weight
snapshot for conditional lifts of P(left|context) and P(right|left); no extra tap
window or personal history. Missing selected packs retain lexical-only split policy.
The automatic-split experiments failed name/product controls or had under 10% recall,
so Space/punctuation/Typr remain unchanged.
For spelling-preserving splits, observed-letter densities cancel against the literal;
existing whole-word spatial readings remain competitors. Exact joins inspect only
one adjacent textual suffix separated by one ASCII space, not a retained previous
word/space-tap window. No missing-space position or boundary label is invented.
Manual split/join choices and immediate undo teach **no taps, word counts or word pairs**;
acceptance still revalidates full ownership and the exact suffix before editing.
The boundary retrieval cache is cleared on evidence invalidation. Current/pending
raw taps, static hit-testing, Space/Typr gestures, double-space period and all
existing capture invalidations remain unchanged. This is not spatial boundary-error
recovery; see [the policy and limits](KEYBOARD_SPATIAL_DECODER.md#omitted-spaces-and-exact-joins).

## Corpus context suggestions

The [offline corpus context layer](KEYBOARD_SPATIAL_DECODER.md#offline-corpus-context-suggestions)
reads only a short RAM field suffix, separately from this touch tracker. It neither
extends the tap window nor stores personal contexts. Reordering current-token
suggestions preserves their completion provenance; after-space predictions have
no current token/tap alignment and teach no touch labels, word counts or word pairs.
P4's [personal next-word layer](KEYBOARD_LEARNING.md#personal-next-word-pairs)
counts only adjacent independently settled words (including deferred manual choices),
never silent automatic output or retyped/undone words. Its single RAM predecessor
resets on evidence/field/selection/language discontinuities; raw taps remain RAM-only.
Only bounded aggregate word pairs may persist with Full Access, never sentences or
app/host information. Automatic correction and conservative invalidation are unchanged.

## Proof limits

`KeyboardTouchInputTests` covers geometry, rollover, deletion/retyping, undo,
suggestions, external/held-tap invalidation, layout changes, accents, slides,
cancellation, trackpad, hidden suggestions, disabled autocorrect, non-prose
fields, overflow, missing context and unchanged tracking-only outputs.
`KeyboardLearningIntegrationTests` covers trusted feedback and invalidation;
decoder tests cover evidence use with spatial scoring enabled. Implemented tests
are not evidence of a passing iOS run; Linux cannot validate UIKit/host ordering.

Actual host callbacks, evidence coverage during fast two-thumb typing and
keyboard lifecycle behavior need the owner iPhone checks in the
[correction-path reference](KEYBOARD_SPATIAL_DECODER.md#required-owner-iphone-checks).
Conservative invalidation may reduce evidence coverage without changing typed
characters; coverage and learned model movement do not establish accuracy.
