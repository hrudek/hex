# Personal typing learning and diagnostics

## Neural measurement spike (R2-10)

[Evaluation and reproduction](KEYBOARD_NEURAL_EVALUATION.md): the small bilingual
int8 next-word model fails the same-set DE/EN/mixed quality gate. Evaluation-only
tooling/tests are retained; no neural weights, runtime ranking, automatic policy,
new personal data or settings ship. No changes to privacy copy, Full Access,
App Group writes, deletion/reset or dictation-log retention are needed: this
explicit offline experiment uses only public corpus samples and a synthetic
train-only profile, never the user's contacts/history/log. The keyboard remains
network/microphone/speech-model free. iPhone footprint/latency are unverified.

## Larger corpus context packs (R2-9)

Bundled DE/EN predictions now add bounded Leipzig news, Wikipedia and OPUS subtitle
samples to Common Voice/Tatoeba. [SOURCE](tools/keyboard_context/SOURCE), WordData
ATTRIBUTION and third-party notices state licenses/provenance and unresolved
rights questions. This is static public-corpus data, not learning from users.
No personal bytes/schema/imports, reset/deletion semantics, Full Access gating,
privacy permission, network, microphone or dictation behavior changes. Personal
contexts stay deletable/resettable. Static corpus data remains active with Learn
from my typing off. No new switch or automatic-policy authority.

TBG1 and the combined 1 MiB loader cap remain unchanged: 8,000 words plus BOS per
language, K=3/min=10. Packs 662,793→770,630 bytes (+107,837); load validates 16,002
word records / 35,405 edges; 32,000-byte derived index, 802,630 mapped+index bytes
(not measured RSS). No corpus trigrams built: no measured gain justifies bytes;
personal R2-2 trigrams/backoff remain unchanged.

Only dev partitions selected the best balanced recall gain per combined byte
from 30 candidates. Identical CC0 64-sentence recall@1/@3: DE 6.47/14.06→7.59/14.51%,
EN 10.37/17.74→11.29/18.43%; mixed 417-pair recall@3 15.11→15.35% and wrong-language
slot rate 1.92→1.44%. Full CV and all three full new-source domain tests improve,
but full Tatoeba recall@3 falls DE 19.05→18.40%, EN 28.12→27.59%. The new small
alternating-language subtitle fixture also falls 15.88→15.44% recall@3 (while
wrong-language slots fall 1.27→1.12%); news/wiki alternating recall improves.
These are explicit domain tradeoffs, not an across-the-board gain. Same injected-vocabulary noisy correction retains
DE 684/722 @1, 688/722 @3; EN 669/686 both; mixed 713/746 @1, 717/746 @3, with
zero unwanted autos and zero changed automatic decisions.

Linux proves split/counts/formulas and injected-checker controls, not legal
clearance or iPhone behavior. iPhone checks: cold/warm offline DE/EN/mixed
predictions and language toggles; extension memory/load; Apple dictionaries;
manual picks/undo and boundary chips; learning/Full Access on/off; deletion/reset
of personal contexts; archived resources and attribution links. Subtitle/news
provenance and App Store DRM/share-alike remain owner release-review questions.


Typr's full keyboard can retain bounded personal touch statistics, word choices
and text-free diagnostic counters on this iPhone. This owner-approved storage
replaces the old kept-word store; it is **not RAM-only**. It is not a typed-text
history, raw tap archive or accuracy measurement. It now includes a small personal
next-word model: sensitive aggregate counts of which word followed which.
The keyboard never accesses the microphone, speech model or network.

R2-5 [orthography suggestions](KEYBOARD_SPATIAL_DECODER.md#germanenglish-orthography-r2-5)
reuse the bounded RAM-only sentence posterior and local system dictionaries.
They add no recording, Contacts/history/log reads, stored words, posterior
history or persistent bytes. Existing imported-name protection, keeps and
contextual undo/rejection memory veto the new candidates too; their existing
deletion/reset and Full Access rules are unchanged. Choosing a chip follows
ordinary explicit acceptance accounting; inserting an apostrophe or changing
case invents no tap labels. Automatic noun capitalization is not enabled.

The separate [offline corpus context layer](KEYBOARD_SPATIAL_DECODER.md#offline-corpus-context-suggestions)
uses bundled public DE/EN statistics for after-space predictions and display-only
reranking. It reads at most a 256-character/2,048-byte field suffix in RAM,
recomputes a bounded sentence language posterior per request, and stores **no
posterior or history of its own**. With learning on, its weak language-usage prior
is derived from existing deletable trusted word counts and update dates (see below). The separately approved
[personal word-pair layer](#personal-next-word-pairs) adds bounded follower counts; no new switch.
Autocorrect and its selected languages govern it, independently of Learn from my
typing. Picking a next-word prediction has no aligned current-token evidence and
teaches no touch labels; its explicit word count and later context settlement follow the personal next-word rules. Ordinary typed-prefix completion picks
retain the existing trusted-count/no-label rules. Full Access-gated personal
persistence, resets, keeps and rejected pairs below are unchanged.

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
  personal calibration and bounded word bonuses can influence spatial scores, and
  [personal completion ranking](#personal-completion-ranking) can reorder completions.
  Independently settled adjacent words can update personal next-word pairs, used
  above the corpus for predictions and bounded display-only context ranking.
- **Off:** no new touch labels or word counts, no personal calibration/count priors,
  personal word-pair updates/influence, personal-only candidate scan or personal completion ranking (completions keep
  exactly today's system/corpus order). Previously stored aggregates are retained,
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
| Immediate undo of automatic replacement | Original literal's identity labels only if pending literal/inserted suffix/epoch/evidence still match | Persist a context-aware typed→replacement veto with deterministic decay (below); **no immediate permanent keep or word-count increment**. Unsupported phrase/punctuation pairs retain session-only suppression |
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
stays **RAM-only**. Only slow aggregated per-key and all-key touch statistics are serialized;
there is no sample reservoir, point sequence, field text, ordered word stream,
sentence archive, host-app history, transcript or audio in these
learning/diagnostic files. The personal lexicon **does contain word strings**
and rejected word pairs, plus followers after **one or two words** (aggregate
bigrams/trigrams, no sentence archive or app/host information): it is sensitive
personal data, not anonymized data. These associations can reveal short phrases.
Explicitly accepted next-word and completion chips also supply word evidence.

| Stored learning state | Bound and retention |
| --- | --- |
| Layout signatures | At most 4; orientation, width rounded to nearest 8 pt, suggestion strip and globe; least recently updated layout evicted |
| Slow touch statistics | Up to 26 keys plus one global aggregate/layout: capped effective count, mean x/y offset and full xx/xy/yy covariance in pitch units; layout last-update time, no raw points |
| Fast aim (never stored) | One active layout, two shared affine ridge regressions (~40/~8 trusted-label decay) plus three predictive weights; 24 sufficient sums, no per-key fast banks or point reservoir |
| Kept words and trusted word counts | **One combined bound: kept ∪ counted ≤2,000 words**; normalized lowercase NFC, 2–32 letters, ≤256 UTF-8 bytes; keeps have priority. Evict unkept counts by lowest count then oldest update, then oldest keeps (with their counts); spelling breaks timestamp ties. Keeps store last-kept time; counts saturate at 10,000 and store last-update time |
| Next-word contexts | ≤512 combined bigram/trigram edge types, ≤8 followers/context, count ≤255; normalized lowercase NFC, 1–32 letters / ≤128 UTF-8 bytes per word, ä/ö/ü/ß remain distinct; ≤64 KiB conservative encoded byte bound inside the unchanged whole-store limit. All counts halve every 256 valid row updates (a word with two predecessors updates two rows); zeros disappear; weakest counts then lexically greatest context/follower are evicted deterministically |
| Rejected typed→replacement pairs | At most 512 unique normalized pairs, FIFO; optional ≤2 predecessor words and remaining-event counters (global ≤64, context ≤256). Repeated undo refreshes horizons/context, not FIFO position. Migrated legacy pairs remain permanent until deletion |
| Diagnostics (separate statistics epoch) | Fixed known counters, accepted labels by source (`literalValid`, `keep`, `undo`, `manualPick`), rejected labels by reason, since/updated dates and two seven-bucket latency histograms; each count saturates at Int32.max |

Keeps and counts can overlap, but loading validates their **union**, not just each
collection. Any valid model fits the decoder's full personal scan; capacity alone
never makes its search incomplete. Word strings are not folded from ß to ss or
umlauts to ASCII. Counts/dates are per retained type, not a chronology of word uses.
No time-based expiry runs: data remains until reset, bounded eviction or invalid
state discard. Updates continue adapting statistics; effective count is not a
lifetime tap count.

### Undo, literal confirmation and acceptance (R2-3)

The learning value schema is **5** (same `learning-v1.json`, same App Group and
256 KiB whole-file cap). Schema 1–4 migrates without inventing observations;
old rejected pairs have no horizons/context and retain their permanent veto.
Older clients reject schema 5: downgrades can lose learning. There is no parallel
feedback store. Optional metadata extends the existing rejected-pair records;
pair identity/deletion remains normalized typed→replacement, not its counters.

A single ownership-validated undo blocks that pair in **every context for the
next 64 trusted word events**. Afterwards it blocks only its exact saved context
until **256 events**, then the record is removed and the correction may return.
Context is up to two immediately preceding normalized 2–32-letter words, read
from at most 96 preceding characters; punctuation/unsupported forms terminate it.
The longest available key is exact, not a fuzzy semantic or cross-sentence match.
With no meaningful context, only the 64-event global veto applies; metadata still
expires at 256. A new undo refreshes both horizons and replaces its context.
One pair retains one context, not an unbounded list. Full-store byte pressure may
evict records before their horizons, as with prior FIFO protections.

An event is an independently settled literal or an explicit accepted alternative,
completion or prediction that qualifies for a word count. Automatic output alone,
refresh/polling, undo itself, punctuation, deletion/retyping and attributed words
never advance this clock. With Learn from my typing off the clock and implicit
literal confirmation pause; explicit undo/keep still protect. There is **no
calendar expiry**. Each word-count update ages ≤512 records in one pass; an
independent literal confirmation can inspect another ≤512. Existing lookup and
snapshot/word-limit bounds remain. These are operation counts, not wall-clock or RSS
claims. Persistence still requires actual Full Access before every write.

A **fresh independently typed** original spelling after undo may now settle even
if absent from the dictionary. With intact geometric evidence, its next word's
first letter confirms it as a keep (and one word count). The restored undo word
itself cannot confirm it; deletion/retyping, stale fields, attributed letters and
learning-off cannot either. Keeps retain the ordinary 2,000-word budget and are
deletable; they outlive rejection decay until deletion/reset/eviction.

Repeated explicit acceptance reuses the existing capped counts (≤10,000), spatial
bonus `min(1, .25 × log2(1+count))` and personal completion ranking rather than
adding another weight table. Eight `hello` completion picks in the injected
`he → help, hello` fixture move `hello` from rank 2 to rank 1, with zero touch
labels. Merely continuing after automatic corrections remains **not** acceptance:
there is no silent self-training. No automatic thresholds, dictionary guards or
split/join policy are relaxed. This is a measured synthetic ranking result, not a
human accuracy claim.

Manage learned words displays/searches the predecessor key with its rejected pair;
deleting that row removes the full record. Deleting a kept/counted/context word
also removes rejected records naming it as original, replacement or predecessor.
Reset learning clears horizons and confirmed keeps too, with existing epoch races
and Full Access gating unchanged. These short associations are sensitive personal
data, not anonymous statistics; no raw sentences, hosts, taps, microphone or network
are added. Settings/management privacy copy discloses predecessor storage. Dictation
log data/import behavior is unchanged.

Regression/evaluation: `PersonalTypingRejectionTests`, `KeyboardLearningIntegrationTests`,
`KeyboardLearningStoreTests` and `KeyboardSuggestionPersonalRankingTests` cover migration,
horizon boundaries, same/different context, refresh, deletion/reset, byte/FIFO caps,
independent confirmation and bounded acceptance. Full before/after EVAL lines are
in the R2-3 research report. Observed Linux Swift 6.4.2 full harness: 416 tests,
406 passed, the one pre-existing backup-metadata failure, nine baseline skips
(before: 407 / 397 / one / nine). Held-out noisy strip recall@1/@3 was unchanged:
DE 684/722 and 688/722, EN 669/686 at both cutoffs, mixed 713/746 and 717/746;
0/1,077 unwanted automatic control changes before and after. One undo gave
0/1 same-context and 0/1 different-context immediate recurrences; event 64 allowed
1/1 different-context recurrence, event 256 allowed 1/1 same-context recurrence.
512 short rejection records encoded to 49,770 state bytes; maximal-Unicode input
at 512 records was trimmed by the existing writer to 422 records / 247,840 file
bytes (262,144-byte cap). Scratch build with the 100 ms long-expression warning
flag had no long-expression warnings. These are synthetic Linux results, not
iPhone accuracy, timing budgets or RSS measurements.

Linux cannot validate Apple UI compilation, protected
files/backup flags, actual Full Access transitions, host callback timing or real
checker behavior. On iPhone test undo and fresh retyping in two hosts, after-space
and punctuation/Typr boundaries, recreation/reload, 64/256-event sessions, off/on,
revocation, deletion/reset live refresh, context rows/search/accessibility and
rapid typing latency/extension peak memory.

### Slow covariance and fast aim

R2-8's [decoder-statistics evaluation](KEYBOARD_SPATIAL_DECODER.md#decoder-statistics-evaluation-r2-8)
retains Gaussian production scoring: a test-only Student-t/alignment-sum reranker
regresses noisy EN/mixed recall despite some outlier gains. It reads frozen
synthetic calibration only, never teaches from hypothetical readings and adds
no runtime data collection, persisted state, privacy-copy change or new reset
obligation. Existing Full Access, deletion, reset and independent alignment
rules below are unchanged; the keyboard still uses no microphone/model/network.

Slow effective counts cap at **256**; update weight is `max(1/n, 1/64)`.
The population update retains xx/xy/yy covariance. The shared physical spread pools
within-key covariances in sorted key order, weighted by effective count, plus **20**
`.20²` prior observations. Per-key covariance shrinks by `n/(n+20)` toward that
pool; slow centers shrink toward zero by the same factor. This is a bounded Gaussian
translation of iikb's hierarchical/multiple-memory ideas, **not** its NIW/Student-t
model or an explicit grip classifier.

Calibration starts after **20 pooled trusted labels**, including for unseen keys;
scarce keys borrow spread and a shared global center/shift. A migrated diagonal-only
model retains its per-key 20-label threshold until 20 new pooled labels exist.
`TouchAimDrift` replaces sparse per-key fast memories with one shared affine field:
`drift(u,v) = W × [1,u,v]`, where key positions are normalized to [-1,1] in the letter
plane. It can explain both translation and position-dependent reach/tilt without
waiting for 20 labels on every key. Two exponentially forgetting ridge regressions
have ~**40/~8** label memories and diagonal ridge penalties **[1,2,2]** toward no
drift. They learn residuals from the pre-update slow physical model. A stable
no-drift memory competes with them; prequential likelihood weights (scored **before**
learning) use **.02 fixed share**. Disagreeing means broaden the moment-matched
Gaussian. There is no discrete posture state, sensor, raw reservoir or per-key fast
bank. The affine field is Typr's transfer mechanism, not a copied upstream algorithm.
Only independent trusted labels advance any memory; ordinary automatic output does
not accelerate adaptation. Recovery is measured in **accepted trusted labels**, not
all physical taps; real alignment/feedback gates can make it substantially slower.

Physical covariance is tempered by **(.35/.20)² = 3.0625** before decoder use, so a
.20-pitch physical cloud has the original .35-pitch scoring width. Directly using
a mature narrow physical cloud with unchanged prior/margin weights was overconfident
in the synthetic controls. The physical prequential model has eigen-sigma bounds
.10–.50; the final frozen inference density retains the bounds below. Saved diagnostic
ellipses show shrunk slow statistics, not the live/tempered inference distribution.

Inference offsets clamp independently to **±.50 pitch**, enough to represent a
far-side thumb undershoot; drawn keycaps and the one-pitch trust gate do not move.
Marginal sigma stays
**.22–.50**, and xy is bounded so **both covariance eigenvalues** stay in
**[.22², .50²]**, hence determinant ≥ **.22⁴**. Densities include the determinant
normalizer. Calibration is an immutable value frozen for each decode; scoring never
updates it. The separately bounded [letter-gap attribution](KEYBOARD_TOUCH_INPUT.md#bounded-adaptive-letter-attribution)
uses the same frozen snapshot; all drawn-keycap taps remain literal.

Fast state/weights are never Codable and never enter saved summaries. They reset
with evidence discontinuities (field/host/layout/lifecycle invalidation, cancellation,
ambiguous gestures), a different active layout, learning toggle, model reload or reset.
Ordinary word boundaries and applied manual word choices clear current-word taps
but retain fast aggregate aim (including the manual choice's just-trained labels).
There is no raw recent-point reservoir, even in the diagnostic model.

Maximum numeric slow payload is **5,184 bytes** (4×27 statistics, Swift stride 48),
fast payload **320 bytes** (one `TouchAimDrift`, including SIMD padding) on the tested Linux target;
dictionary/string/allocator overhead, snapshots and encoding transients are extra,
not measured extension RSS. Stored byte ceilings and collection caps are unchanged.
The word bonus is
`min(1.0, .25 × log2(1 + count))` log units. These bounds limit influence; they
are not evidence of calibration quality or improved typing.

## Attribution and learning trust

Bounded adaptive letter-gap attribution follows Learn from my typing **and**
Autocorrect; off uses geometric insertion. Its same-row, gap-only, strict-density/
posterior gates are defined in [touch input](KEYBOARD_TOUCH_INPUT.md#bounded-adaptive-letter-attribution).
P8b requires four letters of known continuation, a 90% uniform novel-word floor,
consistent neighboring learned densities and a 1.5%-width boundary band. Backspace
vetoes attribution for the rest of the word, even with partial/missing evidence;
the RAM-only bit survives layout refresh and resets at a separator/field preparation.
It never adds training eligibility. No positional/retyping history is stored.
Geometric hits and attributed letters stay separate in RAM evidence. A word with
any automatic reattribution is disqualified from **all touch labels and word counts**,
even on a later keep/manual choice or unchanged-literal settlement, including a
partially observed prefix. They cannot become personal pair endpoints either. Explicit keep
and rejection protections still work. This prevents self-confirming covariance,
aim, counts or personal continuation priors. Other trusted-word rules are unchanged.

R2-7 deliberately retains this exclusion: wider/shorter-prefix experiments failed
the zero-false-change gate, and absence of undo is not independent intent evidence.
No soft-label trainer is shipped or claimed successful. A 16-trial fixture measures
zero new attributed labels/counts both after eight unchanged settlements and eight
backspace/retypes; independently trusted calibration still learns normally. See
[the measured widening decision](KEYBOARD_TOUCH_INPUT.md#r2-7-widening-evaluation-and-decision).

No new persisted text, raw taps, context history or schema. TSW1 continuation indexes
are immutable derived public-resource data; the personal index adds bounded prefix
sums to its existing snapshot. The map itself is RAM-only and ownership checked.
`Reattributed letter taps` counts actual changed insertions, not success, intention
or accuracy; it saturates and follows the existing Full Access-gated diagnostics
save/statistics-reset contract. A deliberate novel-name gap tap remains ambiguous;
all visual keycap taps are protected, but gap reattributions need physical-iPhone
acceptance. A 455-unique-OOV evaluation now measures harm, including precise,
Gaussian, shifted and deliberate gap probes: one harmed tap/word per 1,820 runs in
each language mode, below the stated synthetic bounds but not zero. The original
short `thrax` regression is protected. These development fixtures do not establish
human typing benefit; the stricter gates reduce in-vocabulary gain substantially.

## Personal names and terms

The app's **Personal names and terms** controls are source consent, both off until
the owner opts in. **Import contacts** asks iOS for Contacts access and reads only
given/family/nick names and companies (limited access means only selected contacts).
No phone numbers, addresses, contact IDs or contact relationships enter the file.
**Import dictation words** reads active Custom vocabulary spellings, not sounds-like
forms, plus final text from up to 50 entries in the app's existing recent log cache.
Only finished entries qualify: no raw ASR, rejected/late model answers, feedback
notes, expected text, audio or full archive walk. Opening an older log entry can
change that cache; this is not an exhaustive or durable dictation-word history.

The app rebuilds at launch/activation, Contacts changes/permission grant, custom
vocabulary changes and changes to the recent log cache. Enumeration runs off the
main actor, with cancellation checks; generations/source consent prevent stale
results from overwriting a reset. Contacts enumerate the accessible address book
without an input-count limit, but only the bounded top-K output is retained.
Imports are a separate dictionary, not typing counts/bigrams or a confidence
signal invented from inferred corrections; Learn from my typing does not disable
the imported literal protection.

### Query and storage bounds

`ProtectedPersonalLexicon` owns normalization, streaming build, validation,
serialization and binary queries. NFC/lowercase keys fold curly apostrophes to
ASCII, preserve accents/ß (no ae/ä or ss/ß conflation), split phrases/companies on
nonletter/nonapostrophe characters, reject one-letter and >64-UTF-8-byte tokens,
and deduplicate. There is no frequency ranking or source precedence. The smallest
**2,000** distinct keys in Swift's deterministic string ordering survive regardless
of input order. Numeric identifiers are not imported as whole literals; ordinary
identifier/URL protections remain in effect. Completions follow typed capitalization,
not original contact/product casing; no new automatic capitalization.

`Typr/Keyboard/personal-lexicon-v1.json` in the App Group contains only version 1
and sorted word keys: **256 KiB** hard encoded-file cap, **128,000 bytes** maximum
word payload (2,000 × 64), plus JSON/container overhead. The app writes atomically
with complete file protection and backup exclusion. No source IDs, sentences,
timestamps, frequencies or audio are stored here. A cap-sized 64-byte fixture is
134,023 encoded bytes. These are payload bounds, not Swift allocation/RSS claims.

The keyboard only reads, with real Full Access, on appearance/host activation.
No Contacts, microphone, speech or network API is added to the extension.
File metadata preflight rejects nonregular/symlink/oversized files; the read is
capped at 262,145 bytes even if metadata races. Missing, corrupt, noncanonical,
unknown-version, over-count or oversized files yield an empty import lexicon.
Load validates at most 2,000 entries after the file/count checks. Queries over
2,000 sorted keys need at most 11 binary comparisons, then at most four prefix
entries to return three strict completions. No list scan is added per key.

Exact imported literals veto *all* automatic changes, even deterministic
contraction/digraph rules and iOS shortcuts, while unlisted words retain existing
policy. They are valid learning literals under the existing independent
settlement/trusted-touch gates. Prefix completions are manual only. Split/join
chips are vetoed if any original token is imported; boundary automation remains
suggestion-only. Adaptive attribution protects an **exact completed imported word**
and each geometric **prefix-plus-letter** that can still spell an imported term.
R2-7 removes the blanket current-prefix veto: unrelated branches of a common
imported prefix can adapt under the unchanged #124 gates. Every intended imported
continuation stays literal, including contacts also valid in the corpus. The
keyboard does not inspect source identity, dictation history or system validity
on insertion. No inferred touch label is created and no new data is collected.
The same imported-word deletion/reset and Full Access rules apply; privacy copy
remains accurate because storage, import consent and data categories are unchanged.

### Deletion and device checks

**Delete imported words** removes the file and disables both sources. App **Reset
learning** does the same; statistics-only reset does not. Both prevent immediate
launch/defaults-triggered repopulation. Neither deletes Contacts, Custom vocabulary
nor the Dictation log: turn imports back on to rebuild from remaining sources.
Turning a source off, changing vocabulary or deleting log entries rebuilds the
shared list without that source (a token present in another source remains).
Existing typing counts/kept words are separate and use Manage learned words;
deleting the import list alone does not erase independently learned words.
The extension discards its old snapshot at its next appearance/activation, not via
a per-key file read. Existing iOS supplementary lexicon entries remain separate.

Linux tests exercise build/caps/order, JSON/file rejection, deletion/reset,
manual completions, exact automatic-rule/shortcut veto and integrated boundary and
geometrically-correct name/compound gap controls. UIKit/SwiftUI compilation,
Contacts grant/denial/limited access/revocation, actual app lifecycle notifications,
locked-file protection, backup flags, extension Full Access transitions and
memory/latency on an older iPhone still require device verification. Check rapid
reset while import/permission is in flight, deletion/re-enable, both languages and
mixed text in two hosts, manual completion casing and immediate undo.

## Personal completion ranking

Issue #101. With **Learn from my typing** on, prefix completions in the strip use the
same local personal snapshot as the spatial decoder:

- **Candidates kept:** Typr corpus prefix completions and `UITextChecker.completions`
  stay in the baseline list (corpus first, system list sorted by length then
  alphabetically, at most 64 considered for personal promotion). The separate public
  corpus context layer can then rerank the bounded union before choosing visible chips.
- **Personal words move up:** a candidate that is kept, or counted at least twice (the
  decoder's personal-word threshold), is placed ahead of the other completions. Order:
  higher count, then kept, then the original position; equal weights keep the system/
  corpus order. Personal ranking alone does not reorder unweighted candidates.
  Context gain may subsequently reorder both weighted and unweighted completions.
- **Missing personal words join:** kept or twice-counted words that strictly extend the
  typed prefix (2–31 letters, case- and NFC-insensitive; ä/ö/ü/ß are distinct letters)
  may be added after equally weighted baseline words. The store is case-folded, so a
  capital is restored only when the selected German dictionary (`tastatur → Tastatur`)
  or English dictionary confirms it; otherwise the typed prefix's case applies.
- **Unchanged:** text replacements, the automatic fix, spatial alternatives and
  Contacts/lexicon terms keep their slots and precedence; rejected pairs are not
  offered; personal chips are completions, so they are never highlighted for, or
  applied at, Space, punctuation or the Typr key. Automatic replacement is unaffected.
- **Learning:** a pick teaches the existing completion signal only: +1 word count,
  **no touch labels** (including the prefix taps). `Picked personal completion`
  additionally counts picks of a chip placed by personal ranking. It is text-free and
  does not prove the word would otherwise have been absent or that the order is better.

Bounds: `PersonalCompletionIndex` is built once per personal snapshot (that is, after a
word is counted, kept or forgotten, lazily on the next suggestion preparation) from the
decoder's prepared, sorted scan list of ≤2,000 words. A prefix lookup is two binary
searches plus at most eight pops, 17 O(log 2,000) range-maximum queries and nine
pending intervals; no keystroke scans all 2,000 words. The index stores no extra text
beyond the snapshot's words (payload below 192 KiB in tests; not RSS). The corpus and
personal lookups run on the suggestion worker; the main actor only calls the checker,
merges at most 72 baseline and 8 personal candidates and applies casing. Nothing new
is persisted by personal completion ranking itself; the separate word-pair layer
below provides personal next-word prediction. The separate corpus next-word/display ranker is independent of
Learn from my typing: **off removes all personal completion/count/calibration influence,
not public-corpus context gain**. Off with retained counts and off with empty counts
produce identical context-ranked completions (keeps/rejected protections remain
independently active). With no usable context, #115's exact old order and work budget
remain. In the deferred worker finish, at most eight promotions, eight trie results
and eight system completions join fewer than eight preceding alternatives (≤32 total);
contact, automatic, explicit-revert and literal slots remain pinned. All source
completion/personal-pick flags survive the display rerank, and no completion teaches taps.

`KeyboardSuggestionPersonalRankingTests` covers index order/ties/oracle, case,
German nouns, umlauts/ß/NFD, switch-off identity, contacts/rejections/automatic
replacement, pick learning and worker/synchronous equality. Observed Linux harness
(Swift 6.4.2 debug, synthetic user who often types every third public fixture word,
three-letter prefixes, corpus-membership checker without system completions):
those words reached the two alternative chips in **20→34 of 34** (DE), **23→25 of 25**
(EN) and **46→96 of 96** (mixed, with invented names) cases, off→on. Other fixture
words lost some slots: **41→37 of 56**, **49→47 of 51**, **76→73 of 102**. Automatic
replacement differences, automatic completions and highlighted personal chips were
**0**. With a full 2,000-word snapshot, the index build took **0.68 ms**, a lookup
averaged **0.014 ms** (max 0.026 ms) and strip assembly **0.13 ms** on versus **0.07 ms**
off, with a **90,904-byte** index payload. These are synthetic Linux numbers, not
iPhone latency, real typing benefit or Apple checker behavior. Latency measurements
remain EVAL diagnostics only; deterministic entry/result and byte bounds gate
regressions rather than noisy shared-runner timing. The same applies to aim
snapshot/trusted-label update timings; numeric/encoded byte limits remain asserted.
See [evaluation regression gates](KEYBOARD_SPATIAL_DECODER.md#evaluation-regression-gates).

## Sentence language posterior (R2-4)

DE/EN suggestions use a sentence-level running posterior rather than a separate
weight for each candidate word. Every request reconstructs it from completed words
in the existing ≤256-character / 2,048-byte RAM-only field suffix; the active token
is excluded. Only the last eight word-evidence values survive within a sentence.
Lexical evidence uses membership/frequency in the selected bundled context packs,
with additional cues for umlauts/ß, known English apostrophized words and known
German capitalized nouns mid-sentence. A capitalized unknown name or sentence-initial
word is not a noun cue. This is a bounded heuristic posterior, not a calibrated
probability of a human speaker's language. A completed proxy word is evidence for
ranking only, **not permission to learn** from pasted or automatically changed text.

Two consecutive contrary observations (the latest strong) discount old evidence immediately;
a single loan word does not force a switch. Explicit umlaut/contraction cues can
switch immediately. Sentence punctuation and newlines clear the eight observations
and start with a decayed prior (`.25 * previous log odds + .5 * personal prior`).
Repeated punctuation does not reset repeatedly. Non-prose barriers break word
adjacency, not sentence punctuation inside a URL. Edits retokenize rather than
consume twice; no sentence posterior crosses an unavailable field suffix.

There is no reliable host-app/field identity in the pure engine. With **Learn from
my typing** on, recent usage instead supplies a weak prior derived from the **32
most recently updated retained counted word types**, with lexical tie order,
per-type weight `min(count,4)` and four neutral pseudocounts; the weighted mean of
clipped corpus log ratios is capped at ±1 log odds. These are retained types, not
an ordered 32-event history. Old dates have no wall-clock expiry. This deliberately
reuses existing counts/dates: **zero new stored fields, files or bytes**, no app IDs,
no schema change, no transcript seeding. Keeps without counts contribute nothing.
The ≤2,000 counted types are sorted/classified only when the learning generation
changes; at most 32 classifications run per refresh, and only the resulting scalar
is cached by the engine. Learning off removes
this prior and retains the underlying data. RAM learning without Full Access still
works; the existing session gates every persistent load/save and stops on revocation.

Deleting a word's count removes its usage contribution on authoritative refresh;
removing only its keep leaves an independently counted word in use, as before.
Reset learning removes every contribution. No separate reset/control is needed.
Settings and management privacy copy disclose this use. Aggregate word counts are
sensitive; no extra language/app history is serialized.

The posterior weights both languages in next-word probabilities and existing
bounded correction/completion **display** context gains. Automatic corrections,
valid literals, pinned automatic/revert/contact slots, undo and touch learning are
unchanged. A single enabled language always uses weight 1 for that pack; neither
selected or a missing selected pack abstains. No new switch/network/microphone use.

Deterministic work: at most eight evidence-fold steps per completed word in the
bounded suffix, eight retained Doubles, two scalar priors and fixed scalars; Linux
value-plus-element payload is 104 bytes (not heap/allocator overhead or RSS).
Cached personal prior adds one Int and one Double plus optional/struct overhead.
Prior refresh sorts ≤2,000 entries and classifies ≤32; it adds no checker calls.
`KeyboardContextPosteriorTests` cover cues, switches, eviction, reset, normalization,
active-token exclusion, recency/ties, persisted counts, deletion, learning off,
Full Access denial and engine cache refresh. Historical D3b resource vectors still
test the **old** filter explicitly; new posterior behavior has separate assertions.

Same-fixture Linux evaluation: tiny abrupt mixed sample wrong-language slots
36.11% → 33.33% (12 predictions / 36 slots); alternating held-out sample 3.12% →
1.92% (417 predictions / 1,251 slots), first-three-after-switch 6.42% → 3.99%.
Recall@3 stays 33.33% / 15.11% respectively. These development fixtures are not
human code-switch accuracy; the posterior cannot anticipate an unseen switch.
Public single-language held-out recall@3 remains DE 14.06%, EN 17.74%.
Full quality/control counts and exact commands are recorded in the R2-4 research
report. Device checks remain: Apple dictionary noun casing/contractions, DE/EN/
mixed and limited-context hosts, language changes, completion/undo, actual Full
Access revocation and deletion/reset refresh, main-thread latency and peak memory.

## Personal next-word pairs

Owner-approved P4, extended by R2-2, adds a small personal follower model above
the public corpus. There are **at most two trusted predecessor words in RAM**
and no sequence archive. Both bigram and trigram edges share the original caps. Unchanged
valid/kept literals still settle only on the next unambiguous letter with their
suffix intact. A pair is counted only once both endpoints independently settle,
and the current field suffix ends exactly in `previous + " " + word + " "`.
No context endpoint is reconstructed from existing field text. A trigram additionally
requires all three independently settled endpoints and the exact three-word suffix.
Manual kept/alternative/completion choices supply an endpoint after the same
settlement; next-word picks now do too. A following owned prediction pick can
settle its predecessor, allowing chip chains without inventing taps. Picks supply
an immediate word count, but no prediction/completion touch labels. Backspace
before settlement discards the pending context endpoint (it does not roll back
an already-counted explicit-choice unigram). Automatic output, undo,
in-word deletion/retyping, second separators, Return and punctuation do not teach
pairs, nor do manual split/join boundary picks or their undo. A failed settlement
breaks adjacency; a later valid word may start a new chain.
Field, selection, layout/lifecycle/ambiguous-input discontinuities, selected-language
changes, learning toggle, authoritative reload, either reset and Full Access
revocation clear both RAM predecessors and the pending choice. Ordinary word boundaries
and applied manual choices alone do not. A clipped/missing proxy suffix abstains.

For prediction and display reranking, hard-backoff row selection probes the
normalized `earlier + " " + previous` key first, then `previous`, then uses only
corpus packs if neither exists. A retained trigram row takes precedence; this is
**row-presence backoff**, not interpolation of two personal orders. Each selected
row is discounted against the corpus mixture below (no recursive blending).
The corpus still conditions on the last word. Sentence/newline and identifier/
numeric barriers clear the extra context; a current completion token is excluded.
Row selection uses at most two personal-map probes (one on trigram hit); the
selected row has at most eight followers. Existing corpus search and ≤32-candidate
rerank limits remain, with no history-length scan.

For a retained context row, let `N=sum(counts)`, `T=number of followers`, `c=count(h,w)`:

`P_personal(w|h) = (max(c-.5,0) + 1.5*T*P_corpus(w|h)) / (N+T)`.

This is absolute discount .5 plus Witten–Bell-style backoff translated from iikb;
unknown contexts use the corpus exactly. Repeated personal words can outrank corpus
followers. Top-three prediction is exact for this mixture: seed all ≤8 personal
followers alongside corpus boosts and multiply the corpus unseen-word stopping
bound by `1.5*T/(N+T)`. A follower absent from every selected corpus pack (or
stock-name suppressed there) is a novel personal follower: it may join only after
**two** trusted sightings (`novelFollowerMinimum`), so one accidental word never
surfaces as a prediction. Corpus followers need no minimum; their personal counts
only add mass. With `c=1` the discounted term is `.5`. Selected corpus
packs remain required; German/English/mixed use the same NFC lowercase keys, with
no stored language classification or hard personal-language partition. Personal
prediction casing uses the selected dictionaries to restore nouns/proper names.
Picking a prediction applies host sentence/word/all-character auto-capitalization
when appropriate (first letter after `. ! ?`, or field start); German capitals are
never lowercased. This does not invent predictions at empty/unknown fields.

Display reranking substitutes this mixture into the existing `.35 * clip(log(P/base),
0, log(20))` gain, retaining its cap, evidence-kind slots and pinned automatic,
literal, revert and contact entries. Only a retained personal follower can receive
an OOV gain, again only from two sightings (denominator floor `1e-12`, still capped);
other OOV words still receive zero. It never
changes automatic decisions, completeness, margins, validation or undo. Learning
off supplies an empty personal model for both prediction and ranking and disables
pair updates, but retains saved counts. Corpus context remains active.

Context counts halve (integer division, dropping zeros) **before every 256th
valid row update is inserted**; a settled word with two trusted predecessors
updates the bigram then trigram row (two events), sharing the modulo clock; the modulo counter persists. This is event ageing,
not wall-clock expiry: unused data remains until eviction/deletion/reset or further
pair events. Rows/totals are derived after ageing so no stale totals survive.
Keep/rejection protections never age. Row eviction removes the lowest count, then
the lexically greatest follower; global eviction the lowest count, then greatest
context, then greatest follower. Both always spare the edge just recorded, so a
recent phrase displaces a stale weakest one instead of vanishing. Each update temporarily
has ≤513 edges and ≤9 followers in one row; bounded eviction scans can remove at
most 513 edges, never an unbounded history. Logical string+counter payload is also
bounded by the conservative ≤64 KiB JSON bound; Swift dictionaries, COW snapshots,
allocator overhead and encoding transients are extra, not measured RSS. The whole
store still caps at 256 KiB and trims pairs before unigram/protection entries.

Deleting a kept or counted word in **Manage learned words**, or a word in its
**Words in next-word contexts** section, purges every row naming it in either
predecessor position and every incoming follower reference. The immediate Backspace revert of a just-added keep only withdraws the
keep: it is not a deletion request and leaves earlier pairs. Reset learning clears
all contexts. Schema **1/2/3 → 4** migration preserves valid bigram counts without
inventing trigrams; the historical `bigrams` field/type and `learning-v1.json`
filename remain. Older clients reject schema 4 (downgrades may lose learning).
An invalid context section drops only context counts; keeps, counts and rejections
survive. Corrupt/oversized file handling and epoch-protected reset remain unchanged.
Dictation transcripts are **not seeded into this context model**; #127's existing
app-only protected-word imports are unchanged. The keyboard still never uses a
microphone, speech model or network.

`PersonalTypingTrigramTests` / `PersonalTypingTrigramEvaluationTests` add schema-3
migration, both-predecessor deletion, reset races, corrupt contexts, prediction
chains/undo, Unicode byte caps, deterministic eviction and held-out-lead-in repeat
curves for settled/completion/prediction learning. The same fixtures run against
the old schema-3 baseline; public DE/EN held-out recall stays 14.06% / 17.74% @3,
not an asserted public-corpus improvement. The mixed public measurement enables
both packs on DE/EN sentences, not public intra-sentence code-switch data. These
small synthetic repeat gains do not establish human benefit or iPhone performance.
Real iPhone checks: actual checker/casing, fast chip chains, undo, limited host
context, Full Access revocation, app deletion/reset live refresh, protected-file
migration and physical extension memory/latency (see R2-2 report).

`PersonalTypingBigramTests` and `PersonalTypingBigramEvaluationTests` cover settlement and forbidden sources, discontinuities,
manual choice/undo, migration, reset/delete races, revocation, learning-off isolation,
Unicode/mixed pairs, ageing/caps/bytes, exact mixture top-three against exhaustive
union and sentence/noun casing. Synthetic repeated-session recall (typed through the
real engine), CC0 held-out no-harm, DE/EN/mixed noisy-touch and ageing evaluations
print `EVAL P4_*`; timings are report-only, never wall-clock assertions.
These are not natural typing benefit, Apple dictionary or extension memory proof.
Only a real iPhone can prove protected persistence/backup policy, Full Access
callbacks, management refresh in a live keyboard, UIKit/host ordering and latency/RSS.

## Multi-part boundary suggestions (R2-6)

The bounded 3–4-part suggestion fallback reuses the current RAM-only observed
word and frozen calibration in the existing worker. It requires two parts with
positive observed letter likelihood and keeps all automatic split/join and Space
reinterpretation disabled: optional imported names do not protect unlisted names.
See [decoder bounds and gate curves](KEYBOARD_SPATIAL_DECODER.md#multi-part-boundary-suggestions-and-gate-remeasurement-r2-6).

Privacy/storage copy is unchanged in scope: **the keyboard does not use the
microphone, speech model or network**. This change collects no additional text,
contacts, taps, transcripts or usage history; writes no new files or App Group
fields; and adds no import source or permission. Existing app-written protected
personal terms, Full Access gating, deletion and Reset learning retain their
meaning. Temporary span/beam caches are per-call, not saved. Manual selection
and undo neither train constituent words/pairs nor infer touch labels; the
existing 64-pair RAM boundary rejection list remains separate from R2-3's durable
automatic-correction undo/confirmation memory. No automatic boundary change is
shipped, so no new automatic undo pair format or persistence migration is needed.
The entire selected replacement is still one owned-suffix edit/undo transaction.

## Manual boundary choices

The strip can offer exact omitted-space splits and conservative exact joins.
P5b ranks splits with the existing public-corpus bigram model using only the short
RAM field suffix; boundary ranking reads no personal next-word pairs and adds no storage.
This corpus influence remains active with Learn from my typing off, while personal
counts/calibration do not. Evaluated automatic-split gates either split lowercase
names/products (`ina`, `malin`, `todo`, `athome`) or recovered under 10% of omitted
spaces, so all boundary choices remain manual.
See
[the boundary policy](KEYBOARD_SPATIAL_DECODER.md#omitted-spaces-and-exact-joins).
These are **suggestion-only**, with no automatic application at Space/punctuation/
Typr-key boundaries. A manual pick replaces an owned suffix as one undoable step.
Neither picking nor undoing a boundary hypothesis teaches touch labels, a phrase
count, or constituent-word counts. No missing space is fabricated as a tap. Exact
joins need no geometry; spatial joins retain at most one previous fully observed word
and the actual real Space tap in the bounded RAM window below. The manual-alternative pick counter can
increase; boundary undo is not counted as an automatic-correction undo.

Boundary phrase rejections use a **64-pair FIFO in session RAM only**, bounded to
two words / 32 combined letters, with no new file or schema. The existing saved
letter/apostrophe-only word-pair contract is unchanged. Undo offers the immediate
explicit reversal; picking it removes the new session rejection. New typing,
selection/field/layout/lifecycle discontinuities end that immediate association,
not the session rejection itself. Learning reset clears session boundary pairs;
ordinary learning-off retains them and kept-word protections. Boundary picks do
not count as personal-word evidence while learning is either on or off; they also
break the RAM next-word predecessor and supply no pair endpoint. Persistent
protections, individual deletion and Full Access rules for existing word learning
remain unchanged. No boundary-tap archive, sentence history or network.

### Spatial boundary evidence (P6)

The same manual transaction/rejection rules cover `greatvday → great day`,
`a out → about` and gratuitous-space joins. A RAM-only boundary window owns at most
**32 combined taps including Space**, at most two nonempty words, and one changed
boundary. No raw Space archive, new schema, personal context association or additional
Full Access permission. Ordinary/learned letter densities participate, but the Space
predictive density is static: Typr has no independent trusted Space labels and never
trains Space from its own hypothesis. Learning off keeps geometry with static letter
priors and retains keeps/rejections; it does not create personal evidence.

A real Space whose tap is more likely as an adjacent bottom-row letter cancels the
first fragment's pending literal feedback. Otherwise the next letter could count/train
`a` before a user chooses `about`. Existing historical counts/keeps still veto boundary
reinterpretations; a manual pick/undo never supplies labels or constituent counts.
Normal centred Space retains the existing trusted-literal settlement protocol and
preserves the RAM predecessor across an ordinary word boundary. Retaining real Space
geometry does not settle either pair endpoint: the follower still waits for its own
next unambiguous letter. Ambiguous Space cancels pending feedback and breaks the pair
chain; spatial picks and undo also break it, so inferred boundaries supply no personal
pair endpoints. Subsequent independently typed words may start a fresh chain.
Typr-key and programmatic spaces retain their typing/double-space behavior but never
fabricate geometry. Every existing evidence discontinuity clears the window; rollover
Space commits exactly once with its last actual coordinate. The element/string payload
cap is 32,768 bytes per boundary snapshot, excluding container overhead/RSS. See
[the capture contract](KEYBOARD_TOUCH_INPUT.md#spatial-boundary-window).

Evaluation includes 72 valid-pair controls (DE/EN/mixed, normal and adversarial top-edge
Space). There are **0 automatic boundary changes**, with one ambiguous English chip
(`a out → about`) and zero DE/mixed boundary chips. This is a reason to retain the
suggestion-only product policy, not calibrated automatic precision. Synthetic quality,
byte/work bounds and Linux-only verification limits are in the spatial reference.

## Suggestion snapshot isolation

The [suggestion worker](KEYBOARD_SPATIAL_DECODER.md#suggestion-worker-and-boundary-authority)
receives immutable Sendable calibration/personal-prior values. All live learning,
protection/rejection mutations, diagnostics and pending feedback stay on MainActor;
worker output alone never teaches. Boundary jobs additionally share bounded personal
snapshots for exact two-part lookup; a latest-only retrieval cache owns no text history. Results and chips must match learning generation
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

The calibration value includes all bounded xx/xy/yy terms and the moment-matched
stable/40/8 affine-aim prediction, not a reference to live memories. Snapshot reads
are side-effect-free: reading another layout cannot silently reset aim outside
learning generation. Trusted updates and actual fast-state resets advance that
generation; repeated resets of already-empty fast state do not. A stale aim result
is rejected before checker/cache/diagnostic mutation, and the ownership-aware poll
refreshes once for the changed generation. Applied manual choices invalidate their
word/revision but preserve the fast aggregate aim just trained by trusted feedback.

## Files, saves and reset

The existing App Group (`group.dev.rudek.typr`) contains:

- `<AppGroup>/Typr/Keyboard/learning-v1.json` — at most **256 KiB** encoded.
- `<AppGroup>/Typr/Keyboard/diagnostics-v1.json` — at most **64 KiB** encoded.
- `learning.lock` — coordination only, not a data archive.

The learning **value schema is now 3**, retaining the `learning-v1.json` filename
so reset/locking and existing byte limits remain authoritative. Schema 1 migrates
in memory with xy=0 and no invented global stream; keeps, counts, rejected pairs,
layout dates and diagonal statistics survive. Missing global data stays absent
until new labels arrive. Unknown future versions fail closed.
Invalid/non-PSD/nonfinite covariance fails load validation; save-time repair drops
only invalid key/global aggregates and preserves unrelated lexicon data. No migration
persists fast memories or reconstructs raw taps. Schemas 1/2 migrate to empty
next-word counts (no invented observations),
retaining all previous state; the next save writes 3. Schema-1/2 clients reject 3
through their existing version validation, not reinterpret it. This follows the
existing fail-closed downgrade convention; an old client can subsequently replace
an unsupported snapshot with its empty model, so downgrades can lose learning.

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
next-word pairs and rejected pairs. Statistics, including accepted/rejected label totals, remain.
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
inside diagnostics, loads saved kept words, rejected `typed → replacement` pairs,
frequent-word counts and the words participating in next-word pairs only after an
explicit tap. Deleting a kept/count word also purges every incoming/outgoing
next-word pair; the **Words in next-word pairs** section makes pair-only words
deletable without displaying associations. Reset learning clears all pairs. The search field filters all three
categories by partial word, ignoring case and diacritics, and searches both sides of
rejected corrections. An empty search shows everything; no matches get an explicit
message. Deletion while searching targets only the selected visible entry.
Swipe or Edit deletes one entry; keeps and counts are separate entries even when
they share a word, but either deletion purges that word's next-word associations.
No pair association, sentence history, raw taps or per-word dates are shown.
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
| Picked personal completion | Completion picks whose chip was placed by personal completion ranking; a subset of completion picks, not a measure of ranking benefit |
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

The touch map reconstructs bucket-width geometry, draws saved slow shrunk/clamped
centers and correlated one-sigma ellipses, and lists per-key effective counts accessibly.
Keys below 20 have gray outlines; pooled evidence can still inform them in the keyboard.
The app explicitly does not show RAM-only fast aim. It displays **model parameters,
not raw taps, moved hit
targets, measured hit probability, accuracy or improvement**.

No undo does not mean a correction was right. Many repairs are not linked undo,
and some mistakes go unnoticed. Counts are not precision, recall or error rate;
model movement is not benefit. Synthetic decoder evaluation and outstanding
Apple CI/owner iPhone checks are listed in the
[correction-path reference](KEYBOARD_SPATIAL_DECODER.md#required-owner-iphone-checks).
Do not export or commit personal word collections, tap data or private snapshots.
