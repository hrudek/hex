# Third-party notices

Hex+'s own code and the adopted Hex iOS base are covered by the repository's
[MIT license](LICENSE), whose original © Christopher Langton notice is retained.
Source adoption history, including the inherited MIT OpenCode iOS scope port,
is recorded in [PORTS.md](PORTS.md).

## OpenCode iOS scope port

The iOS scope credits `DotScopeView.swift`, `DictationScopeBar` and
`DotScopeShaders.metal` from [anomalyco/opencode](https://github.com/anomalyco/opencode),
inherited through the Hex iOS base. This port is covered by the MIT license.
The following notice is reproduced exactly from the
[OpenCode LICENSE](https://github.com/anomalyco/opencode/blob/12a661ea40cd5863b271a89bb06b8a3ddb7ab5a0/LICENSE);
this commit pins the verified license text, not a new code adoption.

```text
MIT License

Copyright (c) 2025 opencode

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Automatic return to the host app

Host-app detection and return after a cold-start dictation (`ios/TyprKeyboard/KeyboardHost.swift`,
`ios/TyprKeyboard/KeyboardArbiter.c`, `ios/TyprShared/HostReturnCatalog.swift`,
`ios/Typr/HostReturner.swift`) are translated from three MIT projects; see [PORTS.md](PORTS.md).
Their notices are reproduced below.

### iikb

From [AVGVSTVS96/iikb](https://github.com/AVGVSTVS96/iikb/blob/f0f1e1f7a29ba915918729115d782ae494fc7244/LICENSE).

```text
MIT License

Copyright (c) 2026 Bassim Shahidy

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### Dictus

From [getdictus/dictus-ios](https://github.com/getdictus/dictus-ios/blob/8804c3629741b9aebe9475e0b2103769eb969dc5/LICENSE).

```text
MIT License

Copyright (c) 2026 PIVI Solutions

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### VivaDicta

The URL table Dictus ports from [n0an/VivaDicta](https://github.com/n0an/VivaDicta/blob/fac7599517d9110d0e8fc7b439b4e60709547144/LICENSE) (Dictus's last sync point).

```text
MIT License

Copyright (c) 2026 Anton Novoselov

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Keyboard correction, personal learning, diagnostics and word data

Typr adapts selected bounded trie/edit-search, spatial/prior scoring, pitch-normalized
learning statistics, explicit pending feedback and snapshot-dashboard ideas from
[AVGVSTVS96/iikb at `08df5aa1e698d8587b6dcaef53f5e555ba1fac2a`](https://github.com/AVGVSTVS96/iikb/tree/08df5aa1e698d8587b6dcaef53f5e555ba1fac2a).
Exact source/destination paths and exclusions are recorded in [PORTS.md](PORTS.md).
These are rewritten, bounded Typr implementations, not a port of iikb's full
learned/neural model or resources. The existing iikb MIT notice above
(Copyright (c) 2026 Bassim Shahidy), verified against the
[pinned LICENSE](https://github.com/AVGVSTVS96/iikb/blob/08df5aa1e698d8587b6dcaef53f5e555ba1fac2a/LICENSE),
also covers these adaptations; it is not duplicated here.

Typr additionally translates bounded best-first prefix enumeration, physical
held-letter mapping and personal (kept or repeatedly typed) word completions from
`Correction/Lexicon.swift`, `Correction/LetterKeys.swift` and `Correction/TypingMemory.swift`
at [iikb `09a2e9cdfbe851adff6c4646333c0a3f74ba8765`](https://github.com/AVGVSTVS96/iikb/tree/09a2e9cdfbe851adff6c4646333c0a3f74ba8765).
The existing **MIT, Copyright (c) 2026 Bassim Shahidy** notice above was verified
against that revision's LICENSE and also covers these rewritten adaptations.
No additional iikb word data, neural weights or dependencies are included;
[PORTS.md](PORTS.md) records the exact paths, pin and exclusions.

The P4 personal next-word layer additionally translates follower counts and cleanup
from `Packages/KeyboardModules/Sources/KeyboardCore/Correction/TypingMemory.swift`
and discounted backoff from the adjacent `LanguageModel.swift` at
**`09a2e9cdfbe851adff6c4646333c0a3f74ba8765`**. The same **MIT, Copyright (c)
2026 Bassim Shahidy** notice above applies and was checked against that pin's LICENSE;
it is not duplicated. Typr supplies its own stricter trust protocol, event-count
ageing, bounds, schema migration and deletion UI. No upstream resources, app
histories, trigrams, neural weights or executable dependency are adopted; exact
paths/exclusions are in `PORTS.md`.

The aggregate-aim extension additionally translates full covariance, pooled shrinkage,
multiple-timescale aim, predictive fixed-share weighting and covariance-display/test
ideas (rewritten with Typr's shared 40/8-label affine drift, not upstream per-key
30/3 banks) from `TouchModel.swift`, `Aim.swift`, `Tap.swift` and `TypingModelTests.swift` at
[iikb `09a2e9cdfbe851adff6c4646333c0a3f74ba8765`](https://github.com/AVGVSTVS96/iikb/tree/09a2e9cdfbe851adff6c4646333c0a3f74ba8765),
MIT, Copyright (c) 2026 Bassim Shahidy. The same full MIT notice above applies;
[PORTS.md](PORTS.md) lists exact paths and exclusions. No upstream recent-tap
reservoir, executable dependency, neural weights, or language resource is adopted.

The deferred suggestion pipeline additionally translates snapshot/job/revision-checked
finish and compatible-cache adoption from
[AVGVSTVS96/iikb at `09a2e9cdfbe851adff6c4646333c0a3f74ba8765`](https://github.com/AVGVSTVS96/iikb/tree/09a2e9cdfbe851adff6c4646333c0a3f74ba8765),
`TypingEngine+Words.swift` and `FullKeyboardViewController.swift`. The existing
**MIT, Copyright (c) 2026 Bassim Shahidy** notice above also covers this rewritten
adaptation; [PORTS.md](PORTS.md#deferred-keyboard-suggestions-iikb) records exact
paths and exclusions. No upstream controller, resources or neural weights are bundled.

Exact two-part omitted-space suggestions, whole-vs-split comparison and owned boundary
revert additionally translate ideas from `Correction/Corrector.swift`,
`Typing/TypingEngine+Words.swift` and boundary scenarios in `AutocorrectTests.swift` at
[iikb `09a2e9cdfbe851adff6c4646333c0a3f74ba8765`](https://github.com/AVGVSTVS96/iikb/tree/09a2e9cdfbe851adff6c4646333c0a3f74ba8765).
The same **MIT, Copyright (c) 2026 Bassim Shahidy** notice above, verified against
that pin's LICENSE, applies without duplication. These are rewritten manual-only
Typr algorithms, not copied files, upstream test data, language data or dependencies;
[PORTS.md](PORTS.md#exact-omitted-space-splits-and-joins-iikb-p5) lists paths and exclusions.
The small closed-class short-word supplement is Typr original hand-curated work.
P5b additionally translates two-part conditional scoring and whole comparison from
that pin's `Corrector.swift` / `LanguageModel.swift`, using Typr's existing separately
licensed TBG1 corpus model, lexical/code-switch backoff and manual-only policy.
No new upstream data, neural weights, personal context storage or dependencies;
the same MIT © 2026 Bassim Shahidy notice above applies.

The bundled `keyboard-de.words` and `keyboard-en.words` are derived from **Hermit Dave /
FrequencyWords**, revision `525f9b560de45753a5ea01069454e72e9aa541c6`, 2018 DE/EN
50k lists, originating from **OpenSubtitles 2018 / OpenSubtitles**. **Their content
is CC BY-SA 4.0, not MIT**, as declared in the pinned source README:
https://github.com/hermitdave/FrequencyWords/blob/525f9b560de45753a5ea01069454e72e9aa541c6/README.md#license .
Typr normalizes/filters words and compiles the counts into a trie; the derived data
remains CC BY-SA 4.0. Attribution, exact source links, modifications, hashes and
reproduction instructions are in
[ios/TyprShared/FullKeyboard/WordData/README.md](ios/TyprShared/FullKeyboard/WordData/README.md).
That notice and the [full license](ios/TyprShared/FullKeyboard/WordData/CC-BY-SA-4.0.txt)
are bundled with the data in both the app and keyboard. These notices do not
claim endorsement by the original authors. Typr's own decoder/compiler code
remains MIT. No iikb model or word resources, wordfreq or Python package dependency
is bundled.

## Offline corpus context suggestions

Typr additionally translates absolute-discount backoff and bounded contextual
candidate ranking ideas from iikb `LanguageModel.swift` / `Corrector.swift` at
[`09a2e9cdfbe851adff6c4646333c0a3f74ba8765`](https://github.com/AVGVSTVS96/iikb/tree/09a2e9cdfbe851adff6c4646333c0a3f74ba8765),
MIT, **Copyright (c) 2026 Bassim Shahidy**. The full existing iikb notice above
covers this adaptation; no duplicate notice or iikb resource is included.

The separate `keyboard-de.tbg` / `keyboard-en.tbg` statistics adapt:

- **Common Voice and its sentence-collector contributors**, DE/EN text at
  `cd9dbfeeed7f2c377d6e9792f4d7a583c0ad3538`, **CC0 1.0 Universal**:
  https://creativecommons.org/publicdomain/zero/1.0/ .
- **Tatoeba contributors named in the accompanying
  [tatoeba-contributors.tsv](ios/TyprShared/FullKeyboard/WordData/tatoeba-contributors.tsv)**,
  German and English detailed exports dated 7 November 2026, retrieved
  12 November 2026 UTC, **Creative Commons Attribution 2.0 France (CC BY 2.0 FR)**:
  https://creativecommons.org/licenses/by/2.0/fr/ ; full legal code:
  https://creativecommons.org/licenses/by/2.0/fr/legalcode.fr .
  Official source and terms: https://tatoeba.org/en/downloads and
  https://tatoeba.org/en/terms_of_use#section-6 .

The [full accompanying attribution](ios/TyprShared/FullKeyboard/WordData/ATTRIBUTION.md)
contains exact source URLs, changes and distribution conditions, with the actual
7,206-owner roster bundled in app and keyboard. Preserve the accompanying
[training sentence-ID / owner / URL / per-sentence-license mapping](ios/tools/keyboard_context/credits/tatoeba-training-attribution.tsv.gz)
at an accessible public data/credits location or accompany redistributed data with
it; generic Tatoeba credit alone is insufficient. Official CC0 subset rows are
labelled in that mapping. Tatoeba-derived portions are **not CC0 or MIT**. No
endorsement is implied. Preserve applicable credits/license links and do not add
restrictions defeating the granted rights. No audio or share-alike data enters
these sidecars. The unchanged FrequencyWords `.words` files retain separate CC
BY-SA terms. `context-heldout-cc0.json` is a Common Voice CC0 test-only fixture;
`swift-reference-vectors.json` is Typr-generated numeric reference output.

## FluidAudio 0.15.5

The iPhone app uses the Swift package
[FluidInference/FluidAudio](https://github.com/FluidInference/FluidAudio/tree/v0.15.5),
pinned to 0.15.5 in `ios/project.yml`, under
[Apache License 2.0](https://github.com/FluidInference/FluidAudio/blob/v0.15.5/LICENSE).
Its package manifest has no external package dependencies. It includes vendored
components, whose [license notices](https://github.com/FluidInference/FluidAudio/tree/v0.15.5/ThirdPartyLicenses)
must accompany redistribution:

- `ThirdPartyLicenses/fastcluster-LICENSE.md`: BSD-2-Clause, reproduced below.
- `ThirdPartyLicenses/vbx-LICENSE.md`: Apache-2.0;
  Copyright 2021-2024 BUT Speech@FIT (original VBx project).
  [Full pinned license](https://github.com/FluidInference/FluidAudio/blob/v0.15.5/ThirdPartyLicenses/vbx-LICENSE.md).

### fastcluster notice (from FluidAudio v0.15.5)

Copyright:
  * Until package version 1.1.23: © 2011 Daniel Müllner <https://danifold.net>
  * All changes from version 1.1.24 on: © Google Inc. <https://www.google.com>
All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

  * Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
  * Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

## NVIDIA Parakeet TDT 0.6B v2 Core ML

FluidAudio downloads
[FluidInference/parakeet-tdt-0.6b-v2-coreml](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml)
at runtime; model weights are not bundled in this repository.
The NVIDIA Parakeet TDT 0.6B v2 model is licensed under
[Creative Commons Attribution 4.0](https://creativecommons.org/licenses/by/4.0/).
The Core ML conversion is provided by FluidInference.
[Original NVIDIA model and attribution](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2).

## Argmax OSS (WhisperKit) 1.1.1

The iPhone app (only the Typr app target, not the keyboard or widgets) uses the
`WhisperKit` product of the Swift package
[argmaxinc/argmax-oss-swift](https://github.com/argmaxinc/argmax-oss-swift/tree/v1.1.1),
pinned with `exactVersion: 1.1.1` in `ios/project.yml` (tag commit
`1bbc57cb7fe6410248a685b1c5a3c6d56adc2ed4`), under the MIT license below.
Portions under `Sources/ArgmaxCore/External` (the Hub client and tokenizers that
WhisperKit uses) are derived from
[huggingface/swift-transformers](https://github.com/huggingface/swift-transformers),
Copyright 2022 Hugging Face SAS, modified by Argmax, Inc., and licensed under the
[Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0); the package's
[NOTICES](https://github.com/argmaxinc/argmax-oss-swift/blob/v1.1.1/NOTICES) file carries
that notice and the full license text and must accompany redistribution.

`ios/Typr/WhisperTokenizer.swift` follows the special-token table and language-token
set of WhisperKit's `WhisperTokenizerWrapper` (`Sources/WhisperKit/Core/Models.swift`
at v1.1.1); see [PORTS.md](PORTS.md).

```text
MIT License

Copyright (c) 2024 argmax, inc.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Whisper Large V3 Turbo model and tokenizer

Typr downloads these at runtime, only when the user taps Download; nothing is
bundled in this repository or the app:

- Core ML model folder `openai_whisper-large-v3-v20240930_626MB` from
  [argmaxinc/whisperkit-coreml](https://huggingface.co/argmaxinc/whisperkit-coreml/tree/0f63a7800b00dd0226abd051b906c246e1907482/openai_whisper-large-v3-v20240930_626MB)
  at revision `0f63a7800b00dd0226abd051b906c246e1907482`, MIT license (Core ML
  conversion by Argmax, Inc.). It is a conversion of OpenAI's Whisper Large V3 Turbo
  ([openai/whisper](https://github.com/openai/whisper), model weights released by
  OpenAI under the MIT license).
- `config.json`, `tokenizer.json` and `tokenizer_config.json` from
  [openai/whisper-large-v3](https://huggingface.co/openai/whisper-large-v3/tree/06f233fe06e710322aca913c1bc4249a0d71fce1)
  at revision `06f233fe06e710322aca913c1bc4249a0d71fce1`, Apache License 2.0.

The OpenAI Whisper model-weight license is reproduced below (the Argmax Core ML
conversion is covered by the Argmax MIT notice above):

```text
MIT License

Copyright (c) 2022 OpenAI

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## OpenWhispr cleanup prompt and output check

Typr's AI cleanup instructions (`ios/Typr/CleanupPrompt.swift`) follow the structure of
OpenWhispr's cleanup prompt and transcript wrapper, and its duplicated-transcript check
(`CleanupGuard.duplicatesTranscript` in `ios/Typr/CleanupGuard.swift`) is translated from
OpenWhispr's cleanup output check; see [PORTS.md](PORTS.md). The notice below is from
[OpenWhispr/openwhispr](https://github.com/OpenWhispr/openwhispr/blob/2e4768a603ec368a0ff11fdd25eb10a31c65b89b/LICENSE).

```text
MIT License

Copyright (c) 2024 OpenWhispr Team

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
