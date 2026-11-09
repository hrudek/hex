# Hex+

Hex+ is a personal, standalone iPhone dictation app with a custom keyboard,
widgets and Live Activity. Speech stays on-device: Apple Speech on iOS 26+,
or Parakeet via FluidAudio on iOS 18+. The keyboard exchanges commands and
completed text with the app; it never accesses the microphone, model or network.

The project originated from the iOS part of
[anomalyco/hex](https://github.com/anomalyco/hex), under MIT
(© Christopher Langton; the original [LICENSE](LICENSE) is preserved).
There are no automatic upstream merges. [PORTS.md](PORTS.md) records adopted
sources and how future changes are selected.

## Build and test

On macOS, install Xcode 26+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
2.46.0+, then:

```sh
cd ios
xcodegen generate
xcodebuild test -project HEXMobile.xcodeproj -scheme HEXMobile -destination "id=<SIM_UDID>"
```

Alternatively, from the repository root:
`bash .github/hexplus/agent-test.sh [Target/Class,…]` keeps the committed app
identity unchanged. Signing and device installation require the owner's Apple
configuration; CI applies the build identity only in its disposable checkout.

Start with [AGENTS.md](AGENTS.md) for development,
[HEXPLUS.md](HEXPLUS.md) for the feature table, review and CI/TestFlight,
and [ios/README.md](ios/README.md) for architecture and verification limits.
The default integration branch is `hex-plus`; app code stays in `ios/`.
