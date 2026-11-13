# Attribution — D3b contextual statistics (German / English)

## Larger sources (R2-9)

Current packs also adapt Leipzig DE/EN news 2024 (300k rows each), Wikipedia
contributors via Leipzig DE 2021 / EN 2016 (100k rows each), and OPUS OpenSubtitles
v2018 DE/EN (first 1M mono lines each). These are **not CC0/MIT**.

- Leipzig / Deutscher Wortschatz, University of Leipzig: corpus CC BY terms,
  exact version unverified; underlying publisher rights unresolved. Credit
  Goldhahn, Eckart & Quasthoff, LREC 2012.
- Wikipedia contributors: historic text CC BY-SA 3.0,
  https://creativecommons.org/licenses/by-sa/3.0/ ; Typr's copyrightable derived
  Wikipedia adaptations offered under CC BY-SA 4.0 (later-version adaptation),
  see accompanying `CC-BY-SA-4.0.txt`. Preserve article/history attribution,
  changes and share-alike rights; no relicensing claim for other sources/code.
  Full article URL/date supersets are publicly distributed with the Tatoeba
  mapping in the [credits directory](https://github.com/hrudek/typr/tree/main/ios/tools/keyboard_context/credits).
- OPUS / OpenSubtitles.org / subtitle contributors: underlying subtitle, film
  and translation rights retained, **no blanket CC license verified**. Credit
  Lison & Tiedemann, *OpenSubtitles2016*, LREC 2016. Mono exports omit per-line
  film/contributor metadata. Availability is not universal rights clearance.

[Full SOURCE notice](https://github.com/hrudek/typr/blob/main/ios/tools/keyboard_context/SOURCE)
and THIRD_PARTY_NOTICES.md name exact URLs/hashes, reproduction, license links
and open questions. Preserve accessible notices/credit lists with redistributed
packs and new test-only `context-heldout-r2.json` excerpts. Modifications:
NFC/lowercase tokenization, cross-source deduplication, same global digest split,
train-only vocabulary/casing/counts and K=3/min=10 pruning. No endorsement.
Copyright/database/share-alike scope for n-grams, source rights, exact historical
Wikipedia revision credit and App Store DRM remain release-owner review items.


`keyboard-de.tbg` and `keyboard-en.tbg` contain adapted statistics from:

1. **Common Voice and its sentence-collector contributors**, German and English
   `server/data/{de,en}/sentence-collector.txt`, Git snapshot
   `cd9dbfeeed7f2c377d6e9792f4d7a583c0ad3538`.
   Source: https://github.com/common-voice/common-voice/tree/cd9dbfeeed7f2c377d6e9792f4d7a583c0ad3538/server/data
   CC0 1.0 Universal: https://creativecommons.org/publicdomain/zero/1.0/
   (CC0 requires no attribution; this credit preserves provenance.)

2. **Tatoeba contributors named in the accompanying `tatoeba-contributors.tsv`**,
   German and English sentence text, detailed per-language exports dated
   7 November 2026, retrieved 12 November 2026 UTC.
   Source: https://tatoeba.org/en/downloads
   https://downloads.tatoeba.org/exports/per_language/deu/deu_sentences_detailed.tsv.bz2
   https://downloads.tatoeba.org/exports/per_language/eng/eng_sentences_detailed.tsv.bz2
   **Creative Commons Attribution 2.0 France (CC BY 2.0 FR)**:
   https://creativecommons.org/licenses/by/2.0/fr/
   Legal code: https://creativecommons.org/licenses/by/2.0/fr/legalcode.fr
   Official terms: https://tatoeba.org/en/terms_of_use#section-6
   The accompanying `tatoeba-training-attribution.tsv.gz` maps sentence IDs to
   supplied contributor/owner names, original sentence URLs and per-sentence
   license (`CC BY 2.0 FR`, or `CC0 1.0` where Tatoeba's official CC0 export
   lists the ID; CC0 rows need no credit but are kept for provenance). Retain the
   named contributor roster with this notice; a generic Tatoeba-only credit
   is not a substitute. Preserve the mapping at the distribution's public
   data/credits location (or accompany the data with it) for source traceability.

Modifications: Unicode NFC and English apostrophe normalization; Unicode-letter
sentence tokenization; lowercase lookup keys with observed display casing;
exclusion of Tatoeba rows without supplied owners; cross-source normalized
sentence deduplication; deterministic 80/10/10 train/validation/test partition;
training-only top-8,000 vocabularies, unigram and discounted bigram statistics;
DE top-3 followers/count >= 10, EN top-3 followers/count >= 10;
compilation into the sparse TBG1 binary format. The packs are adaptations, not
unaltered sentence exports. No endorsement by Common Voice, Tatoeba, or any
contributor is implied. The Tatoeba-derived portions are not CC0. Keep applicable
license and credit notices with redistributed adaptations; do not add restrictions
that defeat the granted rights. No audio is included.

## Accompanying source mapping

The full deterministic sentence-ID/owner/URL/license mapping is distributed at
[`ios/tools/keyboard_context/credits/tatoeba-training-attribution.tsv.gz`](https://github.com/hrudek/typr/blob/main/ios/tools/keyboard_context/credits/tatoeba-training-attribution.tsv.gz).
Redistributors must preserve this accessible public data/credits location or
accompany their data with the mapping. The bundled `tatoeba-contributors.tsv`
contains all 7,206 supplied training owner names, not just a Tatoeba project credit.
