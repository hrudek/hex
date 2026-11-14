# Local usage statistics

The data layer collects new, text-free measurements. It does not reconstruct history
from the learning model, diagnostics or transcript archive. There is not yet a
Statistics screen. Learning and technical-counter resets do not reset usage data.

## Populations

- **Direct graphemes:** deliberate character, accent, space (including Typr-key space)
  and Return insertions, using Swift `String.count`. A rollover commit or 123-slide
  is one insertion. Double-space period is one deliberate space, not two generated
  characters. Autocorrection replacement text is not additional direct input.
- **Delete actions:** a delete, undo, word-delete or repeat tick is one action. An
  accelerated tick can perform two proxy deletions but is still one action. Undo
  has no positive graphemes and does not reopen a previously counted word.
- **Suggestions:** only accepted, ownership-validated chips. Their output earns word
  completions, not invented manual keystrokes. A boundary chip does not count an
  already completed predecessor again. Refused/stale chips count nothing.
- **Completed words:** session-owned alphanumeric runs, with apostrophes/typographic
  apostrophes/hyphens allowed internally. A separator completes the word. An actual
  autocorrection can complete multiple output words. Unfinished words are not
  counted on dismissal. A bounded RAM-only stack stores character classes, not
  text; tokens beyond 4,096 characters receive no completion credit until a boundary.
  These are output events, not unique words or a document word count.
- **Active typing:** positive monotonic intervals of at most four seconds between
  adjacent direct or delete actions. Exactly four seconds counts. The first action
  after a boundary has no interval and no timed graphemes. A delete endpoint can
  add time, but no positive timed graphemes. Suggestions break the timing chain.
  Unknown/unreported host context changes, cursor/field/layout changes and lifecycle
  interruption end the measurement session. Paste and dictation insertion are not
  typing. A bounded RAM-only context-ownership check belongs to the engine; host
  text is never passed to the statistics store.
- **Successful dictations:** count once after the last cancellation/generation fence
  and formatting, independently of transcript-history settings. Word count uses raw
  recognition before vocabulary/style/cleanup; seconds use stopped capture duration,
  not ASR/cleanup time. Empty recognition/delivery, errors, cancellation, stale jobs
  and captures below the controller's minimum duration do not count. Successful
  punctuation-only output has zero words but still counts as a dictation. The capture
  token is allocated at capture start, not handoff, consumption or history insertion.

Typing WPM is `timed graphemes * 12 / active seconds`. Dictation WPM is
`recognized words * 60 / successful recording seconds`. Both are unavailable until
60 corresponding seconds. Summaries use summed populations and times, never an
unweighted average of daily speeds. Word completions remain separate from WPM's
five-character standard words.

## Storage and reset

`Typr/Keyboard/statistics-v1.json` is a separate schema-1 envelope in the protected
App Group directory. `statistics.lock` serializes app/extension read-modify-write
transactions; each transaction loads the latest file and applies a delta. Writes
are atomic, protected until first unlock, excluded from backups and synchronized.
Regular files/no symlinks and a 2 MiB ceiling are checked before decoding and before
writing. Invalid, oversized or unavailable data throws an error, not an empty-history
snapshot. A future schema is never overwritten, even by reset.

A snapshot contains:

- A separate UUID reset generation, collection start and fixed Gregorian time zone.
- At most 90 calendar-day aggregates including today. Calendar arithmetic handles
  DST; the zone is fixed at creation/reset, not changed during travel. A typing
  interval and its timed graphemes belong to the endpoint day. A dictation belongs
  to its success day. Future/out-of-retention days are omitted on read and pruned on
  mutation; a backward wall-clock jump cannot create unlimited days or negative time.
- At most four measured Heat layouts, each a fixed 64 × 24 grid of saturating counters.
- At most 16 live writer watermarks and 2,048 capture receipts. Receipt validity is
  at most 24 hours **from writer/capture start**, not last retry. Expired/future-started
  operations and full live receipt tables are explicitly rejected, never accepted
  by forgetting deduplication state. Long-lived writers rotate after 23 hours once
  all batches have been acknowledged. Counter/duration ceilings are 10¹².

The keyboard batches for about one second and flushes at its existing learning
lifecycle hooks. RAM-only pending counts can be lost on process death; this is not
crash-proof accounting. A frozen batch keeps exactly the same writer/sequence and
contents on retry, while newer events accumulate separately. Capture retries retain
only token/count/duration in RAM, and retry at the next success or capture start.
Storage errors remain available on the session/recorder. Collection without usable
App Group access is unavailable, not silently reported as zero. Production keyboard
persistence follows the existing Full Access policy; simulator persistence is only
used by explicitly injected test stores. No network, speech or microphone access is
added to the keyboard.

`UsageStatisticsStore.snapshot()` returns a value snapshot (creating the initial
empty envelope if absent); subsequent reads do not rewrite it. `observe` returns an
invalidatable Darwin-notification observer; views should also refresh on activation.
The keyboard observes generation changes and checks again when configuring a field.
`reset()` atomically replaces the envelope/generation, repairing corrupt/oversized
v1 data. Old pending batches and captures cannot revive pre-reset measurements.
Learning files, imports and technical counters are unchanged. No usage-reset button
is exposed until there is a usable Statistics screen.

## Heat, saved model and recent labels are different

Measured Heat accepts only finite, on-board, unambiguous character release points
from the letter/text layout, with zero horizontal inset. Rollover-held commits,
accent menus, 123-slide, reattribution, slid/invalidated geometry and unsupported
fields/layers do not create Heat. There is no coordinate clamping. Geometry version 1
normalizes over the actual board height/width and separates orientation, rounded
8-point width bucket, strip and globe configuration. Nonzero-inset layouts are
explicitly unsupported rather than silently mixed. At most four most-recently-used
layouts are stored; old Heat is not historical word/tap lifetime data.

Saved `PersonalTypingModel` means/covariances are unchanged. Estimated on-target
probability must be calculated separately using real geometry in the presentation
phase. Heat is neither intended-key evidence nor measured accuracy.

The model calls the optional accepted-label hook only after all existing learning,
layout, lowercase-key, finite-coordinate, normalized-distance and outlier validation
has passed and the model has accepted the label. The learning session forwards it;
no unaligned raw word evidence is persisted. The keyboard keeps at most 128 recent
labeled points **in RAM only**, clearing them on session/layout changes, learning
switch/reset/deferred model reload and usage reset. These are labels accepted by the
learning pipeline, not independent ground truth. Do not derive a trend by comparing
them to the saved model or by hit-testing a key against its own assigned tap.

## Verification

Simulator test sources: `UsageStatisticsTests`, `UsageStatisticsStoreTests`,
`UsageStatisticsEngineTests`, plus usage integration cases in
`DictationLogControllerTests`. Targeted macOS execution:

```sh
bash .github/typr/agent-test.sh TyprTests/UsageStatisticsTests,TyprTests/UsageStatisticsStoreTests,TyprTests/UsageStatisticsEngineTests,TyprTests/DictationLogControllerTests
```

Linux checks and a tree-sitter syntax pass do not compile Swift or execute these
XCTests. Cross-process lock contention and additive stale-reader tests are written;
actual simultaneous app/extension writes, kill/relaunch, I/O failure after rename,
latency, memory and privacy behavior still require simulator/device verification.
