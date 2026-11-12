# Bundled keyboard word data

`keyboard-de.words` and `keyboard-en.words` are derived spatial word data, licensed
under **Creative Commons Attribution-ShareAlike 4.0 International**, not Typr's MIT
code license. Full terms accompany them in `CC-BY-SA-4.0.txt`:
https://creativecommons.org/licenses/by-sa/4.0/ . No endorsement is implied.

Attribution: **Hermit Dave / FrequencyWords**, German and English frequency lists,
2018 edition, derived from **OpenSubtitles 2018 / OpenSubtitles**.

- Source: https://github.com/hermitdave/FrequencyWords
- Reviewed revision: `525f9b560de45753a5ea01069454e72e9aa541c6`
- Files: `content/2018/de/de_50k.txt`, `content/2018/en/en_50k.txt`
- Content license declaration: https://github.com/hermitdave/FrequencyWords/blob/525f9b560de45753a5ea01069454e72e9aa541c6/README.md#license
- Corpus: https://opus.nlpl.eu/OpenSubtitles2018.php and https://www.opensubtitles.org/
- Typr modifications: NFC normalization; retain lowercase letters only (a–z for
  English, also ä/ö/ü/ß for German), lengths 3–32; sum duplicate counts; compile
  into a forward-only, breadth-first trie. No invented spellings or capitalization.
- The derived resources remain CC BY-SA 4.0. Their editable upstream inputs,
  exact hashes and the complete transformation are available through the links
  above and `ios/tools/keyboard_words/build.py` in Typr's source repository:
  https://github.com/hrudek/typr .

| Resource | Words | Bytes | SHA-256 |
| --- | ---: | ---: | --- |
| keyboard-de.words | 49,027 | 1,651,128 | `20bba113005c244e68b52a18c41d613e4a65b4f9f12c1e02f8cae475fd966624` |
| keyboard-en.words | 46,277 | 1,292,256 | `30560b21132ddae8b65d27d7f5f52b274feec31d7ddaa10083e3ff90cec37fae` |

## Reproduce offline

Explicitly download the two source files at the pinned revision outside the
repository. The compiler itself never accesses the network or app/runtime data;
its CLI rejects inputs with different SHA-256 hashes.

```sh
python3 ios/tools/keyboard_words/build.py de /path/to/de_50k.txt ios/TyprShared/FullKeyboard/WordData/keyboard-de.words
python3 ios/tools/keyboard_words/build.py en /path/to/en_50k.txt ios/TyprShared/FullKeyboard/WordData/keyboard-en.words
python3 -m unittest discover -s ios/tools/keyboard_words -v
```

## TSW1 format

Little-endian header (24 bytes): magic `TSW1`, UInt32 node count, UInt32 word
count, UInt32 reserved zero, UInt64 sum of retained word counts.
Each node (12 bytes): UInt8 alphabet index, UInt8 child count, UInt16 reserved
zero, UInt32 first child index, UInt32 word count (zero for a nonterminal).
The alphabet is `abcdefghijklmnopqrstuvwxyzäöüß`; root label is 255. Children
are contiguous, sorted and strictly forward; an empty child list has index zero.

Runtime reads are bounds-checked, files are mapped if safe, at most 5 MB each,
400,000 nodes and 50,000 words. Invalid headers/visited records, missing resources
and exhausted searches fall back to the old correction path. Offline tests check
every committed record, parent edge, count and digest. The folder, including
attribution and license, is bundled in both app and keyboard, never the widgets.

These counts are not a spelling dictionary: subtitles contain names, slang and
errors and do not establish German noun casing. No accuracy claim follows from
inclusion. In particular, missing technical terms and compounds are expected.

## Corpus context sidecars (TBG1)

`keyboard-{de,en}.tbg` are **separate** Common Voice CC0 + named-owner Tatoeba
CC BY 2.0 FR adaptations, not FrequencyWords/CC BY-SA or MIT data. See
[ATTRIBUTION.md](ATTRIBUTION.md), [tatoeba-contributors.tsv](tatoeba-contributors.tsv)
and the linked full sentence source mapping. Preserve all three when redistributing.
The [explicit offline compiler](../../../tools/keyboard_context/README.md) pins
all input hashes and documents rebuilds; no acquisition or input files are bundled.

| Resource | Lexical words | Edges | Bytes | SHA-256 |
| --- | ---: | ---: | ---: | --- |
| keyboard-de.tbg | 8,000 | 8,263 | 323,104 | `3efe6edcec45e6a134eaa80ee336e2549d173a432ff57c4b37b8d81c0ad04e79` |
| keyboard-en.tbg | 8,000 | 14,255 | 339,689 | `26bdef6715570b7e7b8890467fc165c586974b417d3cc7f0ae8791a52b3578d9` |

Combined packs: **662,793 bytes**, below 1 MiB. They contain no audio, raw sentences,
neural weights, personal data or network URLs. Observed display casing is manual
suggestion spelling, never authority for automatic German noun correction. Stock
corpus names `tom`, `mary`, `maria`, `john` are suppressed in next-word predictions,
but remain contexts/evidence; real contact/system/explicit suggestions are unaffected.

TBG1 little-endian header is 64 bytes (`<4sHH2sHIIIIIIQfIHHII`): magic, version=1,
header size, two-byte language, zero flags, record/edge counts, word/edge/string
section offsets, total file size, UInt64 retained unigram count, Float32 discount=.5,
configured N/K/min-count, payload CRC32, reserved zero. Each 20-byte word record is
five UInt32 values: key/display NUL-terminated UTF-8 pool offsets, unigram count,
first edge index, full context total (including OOV/pruned followers). Next record's
first edge ends the row, or total edge count for the final row. Each 8-byte edge:
UInt16 follower ID, UInt16 zero, UInt32 count. ID 0 is `<s>` with unigram zero;
lexical keys are NFC lowercase and UTF-8 sorted, not ß-folded. Rows sort descending
count then follower ID. Runtime validates the entire format/checksum/strings/counts,
not just visited rows: ≤8,001 records, K≤16, ≤1 MiB combined, ≤128 UTF-8 bytes and
32 characters per spelling. Unsupported or missing selected language abstains.

`p0(w)=(u(w)+.5)/(U+.5*N)`, `boost=(count-.5)/C(h)`,
`lambda=1-sum(retained boosts)`, `P(w|h)=lambda*p0(w)+boost(w)`;
unknown/no-total contexts use lambda=1. Pruned/OOV continuation mass backs off,
not renormalization of only stored edges. Unknown context is not `<s>`.
The only resident index is sorted unigram IDs, **32,000 bytes combined**.
Mapped file+index payload is 694,793 bytes, not an extension RSS measurement.

`context-heldout-cc0.json` is a small **CC0 Common Voice** test fixture with source
revision/selection recorded inside. `swift-reference-vectors.json` is Typr-generated
numeric reference output for the fixed bilingual formulas. Both are inert test
resources, not runtime model inputs. Neither changes the sidecar training counts.
