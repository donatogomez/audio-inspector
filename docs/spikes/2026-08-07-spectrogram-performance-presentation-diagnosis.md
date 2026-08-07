# Diagnosis — static spectrogram performance and presentation

> **What this is.** A measurement pass run **after** the spectrogram shipped behind
> `add-static-spectrogram-visualization`, triggered by a manual observation: a real 6:56 MP3 took
> **tens of seconds** to draw when the app was run from Xcode, while the report and the waveform
> appeared immediately.
>
> **What it is not.** It is not a benchmark suite, not a contract, and not a promise about any
> machine. Every figure below is one run on one host, and the timings do not carry forward. The
> *semantic* conclusions — where the cost sits, what scales with what, what is and is not quadratic —
> do.

- **Date prepared**: 2026-08-07
- **Trigger**: group 10 manual validation, paused at step 1
- **Related**: **ADR-0016** (this diagnosis revises two of its expectations while it is still
  `Proposed`), `docs/spikes/2026-08-06-static-spectrogram-validation.md` (the original spike, whose
  Release figures this corroborates), change `add-static-spectrogram-visualization` group 12

## Environment

| | |
| --- | --- |
| macOS | 26.3 (25D125) |
| Xcode | 26.6 (17F113) |
| Swift | 6.3.3 (`swiftlang-6.3.3.1.3`), Swift 6 language mode |
| Host | Apple M1 Pro, arm64 |
| Builds compared | `swift test` (Debug) and `swift test -c release` (Release) |

## Fixtures

Generated with FFmpeg **outside the repository** and not versioned. Pink noise rather than music, so
the content is deterministic and the decode path is exercised without copyrighted material.

| Fixture | Content |
| --- | --- |
| `m-07.mp3` | 6:56, 44.1 kHz, stereo, CBR 192k — the shape of the file that triggered this |
| `w-07.wav` | the same PCM as 16-bit WAV, so decode cost can be separated from analysis |
| `m-01.mp3` | 1:00, same parameters |
| `m-15.mp3` | 15:00, same parameters |

## Method

Four passes per fixture, each timed with `ContinuousClock`, and every stage obtained by **subtraction**
rather than estimated:

| Pass | What it runs |
| --- | --- |
| **A** `rawRead` | `AVAudioFile` into a reused buffer, touching samples, building nothing |
| **B** `decodeOnly` | the production decoder, discarding every chunk — adds `PCMChunk` construction |
| **C** `decode+accumulate` | adds the STFT and both reductions, stopping short of `finish()` |
| **D** `fullGeneration` | `SpectrogramGeneration.run` — adds `finish()` and the model |

The harness was disposable and is **not** versioned: it reconstructs from this description in a few
minutes, and a permanent copy would be a second implementation of the pipeline to keep in step.

**One measurement was discarded.** The first Debug sweep ran while a Release benchmark was executing
concurrently, and produced an impossible result (`D < C`, i.e. the superset cheaper than the subset).
It was rerun with the machine otherwise idle; only the clean run is reported.

## A — The headline

`m-07.mp3`, 6:56 stereo, 18 345 600 frames, 4 479 chunks, 35 828 STFT windows, 71 656 transforms:

| Stage | Debug | Release | Debug / Release |
| --- | ---: | ---: | ---: |
| `AVAudioFile` raw read | 609.7 ms | 583.3 ms | **1.0×** |
| decode incl. `PCMChunk` | 9 278.1 ms | 561.8 ms | 16.5× |
| ↳ `PCMChunk` copy + finiteness scan | 8 668.3 ms | ≈ 0 | — |
| STFT + reduction | 47 758.0 ms | 689.9 ms | **69×** |
| `finish()` + model | 433.5 ms | ≈ 0 | — |
| **Total generation** | **57 469.6 ms** | **1 225.1 ms** | **47×** |

`w-07.wav`, the same audio without the MP3 decode: Debug 56 239.6 ms, Release 715.4 ms. Raw read
36.2 ms Debug / 32.5 ms Release, so **the MP3 decode itself costs ≈17× the WAV decode** in Release
(562 ms against 33 ms).

**The control that settles it: the raw `AVAudioFile` read is the same speed in both builds (1.0×).**
AVFoundation is precompiled system code, so the optimiser cannot be the difference there. Everything
above 1.0× is *our* Swift, unoptimised. The 47× is a build-configuration effect, not an algorithmic
defect — but it is what a developer running from Xcode actually experiences.

Release at ≈1.2 s for a 7-minute file is consistent with the original spike, which measured 631 ms for
5 minutes mono. Scaled for duration and stereo that predicts ≈1.5 s; the measured 1.2 s is slightly
better. **The original spike's numbers were not wrong.** Its figures appear to cover the transform over
already-materialised PCM — it reports decode nowhere in that table — and for MP3 the decode is roughly
as expensive again as the transform, which is the part the headline figure never included.

## B — Everything scales linearly; nothing is quadratic

Release, normalised per million frames across three durations:

| Fixture | Mframes | decode ms/Mf | STFT+reduction ms/Mf |
| --- | ---: | ---: | ---: |
| `m-01.mp3` | 2.65 | 30.46 | 35.71 |
| `m-07.mp3` | 18.35 | 30.62 | 37.60 |
| `m-15.mp3` | 39.69 | 30.66 | 37.36 |

Flat across a **15× range of durations**. `SpectrogramAccumulator.compactPending` uses
`Array.removeFirst`, which is O(n) in what remains — but it operates on a buffer bounded by a few
thousand frames and is amortised against the frames it retires, so the total stays linear. **No
quadratic behaviour was found anywhere in the pipeline.**

## C — Where the allocations are

Counted for `m-07.mp3` (71 656 transforms, 4 479 chunks):

| Source | Arrays | `Float`s materialised |
| --- | ---: | ---: |
| `PCMChunk` (one per channel per chunk) | 8 958 | 36.7 M |
| `SpectrogramAccumulator.transformChannel` | **286 624** | **≈293 M** |

`transformChannel` allocates **four** 1024-element arrays per transform: `evens`, `odds`, and the two
`dft.transform(real:imaginary:)` returns. The even/odd split alone copies ≈146.7 M elements through
`stride(...).map`.

So the transform's transient churn is **≈32× the volume of the PCM copy** that group 9 spent a whole
audit on. In Release the optimiser hides nearly all of it; in Debug it does not.

**What is *not* wrong:** the `vDSP.DiscreteFourierTransform`, the Hann window and the scratch buffers
`windowed` / `magnitudes` / `combined` are stored properties built **once per operation**. The original
spike measured a 10× penalty for recreating the setup per frame, and production did not fall into it.
The problem is strictly the per-transform temporaries.

## D — Rendering: `Canvas` against a raster prototype

Measured with `ImageRenderer` off-screen at `scale = 2`, median of three runs after a warm-up.

| Grid | cells | Canvas (Release) | raster build | raster redraw | Canvas (Debug) | raster build (Debug) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1024 × 512 | 524 288 | 213.0 ms | 6.5 ms | **0.1 ms** | 611.5 ms | 307.8 ms |
| 1024 × 256 | 262 144 | 102.7 ms | 3.0 ms | 0.1 ms | 307.2 ms | 156.2 ms |
| 768 × 384 | 294 912 | 116.5 ms | 4.5 ms | 0.2 ms | 341.0 ms | 176.2 ms |
| 512 × 256 | 131 072 | 53.0 ms | 1.5 ms | 0.1 ms | 153.1 ms | 78.1 ms |

Resize is the case that matters, because a `Canvas` re-runs on every size change:

| Width | Canvas (Release) | raster (Release) |
| --- | ---: | ---: |
| 400 pt | 210.1 ms | 0.1 ms |
| 700 pt | 203.7 ms | 0.1 ms |
| 1000 pt | 212.8 ms | 0.1 ms |
| 1400 pt | 210.7 ms | 0.1 ms |

The Canvas costs the same at every width — it is driven by the cell count, not the area — so widening
the window buys nothing. **A raster redraw is roughly three orders of magnitude cheaper.**

**The `Canvas` closure runs once per render**, not dozens of times: instrumenting it counted exactly
524 288 fills per render pass over four renders. The 30 s was never the renderer; the renderer is a
separate, smaller problem that shows up during resize.

> **Limit of this measurement.** `ImageRenderer` rasterises off-screen on the CPU. The on-screen
> `Canvas` may be faster, and this method **cannot distinguish the two**. Treat the Canvas figures as
> an upper bound on a redraw rather than as the compositor's real cost. The raster figures are less
> exposed to this, because the expensive part there is building the buffer, which is plain arithmetic.

## E — Resolutions evaluated, and why 1024 × 512 stays

**Analysis cost does not depend on the grid at all.** It is driven by the number of STFT windows, which
comes from the duration and the hop. Shrinking the grid changes only the render — and the raster
strategy already reduces that to 0.1 ms. There is no performance argument for a smaller grid.

Against that, the original spike measured cutoff separability with 512 bands and found the **narrowest
margin at 5 reduced bands**, between 18 and 19 kHz at 192 kHz. Halving to 256 bands would halve that to
≈2.5 bands and put the forensic purpose at risk in exactly the case the capability exists for.

**Conclusion: keep 1024 × 512, FFT 2048, hop 512, Hann, linear frequency, full Nyquist, −120 dBFS
floor, maximum in both axes, channels combined in the frequency domain.** Nothing here justifies
trading resolution for speed.

## F — Palette

The current ramp is **strictly increasing in luminance** (0.023 → 0.974, Rec. 709) and distributes it
sensibly: 12.6 % of the range below −90 dBFS, **57.0 % across −90…−30 dBFS** where music actually sits,
30.4 % above. On luminance it is sound, and the accessibility guarantees it was built for hold.

Its weakness is **hue travel**, and it is measurable. Sampled every 15 dB:

| dBFS | −105 | −90 | −75 | −60 | −45 | −30 | −15 | 0 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| current | `#0E133C` | `#16216B` | `#194984` | `#1C729E` | `#3B9CA8` | `#5BC6B2` | `#AAE0CC` | `#F9F9E5` |

Four of eight samples sit in the cyan-teal family; between −60 and −15 dBFS the hue barely moves, so
two levels 45 dB apart can read as similar colours even though their luminance differs.

**A Spek-style ramp was evaluated and fails objectively**, which is worth recording because it looks
attractive: black → blue → cyan → green → yellow → orange → red → white is **not monotonic in
luminance**. It rises to 0.757 at yellow, then falls to 0.642 at orange and 0.399 at red before jumping
to white. In greyscale, and for a reader with colour vision deficiency, a loud red band would read as
*quieter* than a mid-level yellow one. ADR-0016 rejected that ramp on a standing rule about colour
never meaning good or bad; this measurement shows the rejection was also technically correct.

### Candidate D — adopted

Cool → warm, with stops concentrated where an inspector reads:

| position | R | G | B |
| ---: | ---: | ---: | ---: |
| 0.00 | 0.015 | 0.015 | 0.045 |
| 0.12 | 0.055 | 0.045 | 0.180 |
| 0.25 | 0.110 | 0.090 | 0.380 |
| 0.40 | 0.130 | 0.250 | 0.580 |
| 0.55 | 0.110 | 0.450 | 0.640 |
| 0.70 | 0.230 | 0.660 | 0.560 |
| 0.82 | 0.620 | 0.810 | 0.380 |
| 0.92 | 0.930 | 0.880 | 0.420 |
| 1.00 | 0.995 | 0.985 | 0.930 |

Luminance 0.017 → 0.983, strictly increasing at every sampled point. Share of the luminance range:
10.1 % below −90 dBFS, **53.8 % across −90…−30**, 36.0 % above — within a few points of the current
ramp, so nothing is lost where it matters. Hue travel: `#1C1660 → #1D619E → #2B8D99 → #64B87B →
#C9D866 → near-white`, which moves through indigo, blue, teal, green and yellow-green instead of
sitting in cyan.

A warmer magma-style alternative was also evaluated and **rejected on measurement**: strictly
increasing, but it spends only 37.8 % of its luminance on −90…−30 dBFS, putting the contrast where
music rarely is.

**The −120…0 dBFS scale is unchanged.** The ramp maps the picture; it never touches
`Spectrogram.values`.

## G — What this diagnosis does and does not support

**It supports**: replacing the per-cell renderer with a raster one; removing the per-transform
temporaries in `transformChannel`; adopting candidate D; and keeping the resolution exactly as it is.

**It does not support** any claim about a specific machine's timings, about the on-screen compositor's
real cost, or about how any other spectrogram application is implemented. Nothing here was compared
against another product's source, and no such comparison is needed to act on the numbers above.

**It also does not establish** that Debug will become comfortable after the allocation work. That is
the open question the follow-up must answer with the same method, and if Debug still takes tens of
seconds afterwards, that has to be said rather than absorbed.

## Falsification criteria, written before the work that follows

The raster renderer is **not** adopted unless it demonstrably preserves: one model cell per logical
pixel, band 0 at the bottom, the first column at the left, zero interpolation, no change to
`Spectrogram`, a resize that neither rebuilds the buffer nor re-runs the transform, and the existing
accessible label and legend. The buffer-reuse work is **not** adopted unless the model it produces is
identical — or, if the modern API differs in the last float, unless that difference is measured and
explained rather than absorbed into a tolerance.

---

## H — After the corrections

Same method, same fixtures, same host, measured once the raster renderer, the reused STFT buffers and
the new ramp were in place.

### Generation, `m-07.mp3` (6:56 stereo)

| Stage | Before | After | Change |
| --- | ---: | ---: | ---: |
| **Release** STFT + reduction | 689.9 ms | **290.4 ms** | **2.4× faster** |
| **Release** total generation | 1 225.1 ms | **846.9 ms** | 1.4× faster |
| **Debug** STFT + reduction | 47 758.0 ms | **35 988.1 ms** | 1.33× faster |
| **Debug** total generation | 57 469.6 ms | **42 316.2 ms** | 1.36× faster |

`w-07.wav`, which isolates the analysis from the MP3 decode: Release total 715.4 → **334.2 ms**
(2.1× faster), Debug 56 239.6 → **41 910.9 ms**.

### Rendering

| | Before (`Canvas`) | After (raster) |
| --- | ---: | ---: |
| Release, first draw | 213.0 ms | 6.9 ms build + 0.31 ms wrap |
| Release, **redraw / resize** | 210 ms *per frame* | **0.1 ms** |
| Debug, first draw | 611.5 ms | 424.6 ms build + 0.40 ms wrap |
| Debug, **redraw / resize** | 611 ms *per frame* | **0.1 ms** |

The build happens **once per model**; a resize does not re-enter it, because
`SpectrogramRaster.buffer(for:)` takes no size and the view holds the result in state keyed on the
model. That is the change that makes a live resize free rather than merely cheaper.

### What did not get fixed, stated plainly

**Debug is still ≈42 s for a seven-minute file.** Removing 286 624 allocations bought 26 %, not an order
of magnitude, and it would be dishonest to close this work implying otherwise.

The remaining Debug cost is **per-element Swift loops that were never the churn**: the magnitude loop
runs 1 023 square roots per transform (≈73 M for this file) and `foldIntoGrid` runs 1 025 band lookups
per window (≈36.7 M), both with bounds checking and without vectorisation in an unoptimised build.
Neither allocates, so neither was in scope for the work this diagnosis authorised.

Two things follow. First, **Release is the configuration any performance claim should be made in**, and
there the whole generation is now under a second for seven minutes of audio. Second, if the Debug
experience is worth more work, the target is those two loops — `vDSP` can compute the magnitudes and the
scaling in one call each — and that is a separate, measurable piece of work rather than a continuation
of this one.

### Equivalence

The optimisation changed **no value**. Every analysis suite passed untouched: the scale readings, DC and
Nyquist unpacking, scalloping, two tones, the impulse, channel combination, opposite polarity,
chunk-size independence down to one frame, the cutoff separations at 44.1/48/96/192 kHz, the lossless
container matrix and the FFmpeg-gated MP3 row. No tolerance was widened and none needed to be — the
modern `transform(inputReal:inputImaginary:outputReal:outputImaginary:)` overload is the same transform
writing into buffers the caller owns.
