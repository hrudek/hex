# Local dictation archive import and report (C)

Dependency-free **Python 3.10+ on Linux/macOS** (`sqlite3` and `fcntl` from the
standard library). This is an explicit desktop command, not an iPhone feature or
background service: no network, uploads, inference, audio, paid evaluation, replay,
automatic regression comparison, package installation or app configuration changes.
Nothing under this directory is added to Xcode targets or `project.yml`.

## Use

Export JSON from Typr › Dictation log, then explicitly choose a private,
**non-synced directory outside every Git checkout**, including linked worktrees:

```sh
python3 ios/tools/dictation_log/cli.py --store "$HOME/.local/share/typr-feedback" import /path/to/export.json
python3 ios/tools/dictation_log/cli.py --store "$HOME/.local/share/typr-feedback" report
python3 ios/tools/dictation_log/cli.py --store "$HOME/.local/share/typr-feedback" report --json
# Deliberately exposes private stages/reference/note/vocabulary on stdout:
python3 ios/tools/dictation_log/cli.py --store "$HOME/.local/share/typr-feedback" report --json --show-text
```

`--store` is required; there is no automatic data discovery. Paths are resolved
through symlinks, then all ancestors are checked for `.git` directories **or
files**. The tool refuses a checkout rather than risking a committed dataset.
An existing nonempty directory must already contain a recognized Typr store; otherwise
it is rejected **before chmod or file creation**, so a mistaken `--store ~` or
Documents path is untouched. New/empty directories are accepted for import.
Report refuses a nonexistent store instead of silently creating an empty one.
Exit status: 0 success (including disclosed conflicts/skipped future entries),
2 invalid input, unsupported format, busy store or local I/O failure. Warnings
and counters must be read; success is not proof of a complete export.

Synthetic smoke check (contains only invented sentences and vocabulary):

```sh
STORE=$(mktemp -d /tmp/typr-feedback-example.XXXXXX)
python3 ios/tools/dictation_log/cli.py --store "$STORE" import ios/tools/dictation_log/examples/synthetic.json --json
python3 ios/tools/dictation_log/cli.py --store "$STORE" report --json
# Exactly two records: good=1, bad=1, references=1, Good without reference=1;
# final-output/reference word edit rate=1/3 for one eligible pair, NOT ASR WER.
# Reimport: inserted=0, unchanged=2, no duplicate records.
python3 ios/tools/dictation_log/cli.py --store "$STORE" import ios/tools/dictation_log/examples/synthetic.json --json
```

## Storage, privacy and deletion

- `archive.sqlite3`: private store, format marker and user_version=1. SQLite
  `synchronous=FULL`, rollback journal and transactions provide whole-import
  commit/rollback. Identity is `(archiveID, entryID)`, not just entry UUID.
- `exports/<SHA256>.json`: **byte-exact copies of each accepted input**. These
  duplicate all private text, settings and vocabulary, even entries skipped as
  unsupported. They are not anonymous or encrypted. Only synthetic examples
  belong in Git. A failed transaction can leave an unreferenced private raw blob;
  it never replaces previously committed records. No automatic cleanup removes
  potential evidence.
- A per-store random 32-byte HMAC key lives in private SQLite metadata. Both the
  vocabulary component and full canonical settings use domain-separated
  HMAC-SHA256 (16 hex characters displayed). This resists dictionary guessing and
  cross-store comparison of short vocabularies. **HMAC is not encryption**: the
  database/raw exports still contain plaintext. The key is created once; an
  invalid/missing key is an error, never silently replaced.
- Store/evidence directories are 0700; database, raw exports, temporary files,
  lock and SQLite side files are 0600. umask 077 covers their creation and is
  restored when the operation closes. Atomic raw writes use exclusive private
  temporary files, flush/fsync, replace and directory fsync. A cross-process
  nonblocking `flock` serializes commands, timing out after two seconds; a crash
  releases the lock. A read-only input export is never modified.
- No application-level encryption, secure SSD erasure or OS backup/sync control.
  Use a private non-synced location and your OS's disk encryption. `secure_delete`
  does not guarantee erasure from SSD snapshots, backups or already shared files.

There is intentionally no per-entry forget that would leave its text in raw
snapshots. To remove **everything**, stop commands, verify the exact store path,
and delete that directory and all its contents, e.g.:

```sh
# DESTRUCTIVE: substitute and verify your actual local store path first.
rm -rf -- /your/verified/private/typr-feedback-store
```

This removes SQLite, journals, HMAC key and **all** raw copies/orphans in that
store. It does not delete the original export, iPhone Files copies, the iPhone
archive, backups or files already shared with another recipient. Never point this
command at the repository or a directory containing other work.

## Import contract and conservative merge

Supports envelope `format=typr.dictation-log`, `exportVersion=1`,
`dateEncoding=ISO-8601 UTC`, UTC exported/context/order dates, UUIDs, source
schema 1/2, nonnegative finite timings, positive integer revisions and bounded
4000-UTF-8-byte text fields with explicit truncation/original-byte evidence.
Input is limited to **512 MiB** and parsed in memory; memory can be several times
input size. Oversized input fails explicitly, never evicts stored data. Ask for
smaller/single-entry exports if needed. SQLite avoids rewriting an ever-growing
whole-store JSON file; reports currently collect retained rows in memory.

- Missing schema-1 revision means 1. Higher revision replaces the **whole** entry;
  lower revisions never replace it. Same revision + canonical equal JSON is a
  no-op. Same revision + different contents warns and keeps the current entry.
  No field-level splicing of old stages with new ratings/reference.
- `ratingOrder`/`referenceOrder` are preserved, **not used to merge snapshots**.
  Native export v1's ISO-8601 encoding rounds dates to whole seconds; ordering
  timestamps alone cannot reconstruct sub-second events. Revision controls the
  complete source snapshot. This tool does not change app date precision.
- Unknown envelope format/export version fails the entire input, no partial
  commit. Invalid known-entry fields, duplicate JSON keys, non-finite numbers and
  truncated JSON fail before store mutation. Diagnostics name only fixed fields
  or line/column, never offending imported values. CLI I/O errors are generic.
- Unknown entry schema is skipped with a warning, its untouched bytes retained
  in the raw export. Unknown rating/category codes stay in the stored source and
  are counted separately as `unknown:hmac:<digest>`; they are never treated as
  good/bad or printed as arbitrary private strings.
- Source `unreadableFiles` and `legacyMigrationPending` are surfaced on import
  and report, including latest-source counts and historical evidence warnings.
- Export v1 currently **does not encode single-entry versus whole-archive
  scope**. Scope remains **unknown**, even with many entries. A one-entry file
  gets an explicit single-entry/small-archive ambiguity warning. Only an explicit
  future `scope: "all"` field is read as all; no app protocol change is included.
  `absentFromLatestImport` is observation only, **never deletion evidence**.
  `absentFromLastWholeExport` is null without such explicit whole-export evidence.
  Import order, not exportedAt, chooses the last observed import; reimporting
  identical bytes does not make an old file newest. Absent records are never
  deleted. A cleared app archive's new archiveID starts a separate lineage.

## Reports and proof limits

Default human/JSON reports omit all dictation stages, reference/note text and
vocabulary. Human output omits entry/archive IDs too. `--show-text` is the only
plaintext mode (and may be combined with JSON). Treat its stdout/redirections as
private. Default reports are still personal metadata, not safe public telemetry.

Counts separate good/bad/unrated/unknown, known-rating coverage, supplied versus
complete references, Good without reference and category counts. Missing timings
remain missing (not zero); report each timing's count, missing count and median.
Groups use sanitized build labels and canonical HMAC settings fingerprints over
language, engine, style, cleanup path, all three AI/vocabulary flags, active
vocabulary snapshot+truncation, prompt revision and guard revision. Missing/null
configuration stays **unknown**, never false/disabled. Unknown/truncated source
evidence cannot establish identical real settings. Fingerprints are comparable
**only within this store**; no cross-store equivalence is claimed.

Each group with n < 5 says **too few data**. No best-setting rankings, statistical
significance, causal claims, model accuracy or regression verdicts. Feedback is
self-selected and confounded by task, speaker, setting changes and app build.

`final-output→reference word edit rate` uses only status `finished`, explicit
complete finalText and explicit complete expectedText. Good alone is **not** a
reference. Empty reference, missing/truncated stages and unfinished jobs are
counted as exclusions. Normalize NFC; split on Unicode whitespace; preserve case
and punctuation (no alternative normalization silently removes errors). Compute
Levenshtein token insertions/deletions/substitutions divided by reference token
count; show pair count, median and pooled rate. At most **1000 tokens per side**
(one million DP cells per pair, linear row memory); larger pairs are excluded
and counted. This may exceed 1. It is **not ASR WER**, semantic correctness or
audio-grounded quality: the reference is intended final text after transformations.

## Verification

```sh
python3 -m unittest discover -s ios/tools/dictation_log/tests -v
```

Synthetic tests cover revisions/conflicts/lineage, absence and unknown scope,
raw-byte preservation and partial-envelope warnings, unsupported versions,
validation/corruption/size bounds, Git directory/file/symlink rejection, atomic
blob failure, SQLite transaction fault injection, private permissions including a
live journal, HMAC stability/separation, complete config fingerprint inputs,
unknown-versus-false, privacy in stdout/stderr, reference eligibility and exact
NFC/punctuation/token-boundary metrics. The CLI example above is a separate local
smoke check, not native device or model-quality proof.

Observed locally: Python 3.13 on Linux, 24/24 tests passing plus explicit
synthetic CLI import/report/reimport. **Existing CI does not automatically run
these Python tests.** No workflow changes were authorized or made. Native archive
CI still guards the unchanged app; no new native simulator/UI test or screenshot
is appropriate for this standalone tool. Exact final runs are recorded on the PR.
