# Typr agent guide

Typr is a standalone iPhone dictation keyboard, based on Hex (MIT). This file
holds every agent rule. Read further only when the task needs it:

- App architecture, switches, privacy rules, proof limits: [ios/README.md](ios/README.md)
- CI, review, auto-merge, signing, owner commands: [.github/typr/README.md](.github/typr/README.md)
- Third-party licenses: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)

## Worktrees

- Before a new feature, fix or refactor, run `git fetch --prune origin`
  successfully, then create `feature/<name>` or `fix/<name>` and a Git worktree
  from the freshly fetched `origin/main`, never from local `main` or an old
  checkout. If fetching fails, stop. Another base needs an explicit owner request.
- Worktrees are sibling directories under the repository root containing `.bare/`.
  Do not develop on `main`. Run `git worktree list` and check status first; never
  overwrite or move another task's uncommitted work.
- Resume a task in its own worktree. Fetch `origin` first and merge `origin/main`
  if `git merge-base --is-ancestor origin/main HEAD` fails; preserve uncommitted
  work and resolve conflicts before editing. Resolve PR merge conflicts the same way.

## Issues and PRs

- Work is PR-first: PR to `main`, label `feature` (fix PRs: `fix/<name>`), squash
  merge. No issue is required. Use an existing relevant issue; create one only for
  deferred/unresolved work, multi-PR coordination or on owner request. Issues are
  notes: no agent starts from an issue or `@claude` comment. `Closes #N` only when
  the PR fully resolves it. The pinned status issue is unaffected.
- Keep each PR cohesive and independently reviewable; a large feature may span PRs.
- Changes under `.github/` need the `infra` label (CI's scope check fails otherwise).
- The PR description is the durable record: goal, agreed user-visible behavior,
  decisions and reasons, changed files, what was tested and what was not (anything
  only a real iPhone proves). Carry outcomes from the conversation into it; update
  it when scope changes. List affected screenshot scenes in a `Screenshots:` line.
- Update affected documentation in the same PR. Keep the switch list in
  ios/README.md current when a switch is added or removed.
- After pushing, read the latest **Typr review** comment, fix every numbered
  finding, push and wait for the next verdict. `⚠️ NO RESULT`: re-run the failed
  job once, then tell the owner. Merging is automatic once required checks pass.
- Removing a feature: prefer GitHub's **Revert** of its PR(s) over rewriting code;
  if the revert conflicts, remove it while preserving dependent behavior.

## Switches

- Bug fixes and normal features get no switch. Add one only for a genuine
  experiment or on owner request. New switches are on by default; off preserves
  the previous behavior exactly. Exceptions need an owner decision.
- Switches live with related settings (**Keyboard**, **AI & vocabulary**,
  **History & feedback**). Values are stored in `TyprShared/TyprSettings.swift`
  (App Group); controls live in `Typr/SettingsPreferences.swift` and
  `Typr/KeyboardSettingsCard.swift`. Never put Typr values in `FullKeyboardSettings.swift`.
- Follow-ups use the feature's existing switch. Making a feature permanent removes
  the switch and the old code path in a PR.

## Tests and honesty

- Every feature adds simulator tests in `ios/TyprTests`. A local simulator run is
  not required before pushing; CI tests after merge to `main`. Run targeted tests
  when debugging or when the owner asks.
- Distinguish implemented behavior, available checks and observed verification.
  An existing test is not a passing run; a simulator is not a real iPhone.
  Report exact checks, failures and what remains unverified.

On macOS:

```sh
bash .github/typr/agent-test.sh [Target/Class,…]
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

- Keep modules deep: callers do not coordinate audio formats, capture lifecycle or
  serialization. No hypothetical platform/plugin seams; generalize only for two real
  adapters or a current test requirement.
- Runtime, storage or privacy changes must follow the privacy rules in
  [ios/README.md](ios/README.md#privacy-and-storage). The keyboard never accesses the
  microphone, speech model or network. Captured audio is not persisted.
- Keep transcripts, log exports and private tool stores out of Git and public issues.
  Offline tooling must not collect app/runtime data by itself.
- UI copy: sentence case, product name “Typr”.
- Identity is committed in `ios/` and mirrored in `.github/typr/app.json`;
  `identity.py` validates without rewriting. Bundle IDs, App Group, URL scheme,
  signing and secrets must not change incidentally.

## Third-party code

Adopt external code only with owner approval. Check the license first: GPL, AGPL and
LGPL are not permitted. Translate the needed behavior rather than copying files,
inspect its dependencies and privacy impact, and add tests. In the same PR, add the
license notice plus source URL and immutable revision (commit, or release/snapshot
with hash) to [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and describe the
provenance (upstream paths, what was taken) in the PR.
