# Adopted sources

Hex+ is a standalone iPhone project, not an automatically synchronized fork.
The local annotated split tags identify the inherited upstream tip
(`split/hex-upstream`) and the last pre-split project state (`split/base`).
Tags are provenance anchors, not release tags.

| Feature | Source (repo) | Paths there | Last adopted commit | Files here | License |
| --- | --- | --- | --- | --- | --- |
| Hex iPhone app (base) | [anomalyco/hex](https://github.com/anomalyco/hex) (`dev`) | `ios/`, `app/AppIcon.icon/`, `tests/fixtures/vocabulary/audio/term-hex-1.wav` | `cae389a833178c5e104e6d00db894078afc29ea0` (`split/hex-upstream`) | `ios/` except Hex+-specific files in the [feature table](HEXPLUS.md#hex-features); icon at `ios/AppIcon.icon/`, WAV at `ios/TestFixtures/term-hex-1.wav` and [provenance README](ios/TestFixtures/README.md) | MIT, © Christopher Langton; [LICENSE](LICENSE) |
| iOS 26 full keyboard parity, 3-slot suggestions and cautious autocorrect | [anomalyco/hex PR #938](https://github.com/anomalyco/hex/pull/938), not merged upstream at split | 17 iOS paths listed below | `9029d2bcafb5504019d9ad979fa3883dd1659161`, via `ad1a58f4` / [hrudek/hex #28](https://github.com/hrudek/hex/pull/28) | The same 17 paths, with Hex+ conflict resolution and subsequent changes | MIT, © Christopher Langton |

## Carried keyboard PR paths

The second row's source and destination paths are:
`ios/HEXKeyboard/KeyboardViewController.swift`, `ios/HEXMobile/ExperimentsCard.swift`, `ios/HEXMobile/FullKeyboardSnapshotStage.swift`, `ios/HEXMobile/KeyboardPreviewHost.swift`, `ios/HEXMobileTests/AutocorrectEngineTests.swift`, `ios/HEXMobileTests/FullKeyboardEngineTests.swift`, `ios/HEXMobileTests/KeyboardLayoutTests.swift`, `ios/HEXShared/DotScope.swift`, `ios/HEXShared/FullKeyboard/AccentPicker.swift`, `ios/HEXShared/FullKeyboard/AutocorrectEngine.swift`, `ios/HEXShared/FullKeyboard/FullKeyboardEngine.swift`, `ios/HEXShared/FullKeyboard/FullKeyboardPalette.swift`, `ios/HEXShared/FullKeyboard/FullKeyboardView.swift`, `ios/HEXShared/FullKeyboard/HexKeyViews.swift`, `ios/HEXShared/FullKeyboard/KeyboardKeyPlaneView.swift`, `ios/HEXShared/FullKeyboard/KeyboardLayout.swift`, `ios/HEXShared/FullKeyboard/KeyboardStripView.swift`.

This list was derived with `git diff --name-only bbab250d^ 9029d2bc -- ios/`.
An upstream PR's status and head may later change; the adopted commit above
is the reference, not the current PR head.

At the split analysis, upstream `dev` was 11 commits ahead at `350c42db`;
none of those commits touched `ios/`. This is a historical observation,
not a claim about the current remote tip.

`src/…` paths in comments under `ios/` refer to `anomalyco/hex` at `cae389a8`.
In particular, unchanged comments in `HEXShared/DotScope.swift` and
`DotScopeShader.metal` name the desktop spring, scope and shader sources.
Some comments retain pre-reorganization names: at that commit,
`src/spring.rs`, `src/dot_scope.rs` and `src/dot_scope/scope.rs` correspond to
`src/rune_hud/spring.rs`, `src/rune_hud/dot_scope.rs` and
`src/rune_hud/dot_scope/scope.rs`. `src/rune_hud.wgsl` still has that exact path.
The old names are not literal file locations at the split commit; no Swift or
Metal comment was changed as part of the standalone split.
The scope also credits OpenCode's iOS port (`DotScopeView.swift`,
`DictationScopeBar`, `DotScopeShaders.metal`) from
[anomalyco/opencode](https://github.com/anomalyco/opencode), MIT, inherited
through the Hex base. Those references are provenance, not local dependencies.

`ios/appstoreconnect.json` and `ios/ExportOptions.plist` are inherited
configuration, retained unchanged and unused by Hex+ CI, which uses
`.github/hexplus/` for configuration and export options.

## How to adopt changes

1. Configure read-only source remotes. Use the repository owner's lowercase
   name (for example `anomalyco` or `avgvstvs96`); `origin` stays `hrudek/hex`.
   These are local setup commands, not automatic automation:

   ```sh
   git remote add anomalyco https://github.com/anomalyco/hex.git
   git remote set-url --push anomalyco DISABLED
   git fetch anomalyco
   git log cae389a833178c5e104e6d00db894078afc29ea0..anomalyco/dev -- ios/
   git diff cae389a833178c5e104e6d00db894078afc29ea0..anomalyco/dev -- ios/

   git remote add avgvstvs96 https://github.com/AVGVSTVS96/iikb.git
   git remote set-url --push avgvstvs96 DISABLED
   git fetch avgvstvs96
   ```

   If a remote already exists, verify its URL instead of adding it again.
   Start each comparison at that feature's saved commit and restrict it to
   its source paths; include icon/test resource paths when they are relevant.
2. Classify each candidate as a bug fix, improvement, irrelevant change, or
   dependent change (requires another adoption or desktop code). The owner
   decides what to bring over; there is no bulk merge or daily sync.
3. Translate foreign code into the project's current architecture; do not
   blindly copy it. Inspect the exact source commit, dependencies, privacy
   contract and tests. Check the license first: **GPL, AGPL and LGPL are
   prohibited**. Update [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for
   new dependencies or attributions and preserve required license notices.
4. Use one cohesive PR per adoption, with tests and honest verification limits.
   Update this table in the same PR (source paths, last adopted commit,
   destination files and license). A normal adoption needs no switch; only
   a genuine experiment or owner-requested switch follows [HEXPLUS.md](HEXPLUS.md).
