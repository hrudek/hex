# Hex+ dictation log

The **Dictation log** switch in the app's **Hex+** card is **on by default**
(`hexplus.dictationLog`, App Group settings). **Show dictation log (n)** opens a
live list, newest first. This is Hex+-owned iOS behavior, not desktop History.

## Two audiences, two exports

Tap a dictation for a compact **Recognition & cleanup** view. It shows the
recognition engine/language, style, selected cleanup path, actual outcome and
answer use, app/iOS versions, prompt/guard revisions and active vocabulary.
A selected path does not prove a model call; an accepted answer only passed the
guard, not a correctness test. Model identity is limited to the known on-device
Apple FoundationModels backend; no exact system model version is available.

**Technical diagnostics** is collapsed by default. It retains creation time,
storage schema, both AI switch states, source/output/copy flags, route port types,
Bluetooth flag, loudest sampled average dBFS, ASR/cleanup/model/stop-to-final
timings, redundant changed flags and diagnostic summaries. Route metadata never
contains device names or UIDs. Unknown ASR failures keep their type name, not
error descriptions or associated payloads. Timing is monotonic in-process
measurement, not a guarantee across iOS suspension.

The **Export** menu on both list and detail offers:

- **Recognition & cleanup improvement** → **Copy** or **Share**: text and
  configuration/outcome evidence relevant to result quality, without technical
  noise, duplicate complete text, or zero-replacement sections.
- **Complete diagnostic log** → **Copy** or **Share**: all retained text and
  technical facts, regardless of which UI disclosures are open.

The list exports **all retained entries**; detail exports just that entry.
Both clipboard formats expire after five minutes and intentionally allow
Universal Clipboard. Share uses the system share sheet. Both are plain text,
with a versioned export header (**v2**, independent of schema-1 storage).
A batch has one shared explanation of evidence limits.

Exports may contain private dictated text, unused model answers, active
vocabulary spellings and human feedback. The app cannot retract copies already
exported. Exporting is explicit; there is no upload, training service or sync.

## Text evidence and human reference

The stages are recorded at their actual production boundaries:

```text
Recognized (raw ASR)
└── Cleanup input (after first vocabulary pass)
    ├── Raw Hex+ model answer, with accepted/rejected/late label
    └── Cleanup output actually used (including fallback)
        └── After style formatting
            └── Final text provided (after second vocabulary pass)
```

An unused model answer is never presented as the cleanup output. The new cleanup
output also records upstream returned/fallback text, without claiming the
upstream API exposes a raw model answer. Formatter damage can now be distinguished
from model damage and vocabulary replacements. Logging does not re-run or change
these transformations.

The improvement export prints each distinct complete stage once; exact repeats
reference an earlier named stage. Matching truncated prefixes are **never**
deduplicated. The UI collapses unchanged stages with a show-text disclosure.
Missing evidence, including new stages absent in older entries, says **not
recorded**, not unchanged. AI input still falls back to Recognized under the
existing storage convention (nil means the first spelling pass was unchanged).

**Human reference** lets the user enter **Desired final text** and an optional
error note. The editor starts empty, never prefills model output as ground truth,
and refuses fields above 4,000 UTF-8 bytes rather than silently truncating labels.
Empty fields remove feedback. Feedback persists with that entry and appears in
both exports. It does not change delivered text, train or modify a model.
A missing reference is explicitly labelled **not a labelled training example**.
Imported/truncated feedback is marked as incomplete.

There is **no retained audio**, so logs alone cannot establish what was spoken or
provide reliable ASR WER. A desired final text is a reference for the intended
finished result, not necessarily a verbatim transcript. Human-reviewed examples
can guide prompts, guard rules, vocabulary and formatter regression tests; they
are not automatic model training. The final provided text does not prove actual
keyboard insertion or host-app spacing.

Two on-demand word comparisons remain: **AI input → AI answer** and
**Recognized → Final**. Removed tokens are struck out; additions are bold and
underlined; `↵` marks line breaks. Diffs are not semantic quality judgments.
Truncation is disclosed; above 400 tokens per side the comparison is skipped.
The LCS is bounded to 400 × 400 plus its sentinel row/column.

## Vocabulary and upstream evidence

Each pass retains the first **20 actual replacements** (span → replacement and
matched term), with the full operation count. Repeated occurrences are separate;
no-op matches do not count. Missing evidence is distinct from zero replacements.
Counts measure operations, not correctness. Strings are quoted and truncated
replacement records/omitted counts are labelled.

New captures additionally freeze the **active vocabulary spellings**: up to 100
quoted terms in one capped 4,000-byte snapshot, explicitly marked if truncated.
Disabled vocabulary records an empty active list. This intentionally expands
private retained evidence beyond just matched terms, allowing diagnosis against
the actual configured spellings rather than today's mutable list. Older entries
with active terms but no snapshot say the spellings were not recorded.
Apple Speech hints are best effort; no individual recognition change can be
attributed to them. Parakeet's batch path has no recognition hints.

Upstream preserves **changed / unchanged / no result**, with a new supplementary
reason for known pre-call skips (missing/unavailable cleaner, disabled, Verbatim,
empty input). An actual nil return is identified as such; its API exposes no
underlying failure reason, so timeout versus model error must not be guessed.
No upstream cleaner internals were modified. Hex+ overrides upstream when on;
Verbatim selects no AI. Frozen AI switches remain in full diagnostics.

## Lifecycle, privacy and storage

One entry is created after a capture passes the existing 300 ms minimum and
reaches transcription. It terminates exactly once as **Finished**, **Speech
recognition failed**, **Cancelled**, or **Interrupted**. Reopening converts
unfinished saved entries to Interrupted. Recording-stage cancellations, short
taps, permission/open failures and discarded captures have no entries. Ending a
warm session does not cancel already-accepted transcription.

Each capture owns an immutable entry ID, enabled/epoch token and recorder.
Clear/Off/On invalidate old tokens. Updates require the matching epoch and an
existing entry: deletion/eviction never resurrects one, including from an open
feedback editor. Only `DictationController.shared` injects the shared store;
default test controllers do not implicitly open it.

Finished/ASR-failed recorders accept only a late model answer update, never a
replacement final text or intermediate stage. Cancelled/interrupted recorders
accept nothing. Late labels distinguish deadline (4 s), background expiry and
other resolution. Capture A's late answer cannot attach to capture B.
Background leases, cancellation, exactly-once cleanup resolution and text-free
`CleanupLogger`/App Group `CleanupDiagnostics` remain unchanged.

Storage: `Application Support/HexPlus/dictation-log.json`, app container only.

- **20 entries**, newest first, **no time-based expiry**. Feedback shares that
  retention: export reviewed examples before newer dictations evict them.
- Every text field is capped at **4,000 UTF-8 bytes**, on Swift Character
  boundaries, with an ellipsis inside the budget. Original byte/word counts and
  truncation flags survive. Up to nine fields per entry (four original fields,
  two new stages, two feedback fields and one vocabulary snapshot) allow up to
  720 kB across 20 entries before replacement records and JSON overhead.
- Encoded JSON must be **≤ 1,000,000 bytes**. Oldest entries are additionally
  evicted to fit; there may be fewer than 20. Replacement-heavy entries can
  evict older entries sooner.
- One synchronous bounded load at initialization; reads stop at 1,000,001 bytes.
  Oversized/corrupt/unknown-schema files are ignored and deleted. Loaded text
  fields are re-capped, IDs deduplicated. Optional additions preserve schema 1.
- Atomic writes on a utility serial queue; one coalesced pending snapshot,
  latest wins. Epochs prevent stale queued writes; an in-progress write completes
  before the newer deletion. Dictation never awaits disk I/O.
- The directory/file are backup-excluded, with
  `completeUntilFirstUserAuthentication` protection reapplied after replacement.
  This permits background writes after first unlock; it is not a separate app
  password or secure erasure. No audio, prompts, device names, error descriptions
  or network requests are retained by this log.
- **Clear** removes entries and invalidates the epoch; **Off** also saves the
  disabled switch. Off at launch deletes before load. Storage failures never
  fail dictation; a fixed notice permits retrying Clear/Off. Deletion cannot
  promise secure overwrite or removal while iOS refuses I/O. Existing App Group
  keyboard results and ordinary dictation clipboard are unrelated and unchanged.

## Verification

`DictationLogImprovementTests` covers compact/full exports, named exact-stage
references, truncation and old-entry gaps, separate model/fallback/formatting
stages, feedback round-trip/deletion, no resurrection and late-answer isolation.
Controller tests also assert actual production stage hooks and frozen vocabulary.
Existing `DictationLogAnalysisTests`, `DictationLogStoreTests`,
`DictationLogCleanupTests`, `DictationLogControllerTests` and `WordDiffTests`
cover matching, storage limits, capture isolation, cleanup and bounded diffs.

Local verification: Swift 6.1.2 frontend parsing passed for changed Swift files
and the existing dictation-log tests; `git diff --check` passed. A temporary Linux
harness typechecked and ran the actual model/export presentation code with
platform-only methods removed and word-count/prompt constants stubbed. It passed
schema round-trip, compact/full selection, stage references, human labels,
truncation, old-entry gaps and batch caveats. This is not an iOS build or XCTest
run. Linux has no Xcode/iOS SDK; native compilation, simulator, visual and device
proof remain open. Before shipping, build production/test Swift
with Xcode 26 / Swift 6 and run these simulator classes plus
`AICleanupControllerTests` and `HexPlusCleanupTests`. Manually verify collapsed
technical details, unchanged-stage disclosures, feedback save/remove, both export
formats and both Copy/Share paths for one/all entries, retention/deletion,
background writing, file protection/backup exclusion, and unchanged original
keyboard/cleanup delivery with logging Off. See [AI_CLEANUP.md](AI_CLEANUP.md).
