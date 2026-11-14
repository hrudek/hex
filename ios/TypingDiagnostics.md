# Typing diagnostics implementation notes

The diagnostics redesign is presentation-only. Counter collection, decoding, storage,
learning algorithms and reset semantics are unchanged. No dependencies, telemetry or
feature switches were added.

## Reading incomplete counts

- Decision tracks require a consistent partition and a positive words-checked count.
  Nonzero decisions remain visible as raw counts even when words checked is zero,
  with the local sum-versus-population explanation.
- An incomparable automatic-replacement or undo comparison shows absolute counts,
  never a ratio. Each method has its own heading and shows **Automatic replacements**
  and **Recorded undos**, including the spatial same-length-plus-edit denominator.
- The genuine all-zero state uses empty-state text, not `0 of 0`.
- Detail links and the definitions of word checks and timings stay available without
  saved statistics. Missing values do not remove navigation or measurement help.
- Sampled-key VoiceOver labels include the visible example-count status as well as
  the count and offset. Model shape remains a separate disclosure.

## Diagram implementation decision

The three detail diagrams use SwiftUI shapes/text plus Accessibility-framework
chart descriptors, **not Swift Charts** as originally planned. The review-fix pass
retains this existing implementation to avoid introducing an uncompiled framework
migration on Linux. This is an explicit implementation deviation, not evidence of
owner approval or of framework-provided layout/accessibility guarantees.

Each diagram has named axes, units, ordered raw-count data points and a complete
text-table alternative. Accessibility text sizes replace charts with open tables;
the A–Z chart also falls back to an open table below 320 pt of content width.
Latency charts have independent zero-based count scales. Bar heights are strictly
proportional; there is no minimum positive height that exaggerates small counts.
A tiny positive count can therefore be subpixel: use the raw-count table/audio
graph rather than inferring zero from an invisible bar. The half-summary class
also has a textual annotation; the 20-example reference is dashed and labelled.

The custom rendering still needs visual checks at narrow widths, with multi-digit
y-axis maxima, the outlined half-summary class, and the dashed 20-example line.
Check large text, VoiceOver/audio graphs, contrast and grayscale on rendered UI.
A hosting-size assertion is not a clipping, navigation or accessibility audit.

## Verification and handoff

New/updated XCTest sources cover SDK-imported AX point accessors, incomparable
method output rows, nonzero decisions at zero population, 19/20/256-example
VoiceOver labels, final copy and proportional chart heights/compact hosting.
These tests are written, **not run** on the Linux development host. Neither the
app nor the test target has been compiled there; both still need Xcode/SDK checks.
An app-only build does not validate the test target.

The review-fix pass ran the Linux CI job's Python suites (76 helper tests and 25
offline dictation-log tests), shell syntax, ShellCheck and actionlint v1.7.11.
Workflow lint initially failed because the Go shim had no selected version, then
passed with the installed Go 1.27.3 toolchain on the process-local PATH. Local
scope/whitespace checks do not replace PR-label checks or the next independent
review. No simulator, screenshots, device or real VoiceOver results are claimed.
