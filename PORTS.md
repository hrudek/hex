# Adopted sources

Typr is a standalone iPhone dictation keyboard. It is based on Hex by Kit
Langton (https://github.com/kitlangton/hex / https://github.com/anomalyco/hex),
MIT; [LICENSE](LICENSE) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)
preserve attribution. The commits and source links below are provenance, not
sync instructions or local dependencies.

| Feature | Source (repo) | Paths there | Last adopted commit | Files here | License |
| --- | --- | --- | --- | --- | --- |
| Hex iPhone app (base) | [anomalyco/hex](https://github.com/anomalyco/hex) (`dev`) | `ios/`, `app/AppIcon.icon/`, `tests/fixtures/vocabulary/audio/term-hex-1.wav` | `cae389a833178c5e104e6d00db894078afc29ea0` (`split/hex-upstream`) | `ios/` except Typr-specific files in the [feature table](TYPR.md#typr-features); icon at `ios/AppIcon.icon/`, WAV at `ios/TestFixtures/term-hex-1.wav` and [provenance README](ios/TestFixtures/README.md) | MIT, © Christopher Langton; [LICENSE](LICENSE) |
| iOS 26 full keyboard parity, 3-slot suggestions and cautious autocorrect | [anomalyco/hex PR #938](https://github.com/anomalyco/hex/pull/938), not merged upstream at split | 17 iOS paths listed below | `9029d2bcafb5504019d9ad979fa3883dd1659161`, via `ad1a58f4` / [hrudek/typr #28](https://github.com/hrudek/typr/pull/28) | The same 17 paths, with Typr conflict resolution and subsequent changes | MIT, © Christopher Langton |
| Automatic return to the host app: host detection via UIKit's keyboard arbiter, return by bundle ID | [AVGVSTVS96/iikb](https://github.com/AVGVSTVS96/iikb) (`main`) | `Packages/KeyboardModules/Sources/FullKeyboard/KeyboardHost.swift`, `Packages/KeyboardModules/Sources/KeyboardArbiter/KeyboardArbiter.c`, `App/Voice/HostApp.swift` | `f0f1e1f7a29ba915918729115d782ae494fc7244` | `ios/TyprKeyboard/KeyboardHost.swift`, `ios/TyprKeyboard/KeyboardArbiter.c`, `ios/Typr/HostReturner.swift`, `ios/TyprShared/HostReturnCatalog.swift` (translated, not copied; no `APP_STORE` stripping) | MIT, © Bassim Shahidy |
| Host detection safety (process-ID table) and the resuming URL table | [getdictus/dictus-ios](https://github.com/getdictus/dictus-ios) (`main`), which ports the table from [n0an/VivaDicta](https://github.com/n0an/VivaDicta) at `fac7599517d9110d0e8fc7b439b4e60709547144` | `DictusKeyboard/HostAppResolver.swift`, `DictusKeyboard/HostArbiterActivation.m`, `DictusCore/Sources/DictusCore/KnownAppSchemes.swift` | `8804c3629741b9aebe9475e0b2103769eb969dc5` | `ios/TyprShared/HostReturnCatalog.swift` (custom-scheme entries only; universal links left out), `ios/TyprKeyboard/KeyboardHost.swift` | MIT, © PIVI Solutions; VivaDicta MIT, © Anton Novoselov |

## Carried keyboard PR paths

The second row's current destination paths are listed below. In the adopted
source revision, targets used `HEXMobile`, `HEXKeyboard`, `HEXMobileTests` and
`HEXShared`, and the key view file was `HexKeyViews.swift`; Typr renamed these
locally without changing their provenance:
`ios/TyprKeyboard/KeyboardViewController.swift`, `ios/Typr/ExperimentsCard.swift`, `ios/Typr/FullKeyboardSnapshotStage.swift`, `ios/Typr/KeyboardPreviewHost.swift`, `ios/TyprTests/AutocorrectEngineTests.swift`, `ios/TyprTests/FullKeyboardEngineTests.swift`, `ios/TyprTests/KeyboardLayoutTests.swift`, `ios/TyprShared/DotScope.swift`, `ios/TyprShared/FullKeyboard/AccentPicker.swift`, `ios/TyprShared/FullKeyboard/AutocorrectEngine.swift`, `ios/TyprShared/FullKeyboard/FullKeyboardEngine.swift`, `ios/TyprShared/FullKeyboard/FullKeyboardPalette.swift`, `ios/TyprShared/FullKeyboard/FullKeyboardView.swift`, `ios/TyprShared/FullKeyboard/TyprKeyViews.swift`, `ios/TyprShared/FullKeyboard/KeyboardKeyPlaneView.swift`, `ios/TyprShared/FullKeyboard/KeyboardLayout.swift`, `ios/TyprShared/FullKeyboard/KeyboardStripView.swift`.

This list was derived with `git diff --name-only bbab250d^ 9029d2bc -- ios/`.
An upstream PR's status and head may later change; the adopted commit above
is the reference, not the current PR head.

At the split analysis, upstream `dev` was 11 commits ahead at `350c42db`;
none of those commits touched `ios/`. This is a historical observation,
not a claim about the current remote tip.

`src/…` paths in comments under `ios/` refer to `anomalyco/hex` at `cae389a8`.
In particular, unchanged comments in `TyprShared/DotScope.swift` and
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
configuration, updated to Typr's identity. Typr CI uses
`.github/typr/` for configuration and export options.

## How to adopt changes

1. Inspect the specific source revision in a separate checkout or on GitHub.
   `origin` stays `hrudek/typr`; no source/sync remote is required.
   Start each comparison at the feature's saved commit and restrict it to
   source paths, including icon/test resources where relevant.
2. Classify each candidate as a bug fix, improvement, irrelevant change, or
   dependent change (requires another adoption or desktop code). The owner
   decides what to bring over; there is no bulk merge.
3. Translate foreign code into the project's current architecture; do not
   blindly copy it. Inspect the exact source commit, dependencies, privacy
   contract and tests. Check the license first: **GPL, AGPL and LGPL are
   prohibited**. Update [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for
   new dependencies or attributions and preserve required license notices.
4. Use one cohesive PR per adoption, with tests and honest verification limits.
   Update this table in the same PR (source paths, last adopted commit,
   destination files and license). A normal adoption needs no switch; only
   a genuine experiment or owner-requested switch follows [TYPR.md](TYPR.md).
