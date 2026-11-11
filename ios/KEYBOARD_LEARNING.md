# Personal typing learning and diagnostics

Typr's full keyboard can retain bounded personal touch statistics, word choices
and text-free diagnostic counters on this iPhone. This owner-approved storage
replaces the old kept-word store; it is **not RAM-only**. It is not a typed-text
history, raw tap archive, contextual language model or accuracy measurement.
The keyboard never accesses the microphone, speech model or network.

[Keyboard correction path](KEYBOARD_SPATIAL_DECODER.md) is the single reference
for candidate scoring and automatic replacement. [Touch evidence](KEYBOARD_TOUCH_INPUT.md)
defines the ephemeral capture contract. Implementation owners are
`KeyboardLearningSession`, `PersonalTypingModel`, `KeyboardLearningStore` and
`KeyboardDiagnostics` under `TyprShared/FullKeyboard/`; the app reads summaries
through `KeyboardDiagnosticsModel` and displays `KeyboardDiagnosticsView` /
`KeyboardTouchModelView`.

## Controls and Full Access

**Settings → Keyboard → Full keyboard → Typing assistance** exposes
**Learn from my typing** (default **on**) and **Typing diagnostics**. These remain
available with Autocorrect off, but are hidden when Full keyboard is off.
The switch is `TyprSettings.personalLearning`, App Group defaults key
`keyboard.personalLearning`, not a layout or hit-target switch.

- **On:** trusted events can update touch aggregates and word counts; frozen
  personal calibration and bounded word bonuses can influence spatial scores.
- **Off:** no new touch labels or word counts, no personal calibration/count priors
  or personal-only candidate scan. Previously stored aggregates are retained,
  not erased. Explicit keeps and rejected-correction protections still work and
  can be stored; diagnostics counting remains independent. Off does not mean
  “no keyboard writes.” A switch change ends pending feedback/undo association.
- Autocorrect off stops the Space decision transaction and spatial decoder;
  manual suggestion feedback (including explicit keep) can still be recorded.

Persistence is constructed only by the device keyboard with actual
`UIInputViewController.hasFullAccess`; permission is rechecked before every save.
Without it, or after a store failure/revocation, learning and counters stay in
RAM for that keyboard session. The session does not silently start a private
extension store or upload anything. App-hosted keyboards, previews and simulator
keyboards use RAM-only sessions. A session that stopped persistence needs a new
persistent session to resume disk saves.

The app **cannot query current keyboard Full Access**. Its own App Group access
or a saved snapshot proves neither current permission nor active learning. No
snapshot says access is off **or** nothing has been saved yet; unreadable storage
or a snapshot older than 24 hours gets last-saved/stale wording. RAM-only session
data cannot be displayed by the app dashboard.

## Trusted signals

At Space/Typr-key boundary, one pending feedback transaction may retain the
original literal, final text, bounded taps/layout and expected inserted suffix
in RAM. It must still belong to the same feedback epoch. Nothing queues a
history of pending words. Automatic output alone is never a trusted label.

| Event | Touch labels | Word/protection effect |
| --- | --- | --- |
| Automatic replacement, with no explicit feedback | None, even if the user moves on | Decision counter only; no count for automatic output |
| Unchanged literal, valid in an enabled dictionary or already kept, with complete aligned evidence | Identity labels after the next letter or another boundary confirms the word plus separator is still intact immediately before the cursor | +1 trusted literal count; no novel-word promotion from silence |
| Explicit keep (quoted literal chip) | Identity labels if evidence matches the literal | Protect literal immediately and +1 count |
| Immediate undo of automatic replacement | Original literal's identity labels only if pending literal/inserted suffix/epoch/evidence still match | Keep original and remember typed→replacement rejection; no word-count increment |
| Manual alternative pick (spatial or spelling) | Only unambiguous tap↔selected-letter pairs from the text aligner; model rejects samples beyond 1 pitch | +1 count for chosen word |
| Manual prefix completion pick | None, including the prefix taps | +1 count for completion |
| Deletion/word deletion, external text change, selection move, dictation/paste, popup/slide, layout change, cancellation, dismissal, overflow or lost association | Discard affected current/pending evidence; no label inferred from the edit itself | No trusted word event from the invalidated transaction |

Single-character backspace is a tracking exception: if pre/post tokens match,
the last sample is removed and the remaining current-word evidence can survive.
It cancels earlier pending feedback; it does not relabel erased taps. A retyped,
fully aligned word can subsequently qualify as a new trusted literal in the
current implementation. Whole-word deletion and unalignable edits clear evidence.

The manual-pick aligner accepts at most one text edit, retaining only mappings
shared by all minimal alignments. Ambiguous repeated-letter regions and the
swapped pair of a transposition are dropped; unaffected pairs may survive.
Candidate search alignment is **not** itself proof of independent label alignment.
Completions, inferred missing letters and stray taps never invent labels.

Before updating, the model requires a supported text-field letter layout and
lowercase intended key, finite coordinates and valid pitch, and Euclidean
normalized distance ≤1.0 from the intended key's **static** center. Captured
layout/context association is enforced by the tracker/integration. Current
letter keys are a–z; popup umlauts/ß have no fabricated centers.

## What is stored and bounded

Touch evidence for the current word and its one pending-feedback transaction
stays **RAM-only**. Only aggregated per-key touch statistics are serialized;
there is no sample reservoir, point sequence, field text, ordered word stream,
context/bigram/trigram history, host-app history, transcript or audio in these
learning/diagnostic files. The personal lexicon **does contain word strings**
and rejected word pairs: it is sensitive personal data, not anonymized data.

| Stored learning state | Bound and retention |
| --- | --- |
| Layout signatures | At most 4; orientation, width rounded to nearest 8 pt, suggestion strip and globe; least recently updated layout evicted |
| Per-key touch statistics | Up to 26 keys/layout: capped effective count, mean x/y offset and diagonal variance in pitch units; layout last-update time, no raw points |
| Kept words | Separate cap of 2,000; normalized lowercase NFC, 2–32 letters, ≤256 UTF-8 bytes; last-kept timestamp; oldest evicted |
| Trusted word counts | Separate cap of 2,000; same normalization/length rules, count saturates at 10,000, last-update timestamp; lowest count then oldest evicted |
| Rejected typed→replacement pairs | At most 512 unique normalized pairs, FIFO; repeated rejection does not refresh order |
| Learning label counters | Accepted by source (`literalValid`, `keep`, `undo`, `manualPick`), rejected by reason; saturate at Int32.max |
| Diagnostics | Fixed known counters, since/updated dates and two seven-bucket latency histograms; each count saturates at Int32.max |

Keeps and counts are independent collections and can overlap. The union of kept
words and count≥2 words can exceed the decoder's 2,000-entry scan limit. This
check runs before corpus filtering and conservatively makes a search incomplete,
even if most entries are in the bundled dictionaries. Word strings are not
folded from ß to ss or umlauts
to ASCII. Counts/dates are per retained type, not a chronology of word uses.
No time-based expiry runs: data remains until reset, bounded eviction or invalid
state discard. Updates continue adapting statistics; effective count is not a
lifetime tap count.

Calibration starts per key at **20** trusted labels. Effective count caps at
256; update weight is `max(1/n, 1/64)`. Mean/variance shrink by `n/(n+20)` toward
zero offset and static variance `.35²`. Inference offsets clamp independently
to ±.25 pitch; sigma clamps to .22–.50. The word bonus is
`min(1.0, .25 × log2(1 + count))` log units. These bounds limit influence; they
are not evidence of calibration quality or improved typing.

## Files, saves and reset

The existing App Group (`group.dev.rudek.typr`) contains:

- `<AppGroup>/Typr/Keyboard/learning-v1.json` — at most **256 KiB** encoded.
- `<AppGroup>/Typr/Keyboard/diagnostics-v1.json` — at most **64 KiB** encoded.
- `learning.lock` — coordination only, not a data archive.

Each JSON envelope has a reset epoch and schema-versioned value. Only the
keyboard writes learning/diagnostic snapshots; the app reads summaries and
requests resets. Writes are atomic **per file**, protected with
`completeUntilFirstUserAuthentication`, excluded from backup, directory mode
0700 and file mode 0600. One lock covers save/reset operations, using three
nonblocking `flock` attempts with 5 ms pauses. This is not a transactional commit
of both files on I/O failure and does not merge simultaneous controllers' deltas:
same-epoch controller saves are last-writer-wins.

Saves debounce until at least **10 seconds after the last change**, and flush on
keyboard disappearance, remount and memory warning. Continuous typing may defer
an idle save; termination can lose unsaved RAM updates. Before load/decode, reads
check regular/non-symlink files and byte limits. Loading validates epoch, schema,
finite/range values and collection limits. Wrong epoch means empty; invalid data
is discarded and counted, without raw-data logs or quarantine copies. A later
save replaces invalid data. Lock/read/write failure falls back to RAM-only.
To meet the byte ceiling, saving can trim old dated lexicon entries, then rejected
pairs; this trims the **saved snapshot**, not the current bounded RAM model.

Successful writes and resets post
`dev.rudek.typr.keyboard.learning-changed`. The dashboard reloads saved summaries
on appearance, notification, foreground and pull-to-refresh, not every tap.

**Typing diagnostics → Reset learning** clears calibration, keeps, word counts,
rejected pairs and learning-source/rejection counters. Statistics remain.
**Reset statistics** clears decision/feedback/store counters and latency buckets,
starting a new `since` period; learning remains. Each has a destructive confirmation.
The app bumps `keyboard.learning.resetEpoch` or
`keyboard.diagnostics.resetEpoch` and deletes the corresponding file under the
same lock. Epoch mismatch makes an old file unusable even if deletion fails.
The keyboard compares epochs on settings/appearance refresh and before saving,
clears/reloads the affected RAM domain and discards pending feedback/undo; a
learning reset also ends session keeps. No stale-epoch save may restore reset data.
Reset errors are shown with a retry message. Resets are not a secure-erasure claim.

The obsolete `keyboard.learnedWords` defaults key is deleted when a learning
session finds it, **without migration** (owner-approved). One explicit keep or
undo now protects the literal immediately, rather than the old two-keeps-in-a-
session threshold. Turning learning off does not revert that protection threshold.
The dictation-log archive and its separate retention/reset rules are unchanged.

## Diagnostic definitions and limits

| Dashboard measure | What it actually counts |
| --- | --- |
| Words checked | Eligible prose-token Space/Typr-key transactions with Autocorrect on, text field and host autocorrection allowed; not every word typed, Return, or every keypress |
| Complete touch evidence, n of m | Tracker evidence present at those boundaries / words checked; association coverage, not decoder success or quality |
| Missing evidence | When evidence is absent: length outside 3–32 first, unsupported non-a–z input next, otherwise absent/invalidated taps; no detailed gesture attribution |
| Decision paths | One per recorded boundary: spatial same-length, spatial letter-edit, spelling fallback, deterministic rule/text replacement, or unchanged |
| Refusals | Valid literal, protection, ambiguity, incomplete search, missing resource, failed validation, below margin, edit requiring invalid literal; not extra boundaries or a disjoint partition of unchanged words |
| Observed undo share | Linked immediate undos / recorded automatic replacements in the statistics period, displayed with numerator/denominator; spatial undo combines same-length/edit paths |
| Keep / alternative / completion picks | Explicit suggestion events, not inferred approval; selecting a repeated center literal without a change is not an alternative |
| Word decisions latency | Monotonic time inside the boundary decision/recording path; a reused cached decode need not run again |
| Suggestions latency / suggestion searches | Actual uncached spatial decode calls triggered by suggestions, including lazy resource loading inside that call; not all keystrokes, strip rendering, host callbacks or end-to-end input latency |
| Learning events | Words counted, keeps and rejections during the statistics period; not unique retained words/pairs |
| Trusted/rejected labels | Model's source/reason counters since learning reset, separate from statistics reset; reasons include outlier, nonfinite position, unknown key, layout mismatch and ambiguous alignment |
| Save failures / invalid files discarded | Observed store failures / invalid payloads rejected; failures may remain only in RAM and be absent from the app snapshot |

Evidence completeness is a tracker test: evidence can exist for a short or long
word even when the decoder's 3–32 gate rejects it. Likewise not every invalidated
gesture yields a rejected-label counter: most are discarded before learning.
The `learningOff` rejection category exists, but the session skips learning calls
while off, so it is not a count of all taps that were not learned. Likewise the
edit-requires-invalid-literal refusal exists in the decoder API, but the current
engine protects valid literals before calling that decision; those refusals
normally appear as valid-literal/protection instead.

Both latency histograms use milliseconds **<1, 1–2, 2–5, 5–10, 10–20, 20–50,
≥50**. They are counts, not WPM, percentiles, complete input latency or a benchmark
comparison. Simulator/Linux numbers do not predict iPhone speed. Cold resource
loading can appear in an uncached decode, while unrelated startup work is outside
these timers.

The touch map reconstructs bucket-width geometry, draws shrunk/clamped model
centers and one-sigma ellipses, and lists per-key effective counts accessibly.
Keys below 20 are marked uncalibrated; estimates may still be displayed but are
not used for inference. It displays **model parameters, not raw taps, moved hit
targets, measured hit probability, accuracy or improvement**.

No undo does not mean a correction was right. Many repairs are not linked undo,
and some mistakes go unnoticed. Counts are not precision, recall or error rate;
model movement is not benefit. Synthetic decoder evaluation and outstanding
Apple CI/owner iPhone checks are listed in the
[correction-path reference](KEYBOARD_SPATIAL_DECODER.md#required-owner-iphone-checks).
Do not export or commit personal word collections, tap data or private snapshots.
