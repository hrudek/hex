<!-- tallow -->
# Typr agent guide

Typr is a standalone iPhone dictation keyboard. Read [TYPR.md](TYPR.md) first
(process, switches and feature table), then [ios/README.md](ios/README.md)
(architecture and proof limits), and [PORTS.md](PORTS.md) before adopting code.

## One worktree per development task

- Before a new feature, bug fix or refactor, run `git fetch --prune origin`
  successfully, then create a task-specific branch and Git worktree from the
  freshly fetched `origin/main`, never from local `main` or an old checkout.
  If fetching fails, stop rather than use cached refs. Another base requires
  an explicit owner request.
- Keep worktrees as sibling directories under the canonical repository root
  containing `.bare/`. Do not develop directly on `main`.
- Run `git worktree list` and check the relevant worktree's status before
  making changes. Never overwrite or move another task's uncommitted work.
- Resume an existing task in its own worktree; a new session does not require
  another worktree. Before continuing, fetch `origin` successfully and merge
  `origin/main` if `git merge-base --is-ancestor origin/main HEAD` fails;
  preserve uncommitted work and resolve conflicts before editing.
  Run edits, builds and tests there.

## Layout and checks

- `ios/`: XcodeGen's `project.yml`; app `Typr`, keyboard `TyprKeyboard`,
  widgets `TyprWidgets`, shared `TyprShared` / `TyprActivity`, tests `TyprTests`,
  app icon and test fixtures.
- `ios/tools/`: explicit, offline Python dictation-log tooling.
- `.github/typr/`: build, test, archive, signing and CI helper scripts.
- `.github/workflows/typr-*.yml`: CI, review, TestFlight/ad-hoc, retry,
  infra-label recheck and weekly status.

All repository paths belong to this project. Changes anywhere under `.github/`
need the `infra` PR label. Keep PRs cohesive, update affected documentation and
the feature table for feature changes, and follow the owner's merge instructions.
Normal features and bug fixes need no switch; real experiments or owner-requested
switches follow the complete rules in [TYPR.md](TYPR.md).

On macOS:

```sh
bash .github/typr/agent-test.sh
bash .github/typr/agent-test.sh TyprTests/DictationControllerTests
```

On Linux (no Xcode build or simulator proof):

```sh
python3 -m unittest discover -s .github/typr/tests -v
python3 -m unittest discover -s ios/tools/dictation_log/tests -v
for s in .github/typr/*.sh; do bash -n "$s"; done
shellcheck -x -P .github/typr .github/typr/*.sh
mise x actionlint@1.7.11 -- actionlint -ignore SC2016 -ignore SC2129 .github/workflows/*.yml
git diff --check
```

## Implementation and privacy

- Keep modules deep: callers should not coordinate audio formats, capture
  lifecycle or serialization. Do not introduce hypothetical platform/plugin
  seams; generalize only for two real adapters or a current test requirement.
- Distinguish implemented behavior, available checks and observed verification.
  An existing test is not a passing run; a simulator is not a real iPhone.
  Report exact checks and failures, and what remains unverified.
- Use sentence case and the product name “Typr” in UI copy.
- The keyboard never accesses the microphone, speech model or network.
- Do not persist captured audio by default. The owner-approved durable
  Dictation log exception is documented in [ios/DICTATION_LOG.md](ios/DICTATION_LOG.md).
  Keep transcripts, log exports and private tool stores out of Git and public
  issues; explicit offline tooling must not collect app/runtime data by itself.
- Keep Typr’s committed identity consistent with `.github/typr/app.json`.
  `identity.py` validates it without rewriting source. Bundle IDs, App Group,
  URL scheme, signing and secrets must not change incidentally.
- Adopt third-party changes only through [PORTS.md](PORTS.md), with owner
  approval, tests, provenance and license review. GPL, AGPL and LGPL code is
  not permitted.
