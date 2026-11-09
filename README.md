# Typr

Typr is a private, standalone iPhone dictation keyboard with a containing app,
widgets and Live Activity. Speech stays on-device: Apple Speech on iOS 26+,
or Parakeet via FluidAudio on iOS 18+. The keyboard exchanges commands and
completed text with the app; it never accesses the microphone, model or network.

Typr is based on Hex by Kit Langton
(https://github.com/kitlangton/hex / https://github.com/anomalyco/hex), MIT
(© Christopher Langton; the original [LICENSE](LICENSE) is preserved).
[PORTS.md](PORTS.md) records adopted sources and how future changes are selected.

## Build and test

On macOS, install Xcode 26+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
2.46.0+, then:

```sh
cd ios
xcodegen generate
xcodebuild test -project HEXMobile.xcodeproj -scheme HEXMobile -destination "id=<SIM_UDID>"
```

Alternatively, from the repository root:
`bash .github/typr/agent-test.sh [Target/Class,…]` keeps the committed app
identity unchanged. Signing and device installation require the owner's Apple
configuration. CI validates the committed Typr identity without rewriting it.

Start with [AGENTS.md](AGENTS.md) for development,
[TYPR.md](TYPR.md) for the feature table, review and CI/TestFlight,
and [ios/README.md](ios/README.md) for architecture and verification limits.
The default integration branch is `hex-plus`; app code stays in `ios/`.
