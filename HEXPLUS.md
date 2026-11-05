# Hex+

`hrudek/hex` is a personal fork of [anomalyco/hex](https://github.com/anomalyco/hex)
for the iPhone app. Branch `hex-plus` (the fork's default branch) is upstream's
`dev` plus Hex+'s own commits on top. Upstream takes no pull requests, so
features live here as ordinary commits.

## Files Hex+ owns

Upstream never touches these, and the sync refuses upstream commits that would:

- `HEXPLUS.md`
- `.github/hexplus/`: identity (`app.json`), CI scripts, their tests
- `.github/workflows/hexplus-sync.yml`, `.github/workflows/hexplus-ios.yml`

Every other upstream workflow is disabled in this fork, and the sync disables
any new one it brings in.

## Identity

`app.json` gives the iPhone build Hex+'s identity: `com.bearylabs.hex` (+
`.keyboard`, `.widgets`), App Group `group.com.bearylabs.hex`, URL scheme
`bearylabs-hex`, home-screen name **Hex+**. These are Apple identifiers
registered for team `2ZNGF24932`; they are not tied to the GitHub account name.

`identity.py` rewrites upstream's identity (Kit's team, `com.kitlangton.hex.mobile`)
in the CI checkout only, so `hex-plus` carries no identity commit that would
conflict on every sync. It fails closed when upstream's identity changes.

## Automation

```ts
hexplus-sync (daily 04:23 UTC, or by hand)
├─ rebase hex-plus onto anomalyco/hex dev → force-push (SYNC_TOKEN)
├─ conflict or upstream touching Hex+ files → issue "Hex+ sync needs you"
└─ the push triggers ↓

hexplus-ios (push to hex-plus, or by hand)
├─ Decide: did ios/, its icon/fixtures or Hex+'s scripts change? no → done
├─ Simulator tests          (no secrets)
├─ Unsigned archive         (no secrets, age-encrypted artifact)
└─ Sign (by hand only)      ad-hoc | testflight, environment approval required
```

## Everyday commands

```sh
# Build and sign for the iPhone (approve the environment on the run page):
gh workflow run hexplus-ios.yml -R hrudek/hex -f distribution=ad-hoc
gh run watch -R hrudek/hex RUN_ID
gh run download -R hrudek/hex RUN_ID --pattern 'hexplus-ad-hoc-*' --dir downloads/hexplus-RUN_ID
age --decrypt --identity ~/.local/share/ios-build-signing/artifacts.agekey \
  --output downloads/hexplus-RUN_ID/HEX.ipa downloads/hexplus-RUN_ID/HEX.ipa.age
~/dev/apple-dev-setup/iphone-wifi install "$PWD/downloads/hexplus-RUN_ID/HEX.ipa"

# Sync by hand, or resolve a conflict the daily sync reported:
git fetch origin && git fetch upstream
git switch hex-plus && git merge --ff-only origin/hex-plus
git rebase upstream/dev          # fix conflicts, git rebase --continue
git push --force-with-lease

# Check the CI scripts on Linux:
python3 -m unittest discover -s .github/hexplus/tests
```

If GitHub's macOS runners are short on capacity (jobs cancelled with "not acquired by
Runner"), rerun later or set the repository variable `MACOS_RUNNER` to another
image label with Xcode 26.2+ (default `macos-26`).

Remotes: `origin` = `hrudek/hex`, `upstream` = `anomalyco/hex` (push disabled).

## Features on top of upstream

| Feature | Commits | Notes |
| --- | --- | --- |
| _none yet_ | | |
