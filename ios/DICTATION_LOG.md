# Typr dictation archive and feedback

## Explicit local analysis (C)

Use the dependency-free [local Python importer/report](tools/dictation_log/README.md)
with an explicit private store **outside Git**. It preserves raw export evidence,
merges whole entries by archive UUID/entry UUID/revision and reports observational
rating/reference/category/timing coverage. Default output has no dictated text or
vocabulary; settings fingerprints use a private per-store HMAC (not encryption).
Reference edit metrics are intended-final-output comparisons, **not ASR WER** or
semantic quality. Unknown export scope stays unknown; absent entries never delete
saved data. No upload, inference, replay, background job or automatic regression
comparison. Python tests run locally, **not automatically in existing CI**.

Export entries may contain the optional `keyboardFeedbackOffer` correlation IDs
from B. They contain no text and are preserved as source evidence, never interpreted
as permission to post feedback by the local tool. Export v1 dates have whole-second
precision: the importer uses whole-entry revisions, never timestamp-only merges.

The Typr **Dictation log** switch (`typr.dictationLog`, on by default)
controls collection, not retention. **Off stops new collection and interrupts
unfinished saved entries; it keeps existing history.** Read, rate, edit a
reference, export and explicitly delete saved entries even while Off. This is
the owner's deliberate retention exception to the earlier switch semantics.
There is no automatic count, age or aggregate byte eviction.

## Everyday feedback

Open **Typr → Show dictation log**, or tap **Fix in Typr** on the keyboard after
Problem (see below). The list uses metadata, a 120-character preview and All /
Unrated / Problems filters. Leading Good and trailing Problem swipes have explicit
VoiceOver equivalents.

The detail is built for daily feedback and shows only:

1. **Recognized**: the raw speech-recognition text, with a **Copy** button.
2. **AI correction**: the final text provided (after AI cleanup, formatting and
   vocabulary), with a **Copy** button. Without an AI pass it says so.
3. **What I said / expected**: an inline field for the human reference
   (`expectedText`). Copy a text above, paste it and correct it instead of
   retyping. **Save** (also on Done and when leaving the detail) owns only this
   field; the separate note is never touched by it.
4. Good / Problem buttons.

Everything else is still recorded and exported, but hidden behind **More
details** (off each time the detail opens): issue categories, the note editor,
every processing stage, vocabulary replacements, diffs and technical
diagnostics. Problem saves immediately; optional issue choices are:
`misheard`, `missing_or_shortened`, `unwanted_rewrite`, `punctuation_formatting`,
`vocabulary_name`, `too_slow`, `other`. Rating does not require an editor.
Copy writes to the clipboard only on an explicit tap.

Good does not manufacture a reference. Removing a rating preserves reference,
notes and categories. Clearing categories is explicit. **Desired final text**
and **Feedback note** are optional and can be edited later; Save owns only these
two fields, never an older snapshot of the rating. Each field refuses input
above 4,000 UTF-8 bytes. Unknown future rating/issue strings are preserved.

Rating order is the strict total key `(modifiedAt, origin, eventID)`; app actions
receive a UUID. Equal or older keys are no-ops. Reference/note have a separate
order. Every mutation increases the per-entry revision. These are observations,
not labelled audio examples or an automatic model-training pipeline.

## Retention, privacy and deletion

Saved text stays on this iPhone until explicitly deleted. **App removal, device
loss and storage failure are not covered; export JSON to keep a separate copy.**
The archive is backup-excluded and protected with
`completeUntilFirstUserAuthentication`, not a separate password or secure erase.
No audio, prompts, device names, error descriptions or network uploads are added.
The list shows total metadata count and approximate encoded archive MB.

Detail's Entry actions menu deletes one entry. Clear requires confirmation and
also removes legacy data and owned temporary exports. Delete/Clear cannot retract
copies already shared with another app. Failure shows a generic retry notice;
deletion is never reported as successful merely because the button was tapped.
Off/On/Clear fence capture callbacks. Clear changes archive lineage and separately
fences storage loads/exports; fresh captures submitted after Clear survive.

## Files and migration

`Application Support/Typr/DictationLog/v2/entries/<UUID>.json` is the source of
truth, one atomic protected file per entry (storage schema 2). `archive-id.json`
identifies the lineage. The rebuildable metadata index contains ID/date/status,
rating/issues/source/revision, bytes, filesystem fingerprint and short preview.
Startup checks all directory names/fingerprints; missing, stale and corrupt
indices cannot permanently hide newer files. Full entries load lazily; roughly
50 are cached in addition to dirty writes, active recorders and current detail.
Capture never waits for startup or I/O. New in-memory mutations beat older loads.

One serial utility queue owns source writes, deletes, migration, reads and
snapshot admission. Each entry write is independently admitted; unrelated entries
cannot be lost to whole-history snapshot coalescing. Index writes coalesce as a
cache only, after source writes. Failed source writes remain dirty for Retry.

Schema-1 `Typr/dictation-log.json` migrates independently of collection being
on. Copies are re-read and verified and a completion marker is verified before
the original is removed. Existing v2 copies always win, including after a
downgrade. Unknown/corrupt originals remain in place with a generic notice;
unresolved copies keep the legacy source. Durable per-UUID deletion markers in
`deleted/` precede entry removal; migration and later writes respect them, so an
unfinished migration or a downgrade's reappearing schema-1 file cannot resurrect
an explicitly deleted entry. Clear removes those markers with the old lineage.
Retry rescans and retries migration.
An interrupted saved transcription is finalized on startup unless owned by the
current process. Wrong filenames are rejected before any write.

## Export

**JSON → Prepare JSON — entire archive** includes all readable persisted entries,
not the visible filter, page or cache. Detail can prepare just one entry. Preparing
is explicit, off main, with progress/error UI and a privacy notice. **Share
prepared JSON** opens the system share sheet; preparing is not proof that a
recipient saved the file. Nothing is automatically copied or uploaded.

Export envelope v1:

```json
{
  "format": "typr.dictation-log",
  "exportVersion": 1,
  "exportedAt": "2026-11-08T12:00:00Z",
  "archiveID": "UUID",
  "appBuild": "build number or unknown",
  "unreadableFiles": 0,
  "legacyMigrationPending": false,
  "dateEncoding": "ISO-8601 UTC",
  "evidenceLimits": "…",
  "entries": []
}
```

Dates throughout exported entries use ISO-8601 UTC. Entries carry storage schema,
revision, frozen context/settings/model identity evidence, prompt/guard revisions,
stages, truncation evidence, feedback and its ordering. A partial archive with
unreadable files or pending legacy migration explicitly reports that limitation;
it is not represented as a complete backup. Corrupt originals are not destroyed.

All earlier source writes precede snapshot admission. Hard links freeze atomic
entry inodes; streaming runs on a separate utility queue, so a long export cannot
block recording/output or subsequent source writes. Clear or per-entry deletion
removes owned export workspaces and cancels pending sharing. Export workers never
recreate a deleted workspace. Temporary workspaces stay alive while the share
sheet reads them, are removed after dismissal or preparing a replacement, and
are cleaned on startup. Already external copies cannot be revoked.

Existing **Text** Copy/Share formats remain for explicitly labelled **loaded
entries, up to 50**, constrained by the current filter; they are not all-history
exports. Detail's plain text exports still contain one entry. Clipboard export is
explicit, allows Universal Clipboard and expires after five minutes.

## Evidence limits

Stages remain Recognized → cleanup input after vocabulary → raw model answer
(with accepted/rejected/late label) → cleanup output actually used → formatted →
final provided text after vocabulary. Late unused answers never replace delivered
text. Technical diagnostics remain collapsed. Exact complete duplicate stages
reference earlier stages in improvement text; truncated prefixes never dedupe.
Missing older evidence means not recorded, not unchanged/off.

Frozen active vocabulary is capped to 100 terms / 4,000 bytes. Each spelling pass
keeps the first 20 replacements plus total count. Per-field truncation, original
byte/word counts and bounded 400-token comparisons remain explicit. Speech hints
are best effort; counts are not correctness scores. Selected model configuration
is not proof a model ran; Apple controls its exact checkpoint. Provided-to-keyboard
is not proof of insertion or final host spacing. Human final-text references do
not establish ASR WER or semantic correctness without audio.

## Verification

Approved delivery contract: [DICTATION_FEEDBACK_PLAN.md](DICTATION_FEEDBACK_PLAN.md).
`DictationLogStoreTests` covers >20 retention/reload, startup/new capture, Off
interruption/fencing, Clear/load/write/editor races, migration/reappearance,
corrupt legacy preservation, feedback total order/editor ownership, complete
archive JSON and index rebuild. Existing controller, cleanup, improvement,
analysis and WordDiff tests retain stage/late-answer coverage with updated Off
expectations. Tests use synthetic data and temporary roots only.

On Linux a recovered local Swift 6.4.2 toolchain parsed the changed Swift and
successfully compiled/ran a temporary harness using the actual model/store/
archive code with iOS-only capture/protection methods stubbed. It exercised 80
entries + reload, whole JSON, migration/reference/interruption, corrupt legacy
preservation/partial-export evidence and Clear lineage. This is **not** an iOS
build, XCTest run, protection proof, UI/VoiceOver proof or real device test.
Native unsigned archive and optional targeted simulator CI results belong in the
PR. Real iPhone file protection/lock, background lifecycle, share recipients,
VoiceOver and on-device model quality still require hardware verification.


## Keyboard quick feedback (B)

Typr › Keyboard dictation feedback is **on by default** (independent of the
archive collection switch). Good / Problem / dismiss use the existing compact
tray or full-keyboard suggestion strip, on **both** surfaces. The full keyboard
retains Undo dictation as a separate sibling; while feedback shows, Undo is an
icon (same action and VoiceOver label) so every feedback action fits without
scrolling. The full-keyboard bar lays out its items with explicit frames because
it is created hidden and filled only when a result arrives.

After **Problem**, the keyboard shows **Fix in Typr** instead of issue categories:
the keyboard cannot usefully show what was recognized and what AI made of it.
Fix in Typr opens `typr://typr/feedback?entry=<UUID>` (the entry ID
only, never text); the app opens the log on that entry with **What I said**
focused. The link never starts a dictation session. Categories remain available
in the app under More details. No keyboard text editor, document inspection for
feedback, clipboard copy or network request.
The compact targets are at least 44 pt wide, **26 pt high**, matching the existing
tray; they are not 44 pt tall. The full strip retains its existing 33 pt height.

Only this keyboard instance's newly inserted, locally initiated result gets an
offer. Entry/job/result IDs, archive lineage, generation and a ten-minute offer
expiry match explicitly. A stored previous result alone never prompts. First
editing, another recording, keyboard disappearance, dismiss, expiry, no Full
Access, either switch off or generation revocation hide it. Style and next
recording remain reachable. The opt-out preserves ordinary keyboard behavior.

One protected, backup-excluded, text-free App Group JSON file per event carries
rating, optional **whole category set**, IDs and creation time. At most 100 valid
pending events, expiring after 30 days, with no eviction of valid events to make
room. Full/unavailable queues say **Not queued** and offer Retry; selection rolls
back to the last successfully queued state. **Noted on keyboard means queued,
NOT saved in the archive.** No ACK is inferred from an event disappearing.

The app drains during its existing keyboard poll, activation and archive load.
Loading/retry is not consent revocation: it neither rotates an existing generation
nor discards previous-session events. Off, strip opt-out and Clear revoke offers;
Clear creates a new archive lineage. Exact-entry feedback can load an evicted
entry, but never recreate a deleted entry. The durable source order is
`(modifiedAt, origin, eventID)` (lexicographic, strictly newer only); app and
keyboard use UUID event IDs. Reference/note ownership remains separate. Source
write + file synchronization precede removal; replay after commit-before-removal
is a no-op. Unreadable sources retain pending evidence for Retry. Queue notices
are separate from storage errors. Snapshot protocol adds only an optional offer,
atomically alongside its result rather than a racing separate defaults key.

Queue I/O uses a cross-process nonblocking exclusive file lock with three short
attempts on its utility queue. Busy operations fail honestly for explicit retry.
The archive's serial writes now synchronize files (potential extra I/O, never
awaited by dictation output). Device suspension while an App Group lock is held,
locked-device protection, background delivery, real Full Access transitions,
VoiceOver and actual host text/cursor behavior still require device verification.
No native iOS proof is claimed from Linux.

Synthetic checks: `DictationKeyboardFeedbackTests` covers exact inserted matching,
ordering, separate reference ownership, durable-write retry, replay, Off/Clear/
Delete/opt-out, simultaneous writers/cap, malformed/expired events, unloaded
entries, load-with-new-offer generation stability, and full-keyboard Undo/host
text/typing dismissal, a feedback offer that arrives after the full keyboard was
mounted (the on-device order), Fix in Typr opening the exact entry link, link
routing that never parses as a launch request, and reference saves that keep
the note. Scene names: `keyboard-feedback`,
`keyboard-feedback-problem`, `full-keyboard-feedback[-dark]` and
`full-keyboard-feedback-problem[-dark]`. Fixtures are synthetic, not real extension
or device proof. Linux strict Swift 6 typechecking uses platform stubs; all eight
non-UIKit XCTest cases also passed under the Linux XCTest runner after the
independent review fixes (Swift 5 mode for its Linux XCTest discovery adapter). Native CI results are recorded on the PR, not inferred here.
