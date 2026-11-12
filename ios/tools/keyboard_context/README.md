# Offline contextual keyboard data

Explicit, stdlib-only Python tooling. It never downloads, executes corpus content,
reads app/runtime data, or collects typing. Raw sentence exports and the derived
SQLite cache **must remain outside Git**. Do not run the iikb research checkout.
The two compiler modules were narrowed from Typr's D3b research builder; there is
no dependency on that checkout or any upstream executable.

## Approved inputs

Arrange an external directory `$DATA` as follows (obtain these exact snapshots
separately; mutable URLs are not permission to accept a new hash):

| Relative path under `$DATA/raw/` | SHA-256 | Provenance / license |
| --- | --- | --- |
| `common-voice-cd9dbfee/de-sentence-collector.txt` | `de6bd33fc5742350690fa4be6197aafd9be2c6c9fe4b70b8c5c8670971acc117` | Common Voice `server/data/de/sentence-collector.txt` at `cd9dbfeeed7f2c377d6e9792f4d7a583c0ad3538`, CC0 1.0 |
| `common-voice-cd9dbfee/en-sentence-collector.txt` | `31ac8e200449ebd7aee4a8c6bd16d4dafd076cf11f7c3efe1035f0283712d136` | Same revision, `server/data/en/sentence-collector.txt`, CC0 1.0 |
| `tatoeba/deu_sentences_detailed.tsv.bz2` | `fd31882dc105bd8fa1390e08b48c42f6194ffae89bbf4bb82decf6ef94f6f2a7` | Tatoeba detailed German export 7 November 2026, CC BY 2.0 FR, supplied owners only |
| `tatoeba/eng_sentences_detailed.tsv.bz2` | `afec98e4c44a72f8fc709ce4d672fd3ab7f9ca731402f5d35e384b0b21b207c5` | Same release, English |
| `tatoeba-licensing/deu_sentences_CC0.tsv.bz2` | `df8c16713e5715a0e1343bc1195004463e7facee08863d3cd709cbf123a74587` | Official same-release German CC0 subset, license classification only |
| `tatoeba-licensing/eng_sentences_CC0.tsv.bz2` | `c2e2edd063a31cbbc8e416a4858225e934bbb0afff485031821e59f230ccf1ca` | Same, English |

Sources: https://github.com/common-voice/common-voice/tree/cd9dbfeeed7f2c377d6e9792f4d7a583c0ad3538/server/data
and https://downloads.tatoeba.org/exports/per_language/{deu,eng}/.
Licenses, exact source URLs, named contributor roster, modifications and the
required distribution attribution are in
[`WordData/ATTRIBUTION.md`](../../TyprShared/FullKeyboard/WordData/ATTRIBUTION.md).
The Tatoeba-derived portions are **not CC0**. No FrequencyWords/OpenSubtitles
counts, vocabularies or casing enter this builder.

## Rebuild

From the repository root, with an explicitly chosen external `$DATA`:

```sh
python3 -I ios/tools/keyboard_context/tools/build_d3b.py prepare "$DATA"
python3 -I ios/tools/keyboard_context/tools/build_d3b.py compile "$DATA"
python3 -I ios/tools/keyboard_context/tools/build_d3b.py verify "$DATA"
python3 -I ios/tools/keyboard_context/tools/heldout_fixture.py "$DATA" /tmp/context-heldout-cc0.json
python3 -m unittest discover -s ios/tools/keyboard_context -v
```

`prepare` refuses an existing `work-d3b/corpus.sqlite`. It validates all six input
hashes, excludes missing-owner Tatoeba rows, and produces deduplicated sentences,
credits and corpus statistics under the external directory. Never point it at an
app container. A fresh prepare is needed to independently validate inputs; compile
and verify recount the cache. Both require the **approved output hashes**, and
verify also compares a second compilation byte-for-byte. Nothing installs output
automatically; copying changed data requires new source/license/content review.

Normalization is NFC + lowercase (not casefold: ß remains ß); English internal
apostrophes normalize to ASCII. Invalid/numeric tokens break adjacency, sentence
boundaries do not form lexical pairs. Sentence deduplication is global across
sources/languages by normalized compact JSON token sequence. First SHA-256 uint64
big-endian modulo ten: 0 test, 1 validation, 2…9 training. Vocabulary, counts and
display casing use **training only**. Display casing uses interior observations
before sentence-initial observations. N=8,000, K=3, count≥10, D=.5, alpha=.5 are
fixed D3b validation-selected parameters, not re-tuned by this production compiler.
Compile output is 662,793 bytes combined (see WordData README for hashes).

The 128-sentence Common Voice fixture is CC0, first 64 SHA-ordered global-test
sentences per language with 5–20 tokens and no invalid barriers. It is independent
of training by normalized digest, **not** by template/author/translation family.
`swift-reference-vectors.json` is Typr-generated numeric reference output from the
Python scorer (47 events, published D3b sequences); the Python and Swift tests
check all state, weight and suppressed/unsuppressed top-three probabilities.

## Credits and distribution

`credits/tatoeba-training-attribution.tsv.gz` is the deterministic, complete
training sentence-ID → supplied owner → original URL → license mapping. It is
**public corpus attribution**, not a private typing store or raw corpus export.
SHA-256: `8e440c5fc04efb41b3719c597af755afebf75a7089477d2af6c51cb6097a3376`.
It lives outside runtime WordData so it does not add ~14 MB to the extension.
The bundled attribution links to its public repository location. Redistributors
must keep that mapping publicly accessible (or accompany their data with it), and
ship the attribution and actual contributor roster. The 7,206 supplied owner names
are preserved verbatim in WordData, including credits to CC0 rows for provenance.
App distribution/DRM and content/third-party-rights review remain owner release
responsibilities; benchmark recall is not content-safety or legal certification.
