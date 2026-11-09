# Third-party notices

Hex+'s own code and the adopted Hex iOS base are covered by the repository's
[MIT license](LICENSE), whose original © Christopher Langton notice is retained.
Source adoption history, including the inherited MIT OpenCode iOS scope port,
is recorded in [PORTS.md](PORTS.md).

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
