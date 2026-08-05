# Spike report — static spectrogram: STFT configuration, reduction and cost

> **What this is.** Group 0 of change `add-static-spectrogram-visualization`, run **before** any
> contract, ADR or production code was written. It answers one question: does the proposed
> configuration actually let a collector see where a file's content stops?
>
> **What it is not.** It is not production code, not a benchmark suite, and not evidence that any file
> is a transcode. Every figure below is a measurement of a drawing, never a verdict about audio.

- **Date prepared**: 2026-08-06
- **Branch**: `spike/validate-static-spectrogram`
- **Package**: `Spike/validate-static-spectrogram/` — its own SwiftPM package, deliberately **outside**
  the production graph. The root `Package.swift` is untouched, so `swift build` at the repository root
  never sees it.
- **Related**: ADR-0003 (native-first; FFmpeg as a dev/test tool only), ADR-0005, ADR-0011 (the port's
  semantic boundary), **ADR-0015** — whose written reversal condition is precisely what this spike
  triggers — `docs/architecture.md`, `docs/concurrency.md`, `docs/testing-strategy.md`, and the PCM
  decoding spike of 2026-08-05 whose format matrix this reuses.

## Objective

Decide, with runnable evidence, whether the following configuration is fit to be written into a
contract — **or find out that it is not, before the contract exists**:

`vDSP.DiscreteFourierTransform<Float>` · FFT 2048 · hop 512 · Hann denormalised · absolute magnitude ·
reference 1.0 · 20·log10 · floor −120 dBFS · linear frequency to Nyquist · at most 1024 columns ×
512 bands · reduced by **maximum** · channels combined by maximum.

## How to reproduce

```bash
cd Spike/validate-static-spectrogram
swift build -c release -Xswiftc -warnings-as-errors
swift run  -c release StaticSpectrogramSpike
```

It writes nothing inside the repository: real-file fixtures are generated into a fresh temporary
directory and removed on exit. The mathematics gates need **no external tool**. Only the real-file gate
uses FFmpeg; when FFmpeg is absent that gate is **SKIPPED**, loudly, and a skip is never counted as
evidence. A failure inside the gate stays a failure and is never downgraded to a skip.

## Environment

| | |
| --- | --- |
| macOS SDK | 26.5 |
| Swift | 6.3.3 (`swiftlang-6.3.3.1.3`), Swift 6 language mode, `-warnings-as-errors` |
| Architecture | arm64 |
| Build configuration for every timing below | **Release** |
| FFmpeg (real-file gate only) | 8.1.2 with `libmp3lame` |

> **SDK-dependence caveat**, inherited from the PCM spike: every observation comes from **one**
> OS/SDK on one machine. The *semantic* conclusions carry forward; the timings do not.

## Result

**67 checks, 0 failures, 0 skips**, from a clean `.build` on the machine described above.

---

## A — Elementary mathematics

Synthetic signals only. If the scale were wrong here, every later gate would be measuring the wrong
thing.

| Case | Observed | Verdict |
| --- | --- | --- |
| Silence | exactly −120.0 dBFS everywhere | PASS |
| DC at 0.5 | preserved in the lowest band, −0.00 dBFS | PASS |
| Tone on a bin, amplitude 1.0 | −0.00 dBFS, **error −0.000 dB** | PASS |
| Tone on a bin, amplitude 0.5 | −6.02 dBFS, **error −0.000 dB** | PASS |
| Tone on a bin, amplitude 0.1 | −20.00 dBFS, **error +0.000 dB** | PASS |
| Tone exactly between bins | −7.44 dBFS: **scalloping loss 1.42 dB** | PASS |
| Two tones (1 kHz @ 0.5, 10 kHz @ 0.05) | −7.12 and −26.92 dBFS | PASS |
| Impulse | **512/512** bands above −80 dBFS | PASS |
| Sample at 1.5 (finite, beyond full scale) | **+3.52 dBFS, not clamped** | PASS |
| Two files 20 dB apart | **20.00 dB** apart in the model | PASS |

**The scale factor is `1 / windowSum`.** `2 / windowSum` is the natural mistake — the real-to-complex
packing invites it — and reads 6 dB high. The three exact amplitude readings above are what pins it.

**Scalloping loss is 1.42 dB, which is Hann's theoretical maximum**, reached because the test placed a
tone exactly halfway between two bins. This is a property of any STFT, not a defect, and it is the
first reason the drawing must not be presented as a measurement of level.

## B — Cutoff discrimination

The gate that decides whether the slice is worth building. Brick-wall low-passed pink noise, cutoff
applied in the frequency domain so it is exact.

| Sample rate | Reduced band | 16↔18 kHz | 18↔19 | 19↔20 | 20↔22 | Edge error |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 44 100 Hz | 43.1 Hz | 47.0 bands | 23.0 | 23.0 | 45.0 | +28…+109 Hz |
| 48 000 Hz | 46.9 Hz | 43.0 | 21.0 | 21.0 | 43.0 | +86…+117 Hz |
| 96 000 Hz | 93.8 Hz | 22.0 | 11.0 | 10.0 | 22.0 | +172…+266 Hz |
| 192 000 Hz | 187.5 Hz | 11.0 | **5.0** | **6.0** | 10.0 | +406…+531 Hz |

Unfiltered noise reaches Nyquist at every rate (22 028 / 23 977 / 47 953 / 95 906 Hz).

**Every pair is separable at every sample rate**, with the narrowest margin — 5 reduced bands — at
192 kHz between 18 and 19 kHz. **1024 × 512 is sufficient.**

The observed edge always lands slightly *above* the true cutoff, by roughly one reduced band, because
the band containing the cutoff still holds energy from below it. **The uncertainty on a reported edge
is therefore about one reduced band**, and grows with the sample rate: ±43 Hz at 44.1 kHz, ±188 Hz at
192 kHz. Any text that quotes an edge must carry that uncertainty.

## C — Maximum against mean

**A first version of this gate was wrong, and saying so is the point of writing it down.** It used a
signal short enough that every STFT frame became its own column: nothing was folded, the two
strategies came out 0.2 dB apart, and the comparison proved nothing. Redone over 60 s — 5 164 frames
folded into 1 024 columns, roughly five frames per column:

| Case | Maximum | Mean |
| --- | ---: | ---: |
| 20 ms transient of 15 kHz in 60 s of silence | **−9.10 dBFS** | **−17.84 dBFS** |
| 1 s of 15 kHz every 10 s | −6.93, visible in 111/1024 columns | −7.49, visible in 110/1024 |
| Abrupt 16 kHz cutoff | step of **88.3 dB** | step of 85.8 dB |
| One isolated 46 ms click | **3/1024 columns** | 3/1024 columns |

**The mean buries a short transient by 8.74 dB.** For a forensic instrument that is the deciding
number: a brief burst of high-frequency content is exactly the kind of thing a user is looking for,
and averaging it against its silent neighbours hides it.

**The risk of the maximum was checked rather than assumed.** An isolated click lights 3 columns of
1 024 — the same as the mean — so the maximum does not smear one artefact into a surface. That result
is specific to a sparse click: **a file with dense impulsive noise would light more columns under
either strategy**, and this spike does not claim otherwise.

## D — Channel combination, with a negative control

**The strategy proposed first was wrong, and the gate keeps it as a reproducible negative control.**
Two channels carrying *different* pure tones, each at 0.5, so each should read −6.02 dBFS:

| Strategy | 5 kHz | 10 kHz | Spurious bands above −80 dBFS |
| --- | ---: | ---: | ---: |
| Maximum over **samples** (time domain) | −10.27 dBFS | −7.95 dBFS | **247**, worst −13.69 dBFS |
| Maximum over **magnitudes** (frequency domain) | **−6.02** | **−6.02** | **0** |

Taking whichever channel's sample is louder synthesises a waveform that exists in neither channel, and
the transform faithfully reports the content of that invented signal: 247 bands of energy that are not
in the file. **For an instrument whose whole job is to show where energy stops, invented energy high
up could conceal a real cutoff.** It is not an alternative the product may choose.

With per-channel transforms combined by maximum per bin, all four invariants hold:

- a tone present in one channel alone survives — **PASS**
- left-only and right-only are indistinguishable — **PASS**
- identical channels read as one — **PASS**
- opposite polarity does not cancel (−6.02 dBFS, not silence) — **PASS**
- no normalisation across channel layouts: 20.00 dB apart — **PASS**

**This is a combined envelope across channels. It is not a mono mix and not a downmix**, and must not
be described as one anywhere in code, tests or UI.

**Cost**: one transform per channel, run sequentially. Measured at **1.6–1.7×** for stereo over mono.
Accepted knowingly. **No timing is promised for more than two channels.**

## E — Edges

| Case | Observed |
| --- | --- |
| File shorter than one FFT window | a model at the floor, nothing fabricated |
| **Zero-padding the final frame** | a 0.5 tone reads **−12.47 dBFS instead of −6.02** |
| Zero-length input | model entirely at the floor |
| Sample rate 0, zero channels, negative counts | all refused |
| Sample rates 22 050 and 8 000 Hz | frequencies mapped correctly |
| Chunking at 1 / 512 / 1024 / 4096 / 65 536 frames | **identical models** |
| Same input twice | **identical** |
| Cancellation | **nil** — nothing partial presented as complete |

**Decision: the final incomplete frame is discarded, never zero-padded.** Padding invents samples the
file does not contain and reads the level low, as the −12.47 dBFS figure shows. At most `fftSize - 1`
frames — 46 ms at 44.1 kHz — go undrawn, which is preferable to drawing something the file does not
say.

**Two observations the contract must act on:**

1. **A zero-length file yields a floor-filled model, not an absence.** The domain type should decide
   whether zero frames means an empty model or no model at all, the way `WaveformEnvelope` did.
2. **A single NaN sample does not leak a non-finite value into the model — and that is the problem.**
   The clamp absorbs it, but **184 cells collapsed to the floor** that otherwise would not have, so a
   corrupted region reads as *an absence of energy* rather than as a fault. **The domain must reject
   non-finite samples at the boundary**, exactly as `WaveformBucket` already does, instead of relying
   on this clamp to hide them.

## F — Cost, memory and confinement

All figures **Release**. Debug figures are not comparable and none are quoted here.

| | |
| --- | --- |
| Reduced model | 1024 × 512 `Float` = **2 048 KiB (2.00 MiB)**, independent of duration |
| Scratch | one FFT frame 8 KiB + magnitudes 4 KiB |
| Cost per transform, setup **reused** | **0.0018 ms** |
| Cost per transform, setup **recreated per frame** | 0.0185 ms — **10.0× slower** |
| 10 s mono | 22 ms |
| 60 s mono | 127 ms |
| 5 min mono | **631 ms** |
| 60 s stereo (sequential channels) | 211 ms — 1.7× mono |
| **1 hour** | **≈7.6 s mono, ≈12.5 s stereo — EXTRAPOLATED from the 5 min figure, not measured** |
| 10 s at 44.1 / 96 / 192 kHz | 22 / 46 / 94 ms |

**The transform setup is created once per operation and reused.** Recreating it per frame costs ten
times as much, which is the difference between a second and ten for a five-minute file.

**Concurrency, measured rather than argued:** `vDSP.DiscreteFourierTransform<Float>` is **not
`Sendable`**, and neither is `vDSP.FFT<DSPSplitComplex>` — both were confirmed by compiling a
`Sendable` requirement against them under Swift 6 and reading the error. The accumulator that owns one
is therefore not `Sendable` either, and is created and consumed inside a single `nonisolated async`
function. **That this package builds in Swift 6 language mode with `-warnings-as-errors` and no
`@unchecked Sendable` anywhere is the evidence for that claim.**

A second, smaller confirmation of the same rule: the spike's own result ledger was rejected by the
compiler as a bare mutable global and had to be actor-isolated. The correct diagnosis, accepted rather
than worked around.

## G — Real files

Pink noise → WAV; FLAC and MP3 (128 kbit/s) encoded from it; then that MP3 decoded back to WAV.
Read through `AVAudioFile`, consuming exactly `buffer.frameLength` and never `frameCapacity`.

| File | Highest band above −90 dBFS |
| --- | ---: |
| `source.wav` | 22 028 Hz |
| `lossless.flac` | 22 028 Hz |
| `encoded.mp3` | **16 774 Hz** |
| `transcoded.wav` | **16 774 Hz** |

Peak dBFS per frequency, across the whole file:

| kHz | source | flac | mp3 | transcoded |
| ---: | ---: | ---: | ---: | ---: |
| 16.0 | −48.2 | −48.2 | −49.1 | −49.1 |
| 16.5 | −50.6 | −50.6 | −50.6 | −50.6 |
| **17.0** | **−49.0** | **−49.0** | **−110.9** | **−108.7** |
| 20.0 | −51.8 | −51.8 | −117.9 | −117.3 |

- **WAV and FLAC of the same audio produce *identical* models.** The container does not change what the
  spectrogram observes.
- **The cutoff survives rewrapping**: the MP3 and the WAV decoded from it report the same edge,
  16 774 Hz. A lossless-looking container does not hide a lossy history from this drawing.
- Reading the same file in chunks of 1, 512 and 4 096 frames gives identical models.

## What this evidence supports, and what it does not

**It supports** saying where a file's energy stops, that the drop is abrupt, and that the container
does not change that observation.

**It does not support** saying *why* energy stops. A cutoff near 16.8 kHz is compatible with lossy
encoding, with the master, and with deliberate filtering, and nothing measured here separates them.
Two independent limits reinforce this: **1.42 dB of scalloping loss** and **an edge uncertainty of one
reduced band** (±43 Hz at 44.1 kHz, ±188 Hz at 192 kHz). This is a drawing of energy distribution, not
an instrument of measurement, and the UI must not present it as one.

**Automatic detection of lossy origin is explicitly out of scope** for the slice this spike serves. It
belongs to a later capability that must work with observable reasons, alternative explanations and
confidence — never a verdict.

## Corrections to the proposal this spike was written to test

1. **Channels are combined in the frequency domain, not the time domain.** The original proposal did
   not specify the domain; combining samples was measured to invent 247 bands of content. Costs
   1.6–1.7× for stereo.
2. **The final incomplete frame is discarded.** Previously undecided; padding was measured to
   understate level by 6.45 dB.
3. **Maximum over mean is now supported by a number** — 8.74 dB on a short transient — rather than by
   reasoning.

Everything else in the proposal survived unchanged.

## Falsification criteria, written before the measurements

If any of these had been met, the configuration would **not** have been adopted:

1. Cutoffs at 18 and 19 kHz indistinguishable in the reduced model at any target sample rate — **not
   met**.
2. The scale requiring a fudge factor to read a known amplitude correctly — **not met** (error 0.000 dB).
3. The transform setup impossible to confine without `@unchecked Sendable` — **not met**.
4. The model growing with file duration — **not met** (2.00 MiB constant).
5. Chunk size changing the result — **not met** (identical at every size, including one frame).
6. A five-minute file taking longer than a few seconds in Release — **not met** (631 ms mono).

## Deletion criterion

This package is deleted once **ADR-0016 is Accepted** and the slice's own tests cover these
observations — the same criterion the PCM decoding spike carries. Until then it stays reproducible, and
this report is the durable record of what it measured.
