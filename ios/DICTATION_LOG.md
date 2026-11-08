# Hex+ dictation log

The **Dictation log** switch in the app's **Hex+** card is **on by default**
(`hexplus.dictationLog`, App Group settings). **Show dictation log (n)** opens a
live list, newest first. Tap a row for text, comparisons and diagnostic facts.
This is Hex+-owned iOS behavior, not upstream's desktop History.

## What it keeps

One entry for each capture that passes the existing 300 ms minimum and reaches
transcription. Entries start as **Transcribing…** and end exactly once:

- **Finished:** final formatted text was provided to the app and, when requested,
  the keyboard and/or clipboard.
- **Speech recognition failed:** fixed category `modelNotReady`, `cancelled`,
  `noSpeech`, or `other`. Unknown failures retain only the error's type name,
  never its description or associated payload.
- **Cancelled:** Cancel or a replacement recording invalidated accepted work.
  This is visible immediately, even if ASR ignores task cancellation.
- **Interrupted:** the saved entry was still transcribing when the app ended.
  Reopening the app converts it to Interrupted; it cannot resume that capture.

Cancellation **during recording**, short taps, permission/open failures and
recording-stage interruptions that discard the capture have no entry. This is a
known scope limit: no text exists yet, and logging those would require hooks
through additional upstream paths. An interruption that finalizes an accepted
capture follows the normal transcription path. Ending a warm session during
accepted transcription/cleanup does **not** cancel it; it still delivers and
finishes as before.

### Text and processing evidence

- **Recognized:** raw ASR output.
- **AI input:** the first vocabulary spelling pass's output. Stored separately
  only when it differs from Recognized; otherwise the detail uses Recognized.
- **AI answer:** raw Hex+ model output, including whitespace, with **accepted**,
  **rejected(reason); not used**, or a late-answer label. Rejected answers are
  diagnostic evidence, **not** the text the app delivered. A thrown model error
  has no answer to store.
- **Final text provided:** output after the existing single style-formatting pass
  and second vocabulary spelling pass.

Word counts, original UTF-8 sizes and changed flags are measured before text
truncation. The model's changed flag compares the accepted, trimmed answer to
trimmed cleanup input, just as the existing cleanup diagnostics do; the pipeline
flag compares the exact raw ASR and final strings.

Two expandable, on-demand comparisons show **AI input → AI answer** and
**Recognized → Final**. Removed tokens are struck out, added tokens bold and
underlined; line breaks are visible as `↵`. These are textual differences, not
judgments of meaning, model quality or correctness. A rejected/late answer may
have a diff even though it was never used. A comparison of truncated fields says
so. Above 400 tokens on either side the view says **Too long to compare** and
keeps both text sections available. Tokens preserve words, whitespace and line
breaks; the LCS has at most 400 × 400 comparisons plus its sentinel row/column.

### Facts and timing

Details (also included in exports) contain:

- Entry ID, schema, created time, status, app version/build and iOS version.
- Keyboard job and copy-request flags; outputs **shown in app**, **provided to
  keyboard**, **copied to clipboard** as applicable. **Provided is not proof of
  insertion**: the keyboard can adjust spacing, and the host app may not consume
  a result. Empty text is not claimed to have been copied.
- Frozen style and cleanup path (`hexPlus`, `upstream`, `none`), speech engine's
  display name and **speech language** (the engine's ASR language label, not an
  Apple Intelligence language inference).
- Recording duration; audio input **port types only** and Bluetooth yes/no,
  sampled at finish before restoring capture audio. No device names or UIDs.
- **Loudest average level, dBFS**: maximum of sampled `averagePowerDB` values,
  not a signal peak. If no finite meter sample arrived, it says not sampled.
- Monotonic ASR, Hex+ cleanup-resolution and model-return milliseconds, and stop
  → final-text-provided time. Model time is measured from the actual model call,
  independently of cleanup resolution. A thrown call that wins resolution records
  duration without an answer (a defaulted `modelFailed` diagnostic callback);
  an error thrown after resolution is usually cancellation and reports neither.
  A returned answer records its time even when late. These are in-process measurements,
  not guarantees of elapsed wall time while iOS suspends the app.
- Stable Hex+ outcome and the same fixed sentence as `CleanupDiagnostics`,
  accepted-result changed flag, prompt/guard revisions (`2026-11-08a`).
- Upstream cleanup reports **changed / unchanged / no result** only; its optional
  string API exposes neither a raw model answer nor a detailed failure reason.
  Verbatim's path is `none`. No upstream internals were added or changed.
- Active vocabulary term **count**, and whether the first and second spelling
  passes changed text. No whole vocabulary list and no speculative applied-term
  list are retained; before/after text is the evidence.

## Late answers and capture isolation

Each capture freezes a permission token (enabled + epoch) at recording start.
It creates its own recorder only after passing the minimum duration. Each recorder
holds an immutable entry ID and store epoch; there is no global current draft.
Every update checks epoch and entry existence. Eviction or deletion never
re-inserts an entry. Default-created/injected test controllers do not implicitly
open a log: only `DictationController.shared` explicitly supplies the shared store.

The optional `CleanupTextDiagnostics` sink is separate from `CleanupObserving`.
A cleanup operation captures only its own recorder. If A reaches its deadline,
B skips busy, and A answers later, only A gains the late answer. A's final text,
status and resolution outcome stay unchanged. Labels use A's stored outcome:

- Deadline: **arrived after the 4 s deadline; not used**.
- Background expiry: **arrived after iOS ended the background time; not used**.
- Otherwise: **arrived after cleanup had resolved; not used**.

Finished (and ASR-failed) recorders accept only this late-answer update after
termination. Cancelled/interrupted recorders accept nothing. Cleanup delivery,
background leases, reservations, the four-second deadline and exactly-once
resolution are unchanged. Existing `CleanupLogger` and App Group
`CleanupDiagnostics` remain **text-free**; the new sink never sends text to them.
See [AI_CLEANUP.md](AI_CLEANUP.md) for cleanup's contract and residual risks.

## Storage, limits, Off and Clear

This introduces a **persistent diagnostic text history** in the app container:

`Application Support/HexPlus/dictation-log.json`

It stores **no audio**, makes no network requests and has no sync service. The
file and containing HexPlus directory are excluded from device backups. Atomic
writes use `completeUntilFirstUserAuthentication` protection and explicitly
re-apply protection and backup exclusion after replacement. This allows background
writes after first unlock; it is **not** encryption with a separate app password.
Data in the existing App Group keyboard snapshot or ordinary dictation clipboard
is unrelated and unchanged.

- **20 entries**, newest first; **no time-based expiry**. Old entries remain until
  replaced by newer ones, Clear or Off. There is no archive.
- Each of four text fields is capped at **4,000 UTF-8 bytes**, on a Swift Character
  boundary, with an ellipsis inside the budget. Typically entries are a few kB;
  the raw text maximum is 20 × 4 × 4,000 = 320 kB plus metadata.
- The encoded JSON must be **≤ 1,000,000 bytes**. JSON escaping can expand control
  characters, quotes and backslashes; oldest entries are additionally evicted
  until the encoded snapshot fits. Thus there may be fewer than 20 entries.
- The store synchronously loads once on the main actor at initialization (app
  launch in production), never through a later async merge. Reads are bounded to
  1,000,001 bytes. Oversized, corrupt or unknown-schema files are ignored and
  deleted. Decoded entries are re-capped and deduplicated.
- Encoding is on the main actor before submission. A utility serial I/O queue
  has one coalesced pending snapshot; latest wins. Writes/deletes carry epochs;
  stale queued writes are discarded. A write already in progress completes
  **before** the newer delete/snapshot. Dictation does not await disk I/O.
- **Clear** invalidates the epoch, removes all entries immediately and queues
  deletion. **Off** does the same and changes the saved switch. Off → On also
  invalidates permission: a capture from before Clear/Off/On cannot reappear.
  When launch settings are Off, deletion happens before any load.
- A storage failure never fails dictation. A fixed **could not be saved or
  deleted** notice is shown; no filesystem error description is retained. Off or
  Clear is not a secure overwrite and cannot promise deletion when iOS refuses
  I/O; retry Clear/Off when storage is available. A successful latest storage
  operation clears the notice; Clear remains available to retry a failed deletion. System storage snapshots and
  exports already made are outside the store's control.

## Conscious exports

**Copy** exports the selected entry's text and facts as plain text, using a
five-minute pasteboard expiration. Universal Clipboard is intentionally allowed
(no `localOnly` flag), so the owner can copy to a Mac. **Share all n dictations**
exports every retained entry, not just the visible row, via the system share
sheet. Treat either as private speech: recognized words, unused AI answers,
spellings present in the text and diagnostic facts can leave the iPhone when
explicitly exported. The app cannot retract a receiving app's copy.

## Verification and handover

New simulator test classes (automatically included by `ios/project.yml`'s
`HEXMobileTests` folder source):

- `DictationLogStoreTests`: default-on isolated settings, UTF-8/Character caps and
  original word counts, newest-20 eviction, round trip, interrupted recovery,
  corrupt/oversized/unknown schema deletion, decoded re-capping, Clear/Off/On
  token invalidation with pending writes, terminal late-answer rules and labels,
  backup-exclusion metadata, storage-error recovery, and encoded-size eviction
  with escape-heavy text.
- `DictationLogCleanupTests`: accepted/unchanged/rejected/empty/raw Notes answers,
  deadline/expiry → finished → late answer, A/B busy isolation and exact outcome
  count, thrown-call timing without an invented answer, cleanup-time deletion/
  cancellation, and the unchanged text-free App Group
  summary shape. Uses existing cleanup fakes and continuation-driven sleepers.
- `DictationLogControllerTests`: delivery and diagnostic facts/timings,
  categorized ASR failure, immediate cancellation and replacement while ASR is
  held, warm-session end during accepted cleanup, finished deadline/expiry entries
  receiving their own late answer without changing delivery, Clear/Off/On during
  recording and ASR, nil-injected log behavior, short/cancelled captures, failed
  storage that does not affect delivery, explicit-export evidence, vocabulary
  evidence and upstream outcomes.
- `WordDiffTests`: empty/identical/added/removed cases, reconstruction of both
  strings, DE/emoji/whitespace/Notes lines and the bounded worst-case matrix.

**Not run locally:** this Linux worktree has neither Swift nor Xcode. Static
inspection, tree-sitter Swift syntax parsing and `git diff --check` are not
compilation or simulator proof. No new
native build, simulator pass, visual screenshot, file-protection/backup behavior
on a device, model-quality, background-survival or physical-keyboard insertion
result is claimed. No CI was dispatched, push made or PR opened by this task.

Optional manual CI target list (run only when requested):

```text
HEXMobileTests/DictationLogStoreTests,HEXMobileTests/DictationLogCleanupTests,HEXMobileTests/DictationLogControllerTests,HEXMobileTests/WordDiffTests,HEXMobileTests/AICleanupControllerTests,HEXMobileTests/HexPlusCleanupTests
```

Before shipping, compile production and test Swift with Xcode 26 / Swift 6 and
run those simulator tests. On an iPhone check both appearances, list/detail live
updates, rejected and late answers, Clear/Off across app restarts, background
writing after first unlock, backup exclusion and file protection, Share all,
five-minute Copy/Universal Clipboard, and that the original dictation/keyboard
and warm-session behavior is unchanged with logging Off.
