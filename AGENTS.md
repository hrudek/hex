<!-- tallow -->
# Typr agent guide

Typr is a standalone iPhone dictation keyboard. Read [TYPR.md](TYPR.md) first
(process, switches and feature table), then [ios/README.md](ios/README.md)
(architecture and proof limits), and [PORTS.md](PORTS.md) before adopting code.

## One worktree per development task

- Before a new feature, bug fix or refactor, fetch `origin` successfully and
  create a task-specific branch and Git worktree from the freshly fetched
  `origin/main`, never from a possibly stale local `main`, checkout, tag or
  cached remote-tracking ref. Only an explicit owner request permits another
  base; fetch and verify that base too.
- Keep worktrees as sibling directories under the canonical repository root
  containing `.bare/`. Do not develop directly on `main`.
- Run `git worktree list` and check the relevant worktree's status before
  making changes. Never overwrite or move another task's uncommitted work.
- Resume an existing task in its own worktree; a new session does not require
  another worktree. Run edits, builds and tests there.

### Mandatory fresh-base gate

Before the first edit of a new task, and before resuming development in an
existing task worktree (including a new session):

1. Inspect `git worktree list` and `git status --short --branch` in the relevant
   worktree. Preserve all existing work; never reset or discard it to update.
2. Run `git fetch --prune origin`. If the fetch fails or `origin/main` cannot
   be resolved, **stop**: do not develop from the last cached state. Resolve
   access/connectivity first or ask the owner how to proceed.
3. For a new task, create the branch/worktree explicitly from `origin/main`:

   ```sh
   # Run from the canonical repository root containing .bare/.
   # Replace <task> and <branch> with new, task-specific names.
   git worktree add --no-track -b <branch> <task> origin/main
   ```

   An existing branch is not a fresh base just because a worktree helper
   reused it. For a resumed task whose branch lacks the fetched `origin/main`,
   safely preserve any uncommitted work, merge `origin/main` into the task
   branch and resolve conflicts before continuing. Do not rewrite shared
   history or overwrite another task's work. If safe integration is blocked,
   stop and ask the owner.
4. In the task worktree, require this command to succeed before editing:

   ```sh
   git merge-base --is-ancestor origin/main HEAD
   ```

   For a newly created task branch, also verify that `git rev-parse HEAD` and
   `git rev-parse origin/main` match exactly before the first task commit.
   Record the fetched base SHA in the handover/PR. For an explicitly approved
   alternate base, use its freshly fetched ref in these checks instead.

Repeat the fetch and ancestry check before handing over or updating a PR;
merge newer `origin/main` commits if necessary and rerun affected checks.
A local branch name or a successful fetch alone is not proof that the task
contains the current remote base. These are mandatory agent process gates,
not a claim of server-side branch protection.

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
