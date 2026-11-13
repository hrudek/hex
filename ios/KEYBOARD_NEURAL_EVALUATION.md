# Neural next-word measurement (R2-10)

**Evaluation only; do not ship either network.** No keyboard behavior, automatic
correction, switch, persistent personal data, privacy copy or reset semantics
changes. The keyboard still never accesses microphone, speech model or network.
The owner allowed neural data/weights subject to notices; rejection here is a
measured engineering decision, not the older blanket privacy/license exclusion.

## Gate and experiment

Require at least **+2 percentage points recall@3 in both DE and EN**, no mixed
regression, bounded work, and a wide measured device-memory margin below the
roughly 60–70 MiB extension limit **including all existing resources/UI**.
Any future first integration must be next-word suggestion reranking only, never
an automatic correction. Passing offline quality alone would not authorize shipping.

The CPU-only experiment trains a two-word-conditioned MLP: shared bilingual
2,048-word vocabulary (including unknown/start), 16-wide embeddings, concatenated
two-token input, 32-wide ReLU hidden layer, full vocabulary output. It uses 6,000
train sentences per language from R2-9's digest-partitioned SQLite cache (dedup
across sources), **139,092 events**, fixed seed 210, 1,200 SGD updates, batch 128.
Vocabulary is training-only. No held-out selection/tuning, personal text, contacts,
dictation log, GPU, PyTorch or Core ML. Row-wise symmetric int8 weights, Float32
row scales/biases/activations; this is **not integer-only activation inference**.

System Python lacked NumPy; installed **NumPy 2.5.4** in an external disposable
venv, not as an app/repository dependency. Whole training + evaluation took
116.17 s initially / 115.88 s repeat / 168.64 s final run. These timings are diagnostics, not tests.
Repeat weights were byte-identical (SHA256 in `results.json`). This deliberately
small, undertrained architecture is not evidence that all neural models fail.

## Same-set measurements

Inputs are existing `WordData/context-heldout-r2.json`: 192 sentences/language,
64 each news/Wikipedia/OpenSubtitles. Mixed is 192 deterministic half-DE/half-EN
splices of the paired sentences, **not naturally sampled code-switching**.
Every model sees the identical events within each row. Denominators include OOV
and sentence starts; invalid-token barriers reset both context tokens. No noisy
touch/correction evaluation is claimed for a next-word-only offline model.

Controlled baseline uses the **current #136 TBG1 bytes** and the repository's
Python probability reference at fixed neutral bilingual weight DE=0.5, no stock
name suppression. It does **not** simulate R2-4's evolving sentence posterior,
UI slot ownership, casing or system checker. Personal comparison uses #128's
trigram-first / bigram-backoff math, a synthetic trusted profile built from the
first 100 train events (134 rows/140 edges, within 512/8 caps), never test targets.
It is a synthetic profile, not real-user learning. Three XCTest checks exercise
the actual Swift int8 pass, malformed models and personal selection/deletion/reset;
existing corpus reference tests protect the TBG1 reference. Replaying evolving
real-user profiles through the whole engine remains a future check.

Values below are **recall@1 / recall@3, percent** (full-precision ratios/provenance hashes
in `tools/keyboard_neural/results.json`):

| Set (events) | Corpus before | Corpus + personal before | Neural alone after | Rerank corpus top 3 | Rerank personal top 3 |
| --- | --- | --- | --- | --- | --- |
| DE (2,039) | 5.35 / 10.99 | 4.86 / 10.54 | 0.59 / 3.04 | 3.14 / 10.99 | 3.33 / 10.54 |
| EN (2,285) | 9.85 / 17.46 | 9.41 / 17.46 | 5.73 / 10.46 | 8.32 / 17.46 | 8.32 / 17.46 |
| Mixed (2,162) | 7.49 / 13.60 | 6.80 / 13.37 | 4.12 / 8.00 | 6.06 / 13.60 | 6.06 / 13.37 |

Neural alone vs corpus recall@3: **DE −7.95 pp; EN −7.00 pp; mixed −5.60 pp**.
Compared with personal baseline: −7.50 / −7.00 / −5.37 pp. A rerank restricted to
the same three words mathematically cannot increase recall@3; here it also harms
recall@1. A broader fixed candidate pool could be evaluated in future, but is not
silently selected after seeing these results. **Quality gate fails decisively.**
Zero new automatic changes is a structural property (no production integration),
not a claim of device accuracy; the full existing valid-word/name/compound and
DE/EN/mixed correction controls remain the relevant regression protection.

## Work and memory

Tiny binary: **124,176 bytes** (weights/scales/biases, excludes external vocabulary
JSON). Exactly **66,560 MACs/call**: 2×16×32 + 2048×32; embedding lookup/dequant
32 scalar multiplies, hidden/output row rescaling 2,080 multiplies + 2,080 bias
adds, 32 ReLU comparisons, and 8,448 bytes of Float32 activation payload. MAC
counts omit tokenization/ranking. A true integration would invoke at most once
per changed settled context and never grant automatic authority; no such hook is
installed. Dictionary/token-string allocator cost is not included in payload bounds.

Standalone optimized Swift 6.4.2 Linux process, same model and six full-logit
vectors: max absolute difference **9.536743e-7** versus quantized NumPy inference
(tolerance 1e-4). 1,000 checksum-consumed calls: **0.05852 s total**, printed only.
Linux `getrusage(RUSAGE_CHILDREN).ru_maxrss`, separate fresh wrappers:
**20,900 KiB loaded peak** versus **16,720 KiB empty** (~4.08 MiB difference).
This is whole-process high-water including Swift/Foundation, parsing, parity
text, transient model copies and allocations, **not an isolated model RSS delta**.

Planning-only iPhone incremental estimate: **1–5 MiB** for tiny-model loading,
vocabulary and scratch/allocator overhead. Serialized weights+activations are
only ~0.127 MiB, but this is not a safe whole-extension total. No observed iOS
baseline/headroom exists here; a 60–70 MiB budget cannot be certified on Linux.

## iikb English predictor inspection

Read-only reference pin `09a2e9cdfbe851adff6c4646333c0a3f74ba8765`:
`KeyboardCore/Correction/Network.swift`, `LanguageModel.swift`,
`KeyboardEnglish/Resources/en.network`, `NETWORK-LICENSE`, `scripts/network.py`.
No upstream code was executed or built. Weights copied out of the untrusted tree
into an external experiment directory; independent Python via `-I` parses them.

Actual HXN1: **7,939,740 bytes**, V=20,000 / E=128 / H=1,024, int8 row matrices,
tied input/output embedding, LSTM state and Float32 scratch, 16-token inference
window/cache. **4,718,592 MACs per recurrent token**; **78,188,544 MACs** cold
16-token window + output; **7,409,664 MACs** one continued token + output.
At least **185,600 bytes** of major Float32 workspace (not an RSS claim), plus
weights, cache/token arrays, output temporaries, lexicon and runtime overhead.
Planning-only device increment **10–20 MiB** including transient loads/caches is
not proven safe with existing Typr models; the NumPy reference expands weights
to floats, so its RSS must not be presented as upstream Swift inference memory.

Independent NumPy LSTM reference, **only first 32 events per set** to bound CPU;
same subset for corpus and upstream, fixed neutral mixture, no personal profile:

| Set | Corpus recall@1 / @3 | iikb reference recall@1 / @3 |
| --- | --- | --- |
| DE | 1/32 / 4/32 (3.13% / 12.50%) | 0/32 / 0/32 |
| EN | 3/32 / 6/32 (9.38% / 18.75%) | 7/32 / 7/32 (21.88% / 21.88%) |
| Mixed | 1/32 / 4/32 (3.13% / 12.50%) | 4/32 / 4/32 (12.50% / 12.50%) |

This is a smoke-sized format/inference experiment, not upstream-device parity or
statistical significance. Word-only fixture tokenization omits original punctuation;
no upstream tokenizer/cache/personal fine-tuning code is executed. English gain
does not compensate for zero German hits; no German upstream network exists.

Upstream training script describes 16-subReddit Reddit comments (~7M words per
subreddit), WildChat-4.8M, and 40% WildChat-1M/SODA lines; 128 embedding, 1,024 LSTM,
32-token training windows, 256 batch, 40,000 Adam steps. WildChat: ODC-By 1.0;
SODA: CC BY 4.0; Reddit source has **no license stated** by the pinned notice.
Exact input revisions, deleted comments, author permissions and derivative rights
remain open. See `tools/keyboard_neural/SOURCE`; corpus rights do not inherit MIT.
No upstream/experiment weights or additional corpus data are committed.

## Reproduction and device follow-up

From repository root; `B` is external research directory, `W` this worktree:

```sh
B=/home/hrudek/code/typr-research/iikb-parity
W=$PWD
# Explicit optional developer dependency (not done by the harness):
python3 -m venv "$B/data/neural-r2/venv"
"$B/data/neural-r2/venv/bin/python" -I -m pip install numpy==2.5.4
# Copy weights as data; NEVER run Python or builds in iikb-src.
cp "$B/iikb-src/Packages/KeyboardModules/Sources/KeyboardEnglish/Resources/en.network" "$B/data/neural-r2/en.network"
OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 "$B/data/neural-r2/venv/bin/python" -I \
  ios/tools/keyboard_neural/evaluate.py "$B/data/out/r2-9/corpus.sqlite" \
  ios/TyprShared/FullKeyboard/WordData "$B/data/neural-r2/replay" \
  --hxn "$B/data/neural-r2/en.network"
. ~/.local/share/swift/env.sh
swiftc -parse-as-library -O -swift-version 6 -D NEURAL_CLI \
  -Xfrontend -warn-long-expression-type-checking=100 \
  ios/TyprTests/KeyboardNeuralEvaluationTests.swift -o "$B/data/neural-r2/forward"
python3 -I ios/tools/keyboard_neural/measure.py "$B/data/neural-r2/forward" \
  "$B/data/neural-r2/replay/tiny.tnn" "$B/data/neural-r2/replay/parity.txt"
python3 -I ios/tools/keyboard_neural/measure.py "$B/data/neural-r2/forward" --empty
python3 -I -m unittest discover -s ios/tools/keyboard_neural -v
"$B/data/neural-r2/venv/bin/python" -I -m unittest discover -s ios/tools/keyboard_neural -v
"$B/harness/run.sh" "$W"
```

All generated corpora/profiles/checkpoints/parity files stay outside Git; remove
`$B/data/neural-r2` to delete this experiment, without touching keyboard learning.
The exact cache/fixtures/packs/model hashes are pinned in the committed result.
Determinism means fixed work/seed/data on the recorded NumPy/BLAS implementation,
not bit-identical training across all architectures or BLAS builds.

Before any future shipping decision: macOS/Xcode Swift 6 build + simulator tests;
real iPhone cold/warm extension physical footprint/jetsam including both tries,
context packs, personal maps and UI, memory warnings/unloading, oldest supported
hardware latency/energy and rapid context cancellation; corpus+personal replay
with evolving language posterior, actual DE/EN/mixed text, names/compounds/OOV;
Full Access on/off, delete/reset and app-group persistence; suggestion selection,
Space/Typr-key/punctuation, undo/rejected pairs and 0 new false automatic changes.
No UI change in this spike; screenshots: none.
