# Keyboard learning controls

Keyboard settings retain **Learn from my typing**, **Manage learned words**,
autocorrect language selection and **Personal names and terms**. The former
Typing diagnostics pages and their snapshot scenes have been removed. There is
no Statistics entry until a usable statistics view is available.

**Saved typing data** is available even when Full keyboard is off:

- **Reset learning** clears touch calibration, kept words, word counts,
  next-word contexts, rejected corrections and imported personal words. It also
  disables contacts and dictation imports without deleting their sources.
  Technical counters remain intact.
- **Reset technical counters** clears the existing autocorrect event counters
  and processing-time histograms. Learned words, calibration and imports remain
  intact. These counters are not typing speed, usage history or tap accuracy.

Both actions require confirmation and report storage failures. They use the
existing shared-store reset epochs; a live keyboard consumes the reset before
its next save. Turning learning off does not delete saved learning. Without
Full Access, session-only keyboard learning cannot be displayed by the app.

The shared learning store, technical instrumentation and autocorrect algorithms
are unchanged. No historical usage statistics can be reconstructed from their
bounded counters or capped touch-model samples.

## Verification

`SettingsPresentationTests` covers removed routes, the isolated learned-word
fixture, reset-control sizing and unavailable storage. The reset integration
in `KeyboardLearningIntegrationTests` checks that counter resets reach a live
keyboard without deleting learning, and that learning resets preserve counters.
`KeyboardPersonalLexiconLearningTests` covers imported-word deletion and source
disabling. These are simulator tests; Linux helper checks do not execute them.
