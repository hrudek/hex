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
| Unchanged literal, valid in an enabled dictionary or already kept, with complete aligned evidence | Identity labels only when the next word's first unambiguous letter is inserted and the previous word plus separator is still intact; second Space, double-space-period, Return and punctuation do not teach | +1 trusted literal count; no novel-word promotion from silence |
| Explicit keep (quoted literal chip) | Identity labels if evidence matches the literal and has no deletion/retyping | Protect literal immediately; +1 count only if not deletion/retyping |
| Immediate undo of automatic replacement | Original literal's identity labels only if pending literal/inserted suffix/epoch/evidence still match | Suppress original for this session and persist typed→replacement rejection; **no permanent keep and no word-count increment** |
| Manual alternative pick (spatial or spelling) | Only unambiguous tap↔selected-letter pairs from the text aligner; model rejects samples beyond 1 pitch; no labels after deletion/retyping | +1 count for chosen word, unless deletion/retyping |
| Manual strict prefix extension pick, from any source (including spatial/spelling) | None, including the prefix taps | +1 count for completion, unless deletion/retyping |
| Deletion/word deletion, external text change, selection move, dictation/paste, popup/slide, layout change, cancellation, dismissal, overflow or lost association | Discard affected current/pending evidence; no label inferred from the edit itself | No trusted word event from the invalidated transaction |

Single-character backspace can preserve aligned remaining samples for **decoding**,
but any backspace inside a word disqualifies that entire word from touch labels
and word counts, including after retyping/reconstruction. It cancels earlier pending
feedback and never relabels erased taps. The disqualification lasts until a new
word boundary. Whole-word deletion and unalignable edits clear evidence. Explicit
keep protection and rejected-pair protection are independent of learning trust.

The manual-pick aligner accepts at most one text edit, retaining only mappings
shared by all minimal alignments. Ambiguous repeated-letter regions and the
swapped pair of a transposition are dropped; unaffected pairs may survive.
Candidate search alignment is **not** itself proof of independent label alignment.
Completions, inferred missing letters and stray taps never invent labels.

Before updating, the model requires a supported text-field letter layout and
lowercase intended key, finite coordinates and valid pitch, and Euclidean
normalized distance ≤1.0 from the intended key's **static** center. Captured
layout/context association is enforced by the tracker/integration. Current
letter keys are a–z; popup umlauts/ß have no fabricated centers. Inference now shares
a/o/u/s density and calibration with ä/ö/ü/ß, respectively; this creates no new
stored key or touch-label source. Prefix traversal keeps no history or persistent
cache. Corpus and noisy-prefix completions are flagged at retrieval (including an
exhausted-tap suffix from the edit decoder), supply a word count on explicit pick
and never supply touch labels, even for the observed prefix. Valid homographs keep
their existing automatic protection; deterministic `fuer → für` rules remain.

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
| Kept words and trusted word counts | **One combined bound: kept ∪ counted ≤2,000 words**; normalized lowercase NFC, 2–32 letters, ≤256 UTF-8 bytes; keeps have priority. Evict unkept counts by lowest count then oldest update, then oldest keeps (with their counts); spelling breaks timestamp ties. Keeps store last-kept time; counts saturate at 10,000 and store last-update time |
| Rejected typed→replacement pairs | At most 512 unique normalized pairs, FIFO; repeated rejection does not refresh order |
| Diagnostics (separate statistics epoch) | Fixed known counters, accepted labels by source (`literalValid`, `keep`, `undo`, `manualPick`), rejected labels by reason, since/updated dates and two seven-bucket latency histograms; each count saturates at Int32.max |

Keeps and counts can overlap, but loading validates their **union**, not just each
collection. Any valid model fits the decoder's full personal scan; capacity alone
never makes its search incomplete. Word strings are not folded from ß to ss or
umlauts to ASCII. Counts/dates are per retained type, not a chronology of word uses.
No time-based expiry runs: data remains until reset, bounded eviction or invalid
state discard. Updates continue adapting statistics; effective count is not a
lifetime tap count.

Calibration starts per key at **20** trusted labels. Effective count caps at
256; update weight is `max(1/n, 1/64)`. Mean/variance shrink by `n/(n+20)` toward
zero offset and static variance `.35²`. Inference offsets clamp independently
to ±.25 pitch; sigma clamps to .22–.50. The word bonus is
`min(1.0, .25 × log2(1 + count))` log units. These bounds limit influence; they
are not evidence of calibration quality or improved typing.

## Suggestion snapshot isolation

The [suggestion worker](KEYBOARD_SPATIAL_DECODER.md#suggestion-worker-and-boundary-authority)
receives immutable Sendable calibration/personal-prior values. All live learning,
protection/rejection mutations, diagnostics and pending feedback stay on MainActor;
worker output alone never teaches. Results and chips must match learning generation
**and** feedback/reset epoch, including a statistics-only reset. Switching learning
off or deleting/resetting saved data invalidates older results rather than letting
their ranking/protection state cross that change. If acceptance itself observes a new
learning state, it refuses the old chip without editing/learning and refreshes once
so the next tap uses live ownership. The existing settings poll also detects stale
published ownership after a deferred load, reset or resource installation, even if
an earlier sync consumed the transition. A compatible completed decode is reused on
unchanged refreshes without another search or another suggestion-search counter.

At most one running job and one replaceable latest request can retain bounded
current-word evidence/context in RAM; no worker field is Codable or written.
Context is a whole-character suffix capped at 256 characters / 2,048 UTF-8 bytes,
token at 64 characters / 256 bytes, alongside existing tap/personal bounds. A large
Unicode prefix does not remove the current word's literal chip. There is no new file,
permission, setting, ordered context history or data collection.
Suggestion-search diagnostics record accepted uncached worker decode duration
on MainActor; queue wait, lazy snapshot preparation, checker finish and rendering
are excluded, so the histogram is still not end-to-end keystroke latency.

## Files, saves and reset

The existing App Group (`group.dev.rudek.typr`) contains:

- `<AppGroup>/Typr/Keyboard/learning-v1.json` — at most **256 KiB** encoded.
- `<AppGroup>/Typr/Keyboard/diagnostics-v1.json` — at most **64 KiB** encoded.
- `learning.lock` — coordination only, not a data archive.

Each JSON envelope has a reset epoch and schema-versioned value. Only the
keyboard writes learning/diagnostic snapshots; the app reads summaries,
requests resets and explicitly deletes individual saved lexicon entries. Writes are atomic **per file**, protected with
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
save replaces invalid data. Before saving, invalid key aggregates are dropped from
RAM and counted once as a save failure; an unrecoverable validation failure stops
persistence instead of failing on every flush. Lock/read failure before the first
successful load temporarily uses RAM-only and retries on settings/appearance refresh
while Full Access is allowed. A successful retry installs the authoritative saved
snapshot, discarding provisional RAM learning/feedback rather than overwriting saved
protections; a deferred-load episode counts once. Write failure stays RAM-only for
the session. To meet the byte ceiling, saving can trim counts before keeps (oldest within each
collection), then rejected pairs; this trims the **saved snapshot**, not the current bounded RAM model.

Successful writes and resets post
`dev.rudek.typr.keyboard.learning-changed`. The dashboard reloads saved summaries
on appearance, notification, foreground and pull-to-refresh, not every tap.

**Typing diagnostics → Reset learning** clears calibration, keeps, word counts,
and rejected pairs. Statistics, including accepted/rejected label totals, remain.
**Reset statistics** clears decision/feedback/store and learning-event counters
(including accepted-by-source/rejected-by-reason totals) and latency buckets,
starting a new `since` period; learning remains. Each has a destructive confirmation.
The app bumps `keyboard.learning.resetEpoch` or
`keyboard.diagnostics.resetEpoch` and deletes the corresponding file under the
same lock. Epoch mismatch makes an old file unusable even if deletion fails.
The keyboard compares epochs on settings/appearance refresh and before saving,
clears/reloads the affected RAM domain and discards pending feedback/undo; a
learning reset also ends session keeps. No stale-epoch save may restore reset data.
Reset errors are shown with a retry message. Resets are not a secure-erasure claim.

The obsolete `keyboard.learnedWords` defaults key is deleted when a learning
session finds it, **without migration** (owner-approved). One explicit keep
chip now permanently protects the literal immediately, rather than the old
two-keeps-in-a-session threshold. Undo only suppresses for the session and records
a persistent rejected pair, never a permanent keep. Rejected forms allow letters
and straight/typographic apostrophes (2–32 characters), so undoing `dont → don't`
protects that pair after reload. Keeps and word counts remain letter-only. Undo of
an iOS text replacement containing spaces, digits or other punctuation suppresses
the shortcut for this session only; it does not persist a rejected pair or keep.
Both protections work while learning is off, without teaching labels/counts.
The dictation-log archive and its separate retention/reset rules are unchanged.

Reset learning and Reset statistics have red labels as well as destructive confirmation
dialogs; their independent reset behavior is unchanged.

## Manage learned words

**Keyboard → Manage learned words**, directly below Typing diagnostics and also linked
inside diagnostics, loads saved kept words, rejected `typed → replacement` pairs and
frequent-word counts only after an explicit tap. The search field filters all three
categories by partial word, ignoring case and diacritics, and searches both sides of
rejected corrections. An empty search shows everything; no matches get an explicit
message. Deletion while searching targets only the selected visible entry.
Swipe or Edit deletes one entry; keeps and counts are separate entries even when
they share a word. No context, typed history, raw taps or per-word dates are shown.
The dashboard and exports do not include this list. Without saved data the page
explains that Full Access may be off or nothing has been saved; the app cannot
inspect the keyboard's current permission or RAM-only learning.

Each deletion rereads the authoritative file under `learning.lock`, removes only
the selected entry, atomically writes the remaining learning with a new learning
epoch, publishes that epoch and posts the existing Darwin notification. A running
keyboard reloads on notification/refresh; a stale writer is refused under the same
lock before it can restore deleted data. Installing the edited snapshot deliberately
discards unsaved RAM learning and pending feedback/session suppression; saved touch
calibration, other words/pairs and statistics stay. Errors are shown for retry.
As with resets, this is not secure erasure. File write and defaults publication are
not a crash-atomic transaction: termination between them can invalidate the learning
snapshot (fail closed), rather than restore a deleted word.

Immediately pressing Backspace after a keep removes a newly added keep and restores
the literal without its separator. A keep that already existed is not removed.
Immediately picking the original replacement after undoing an automatic correction
removes only the newly added rejected pair and its session suppression. New typing,
another feedback action, context changes or an epoch change end this association.
These are protection reversals, not rollback of already aggregated touch labels,
counts or diagnostic events. Older protection is never erased by an immediate revert.

The optional `settings-keyboard-learned-words` snapshot uses synthetic in-memory
fixture words only and never reads or edits the saved personal collection.

## Diagnostic definitions and limits

| Dashboard measure | What it actually counts |
| --- | --- |
| Words checked | Eligible prose-token Space/Typr-key transactions with Autocorrect on, text field and host autocorrection allowed; not every word typed, Return, or every keypress |
| Complete touch evidence, n of m | Evidence usable by the decoder: 3–32 aligned supported letters at those boundaries / words checked; coverage, not decoder success or quality |
| Missing evidence | Classify length outside 3–32 first even if tracker evidence exists, unsupported non-a–z input next, otherwise absent/invalidated taps; no detailed gesture attribution |
| Decision paths | One per recorded boundary: spatial same-length, spatial letter-edit, spelling fallback, deterministic rule/text replacement, or unchanged |
| Paths that declined to replace | Valid literal, protection, ambiguity, incomplete search, missing resource, word data still loading, failed validation, below margin; a later path may still replace. Not extra boundaries or a disjoint partition of unchanged words |
| Observed undo share | Linked immediate undos / recorded automatic replacements in the statistics period, displayed with numerator/denominator; spatial undo combines same-length/edit paths |
| Keep / alternative / completion picks | Explicit suggestion events, not inferred approval; selecting a repeated center literal without a change is not an alternative |
| Word decisions latency | Monotonic time inside the boundary decision/recording path; a reused cached decode need not run again |
| Suggestions latency / suggestion searches | Uncached spatial calls returning a search result, triggered by suggestions; excludes evidence/resource refusals, word data still loading and detached word-data preparation; not all keystrokes, strip rendering, host callbacks or end-to-end input latency |
| Learning events | Words counted, keeps and rejections during the statistics period; not unique retained words/pairs |
| Trusted/rejected labels | Diagnostics-owned source/reason counters since statistics reset; learning reset preserves them; reasons include outlier, nonfinite position, unknown key, layout mismatch and ambiguous alignment |
| Save failures or repairs / invalid files discarded / deferred learning loads | Observed save failures (including repaired invalid key statistics), invalid payloads rejected, and failed initial-load episodes counted once despite retries; failures may remain only in RAM and be absent from the app snapshot |

Not every invalidated gesture yields a rejected-label counter: most are discarded
before learning. `learningOff` counts labels actually submitted by explicit
feedback while off, not all taps that were not learned. The decoder API retains
its edit-requires-invalid-literal refusal, but the engine already guards valid
literals, so no separate unreachable dashboard counter is kept. Pending resource
decodes report unavailable(resource) and permit spelling fallback; boundaries
count this as `resourceLoading` (“Word data still loading”), separately from a
missing/invalid resource.

Both latency histograms use milliseconds **<1, 1–2, 2–5, 5–10, 10–20, 20–50,
≥50**. They are counts, not WPM, percentiles, complete input latency or a benchmark
comparison. Simulator/Linux numbers do not predict iPhone speed. TSW1 mapping,
validation and subtree-index construction run detached from the main actor after
keyboard appearance with Autocorrect on; their cold cost is outside these timers.

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
