# Current-word touch evidence

Step 1 (PR #95) preserved information that fixed key hit-testing otherwise discards,
without changing typing/correction outputs. The tracker itself still changes no hit-testing,
visible keys, gestures, settings or dictation and adds no switch, learning or word data.
Step 2 now consumes its evidence in the separately documented
[static spatial decoder](KEYBOARD_SPATIAL_DECODER.md).

## Ownership and coordinates

`AutocorrectEngine` owns `KeyboardTouchInput`. `FullKeyboardEngine` supplies each unambiguous
letter's inserted text, committed point and key, plus the complete `KeyboardLayout` snapshot.
Points are in keyboard-view coordinates, including the suggestion strip. A normal release
uses its release point; rollover uses the last point available when the earlier letter is
committed, exactly once and in insertion order. Shifted letters retain their inserted case.

Only a fully observed, contiguous prose word is available through
`touchInput.evidence(beforeInput:)`. It must match `AutocorrectEngine.currentToken` exactly.
Suggestions and replace-on-space validate that association before using it for static
spatial ranking. Missing evidence preserves the existing spelling-only path. Hidden suggestions and disabled
autocorrect do not prevent tracking. Email/URL fields and missing document context do.

## Conservative invalidation

- Single-character backspace removes the last sample only if both pre/post-edit tokens match.
- Word deletion, accepted suggestions, autocorrect undo, space, return and unsupported inserts
  discard evidence. Earlier words are never restored from a history.
- Accents chosen in a popup and slides between keys fall back to spelling-only correction;
  their positions are not labeled as ordinary taps. Numeric/symbol input also falls back.
- External text changes (including inserted dictation), selection changes, field preparation,
  keyboard dismissal, memory warnings, canceled gestures and layout changes discard evidence.
  External invalidation also marks held taps unusable, so a late release cannot recreate it.
- After invalidation in the middle of a word, subsequent letters cannot create evidence for
  just that word's suffix. Tracking resumes at a new, fully observed word.
- At most 64 samples are retained; longer words fall back until a new word begins.

The existing token parser also excludes handles, paths, identifiers attached to punctuation
and other non-prose contexts. This first step conservatively excludes apostrophe sequences
rather than trying to align them. Corrected words and manual replacements are not training
labels: there is no learning in this change.

## Privacy and proof

The tracker stores only the current word and geometry in RAM. It has no serialization,
UserDefaults, file, log, export or network path, and no retained surrounding field text.
It does not introduce a persistent keyboard log or change the dictation-log exception.

`KeyboardTouchInputTests` covers geometry, rollover, deletion/retyping, undo, suggestions,
external changes, held-tap invalidation, layout changes, accents, slides, cancellation,
trackpad activation, hidden suggestions, disabled autocorrect, non-prose fields, overflow,
missing context and unchanged correction outputs. Existing keyboard and autocorrect suites
remain regression checks. These are iOS simulator tests; Linux checks cannot establish that
they compile/pass. Actual host callback ordering, fast two-thumb typing and keyboard lifecycle
behavior require an iPhone check. Conservative host invalidation can reduce evidence
coverage without changing what is typed; measure that coverage before building a decoder.

[Step 2](KEYBOARD_SPATIAL_DECODER.md) adds the static decoder and licensed DE/EN data.
A conservative personal touch model remains a separate, unimplemented future decision.
