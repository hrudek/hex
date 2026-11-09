# iOS test audio

`term-hex-1.wav` is the synthetic fixture used by `HEXMobileTests`.
It was adopted from `anomalyco/hex` at `cae389a833178c5e104e6d00db894078afc29ea0`,
with provenance preserved from `tests/fixtures/vocabulary/README.md` and
`manifest.json` at `split/base` (`6f19d87b`).

- Generation: ElevenLabs, model `eleven_v4`, Kit's authorized cloned voice
  (`8olojUk4IXpvKgaOCHXj`), stability 0.5, similarity 0.75.
- Format: mono 16 kHz PCM WAV, duration 2.08 seconds.
- Reference (exact TTS input, not a human-audited transcript):
  “I use Hex to dictate my notes.”
- This is not a recording of Kit speaking. No audio was played aloud during
  generation. The synthetic audio and authored sentence are provided under
  this repository's [MIT license](../../LICENSE).
- SHA-256: `01211cba2a40f03f914a92d761332dfef9ecb166e6031cc4378303b7f51e261d`.

The file is an explicit resource in `ios/project.yml`, outside the test source
folder to avoid duplicate resource discovery. Moving it did not change its bytes.
