# Hex+ dictation archive and feedback

The Hex+ **Dictation log** switch (`hexplus.dictationLog`, on by default)
controls collection, not retention. **Off stops new collection and interrupts
unfinished saved entries; it keeps existing history.** Read, rate, edit a
reference, export and explicitly delete saved entries even while Off. This is
the owner's deliberate retention exception to the earlier switch semantics.
There is no automatic count, age or aggregate byte eviction.

## Everyday feedback

Open **Hex+ → Show dictation log**. The list uses metadata, a 120-character
preview and All / Unrated / Problems filters. Leading Good and trailing Problem
swipes have explicit VoiceOver equivalents. The detail begins with Good and
Problem buttons. Problem saves immediately; optional issue choices can follow:
`misheard`, `missing_or_shortened`, `unwanted_rewrite`, `punctuation_formatting`,
`vocabulary_name`, `too_slow`, `other`. Rating does not require an editor.

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

`Application Support/HexPlus/DictationLog/v2/entries/<UUID>.json` is the source of
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

Schema-1 `HexPlus/dictation-log.json` migrates independently of collection being
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
  "format": "hexplus.dictation-log",
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
