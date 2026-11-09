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
