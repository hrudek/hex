# Bundled keyboard word data

Only `keyboard-de.words` and `keyboard-en.words` are derived word data, licensed
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
