# Design — significant bandwidth

## 1. The question, stated precisely

> **Above which frequency does this file stop carrying persistent signal energy?**

Nine things this is *not*, each rejected for its own reason:

| candidate | why it is rejected |
| --- | --- |
| highest non-zero FFT bin | Every real file has dither and numerical noise everywhere. Answers "Nyquist" always. |
| highest visible spectrogram band | Depends on `defaultMaximumBandCount`, a UI cap. Measured error up to **594 Hz** at 192 kHz. |
| highest bin above an **absolute** dBFS threshold | A quiet programme and a loud one with identical spectra give different answers. Not a property of the content. |
| spectral roll-off percentile (e.g. 99 % of energy) | Dominated by the loud low end; a full-scale bass note puts the "99 % point" near 1 kHz whatever happens above. Measures balance, not extent. |
| the encoder's declared low-pass | Not readable from the decoded signal, and absent for lossless. |
| noise floor | A different quantity; a file can be band-limited *and* noisy above the limit. |
| transient-only high-frequency energy | The failure mode, not the measurement — see the impulse result. |
| Nyquist of the declared rate | The header, which is exactly what the user already distrusts. |
| a "bandwidth score" | An aggregate. Forbidden by the project's own rules. |

**Chosen definition.** The highest frequency at which the signal carries energy **above a stated
threshold, relative to the file's own spectrum, in at least a stated fraction of analysis windows**.

Group 1 measured how many parameters that actually takes, and it is more than three (§3): threshold,
persistence fraction, a **window-eligibility gate**, an **absolute silence floor**, and the analysis
window itself — the persistence fraction is not portable across window lengths. All of them travel with
the result, because the same identifier must imply the same number.

## 2. Why persistence is not optional

Measured, on 5 s stereo at 48 kHz, threshold −60 dB relative to each window's own peak:

| fixture | max over windows | 95th pct | 50th pct |
| --- | --- | --- | --- |
| persistent tones to 20 kHz | 20 133 Hz | 20 133 Hz | 20 133 Hz |
| persistent tones to 16 kHz | 16 148 Hz | 16 148 Hz | 16 148 Hz |
| **one impulse, silence elsewhere** | **23 977 Hz** | **0 Hz** | **0 Hz** |
| digital silence | 0 Hz | 0 Hz | 0 Hz |

A maximum over time answers *23 977 Hz* for a file containing one click. A percentile answers *0*. The
persistence criterion is the whole difference between a measurement and an artefact detector.

## 3. What group 1 settled, and what it did not

The motivating spike settled nothing beyond "the threshold must be relative". Group 1's measurement
campaign is `docs/spikes/2026-08-19-significant-bandwidth-methodology.md`; what follows is its result,
not this document's expectation of it.

**Settled by measurement, on graded fixtures:**

- **Threshold: −50 dB relative to the loudest bin in the same analysis window.** The admissible region
  is [−65, −45], bracketed by fixtures; −50 is its midpoint. The rejected references were measured, not
  argued — the file's overall peak loses a real band to a 2 % transient; global RMS and a robust p95 are
  bin-population statistics that drift 6.0 dB and 41.8 dB across FFT sizes; gated loudness is not
  commensurable with a per-bin magnitude, its offset spreading 32.6 dB across fixtures.
- **Persistence: presence in ≥ 10 % of eligible windows**, restated exactly as the k-th largest of the
  bin's per-window levels with `k = ceil(0.10 · N)` — a nearest-rank-from-the-top p90, not an
  interpolated p90 and not p95.
- **The threshold is a sensitivity, not a discriminator.** A weak band and a low noise floor at the same
  relative level are the same thing spectrally. A persistent band is reported in full at −45 dB, at the
  transition at −50 dB, and not at all at −55 dB.
- **Those two parameters are not sufficient.** No relative reference at any threshold and any persistence
  reports absence for digital silence. A window-eligibility gate at −60 dB below the file's global
  spectral peak (gain-invariant, and inert except on near-silent windows) and an absolute silence floor
  at −120 dBFS are both required.

**Settled by the continuation of group 1:**

- **The resolution claim (§5).** Derived, not observed: the Hann skirt reaches `d(T) = (1/(π·10^(T/20)))^(1/3)`
  bins, 4.72 at −50 dB. The contract is **bin centre plus resolution**; an interval contract was derived
  and then falsified.
- **The analysis window is time-locked at ≈ 42.67 ms**, hop = fftSize/4, realised through the
  non-power-of-two lengths `vDSP_DFT_zrop` accepts. §5's 2048 points is right at 48 kHz and wrong
  everywhere else.

**Still open, and one of them blocking:**

- **The window-eligibility rule (task 1.7) — decided.** A level gate presented as a discovery was
  rejected: its two failure tables are exact mirror images. No gate at all is numerically exact and right
  on seven of eight collector files, but lets a *broadband* floor alone in more than 10 % of a file set
  the answer at any level. Neither spectral flatness (0.564 for both tape hiss and musical "air") nor a
  persistence curve separates them. So the rule is **declared**: a window contributes if it carries
  energy *and* sits within **60 dB** of the file's loudest spectral moment. The cost is stated rather
  than discovered — content more than 60 dB down is not measured, and a floor further down does not count
  as content — and the metric is named **programme bandwidth, within 60 dB of programme peak** so that
  the budget travels with the figure.
- **Absence needs no rule.** A window of zeros transforms to magnitude exactly zero, so it is ineligible
  on its own; the −120 dBFS floor and the file-level energy test that briefly replaced it were both
  artefacts of a magnitude clamp. **The transform must not clamp its magnitudes.** A constant signal is
  DC and legitimately reads 0 Hz, which task 4.4 must handle.

**Still open:**

- **Nothing was measured on real music.** Group 2 took the method onto real files — five rates, five
  lossless containers, AAC, MP3 and rewrap, seven chunk sizes, every file edge — and the fact survived
  all of it, but every fixture is still synthesised from a specification in this repository. No
  commercial recording has been measured, and no listener has looked at a result.

## 3b. What group 2 established

The subject stopped being an array in memory. `ProgrammeBandwidthReference` in `Tests/` implements the
method and is driven by the production decoder, so containers, sample rates, codecs and chunk
boundaries are exercised **before** an accumulator exists rather than after.

- **The resolution contract is `0 ≤ error ≤ 5 × resolution`**, measured: one-sided upward, worst case
  4.55 against the analytic Hann reach of 4.72. Raw hertz are not comparable across rates.
- **Lossless containers read the identical bin**, and so do seven chunk sizes from one frame to the
  whole file — asserted exactly, with no tolerance.
- **Lossy transports move the reading without destroying it**, and rewrapping to PCM preserves the bin.
- **FFmpeg cannot corroborate this quantity**; its `rolloff` measures spectral balance.
- **Five negative controls** break one constant each, so none of them is decoration.

Two things group 2 handed to later groups: an impulse alone in silence reads as broadband (§13d.4 of
the spike), and a bounded accumulator cannot use a plain per-bin counter, because the budget needs the
file's peak — stratifying counters by window peak is one shape that works.

## 4. Architecture

**A sixth consumer of `SharedPCMAnalysisGeneration`, with its own STFT.**

| alternative | verdict |
| --- | --- |
| **A — derive from `Spectrogram`** | **Rejected on measurement.** Max-over-time destroys persistence; band width scales with rate; the caps are documented as free to change. A domain fact would depend on a drawing's parameters. |
| **B — its own accumulator over the shared PCM** | **Chosen.** Full 1025-bin resolution, its own reduction, its own recorded method, independent of any UI constant. |
| C — reuse the spectrogram's FFT output before reduction | **Deferred, and named.** `SpectrogramAccumulator` already computes 1025 bins per hop and discards the resolution; sharing that stage would make this nearly free. It is the right end state and the wrong first step: it couples two accumulators' lifecycles and would land a refactor inside a feature. See §6. |

The dependency rule is unaffected: the accumulator lives in `AudioInspectorAnalysis`, the model in
`AudioInspectorDomain`, and no framework type crosses a port.

## 5. Resolution and uncertainty

The FFT was to be 2048 points, so a bin is `sampleRate / 2048` wide: **21.5 Hz at 44.1 kHz, 93.8 Hz at
192 kHz**. A Hann window spreads a pure tone across neighbouring bins, so the true edge is known no more
precisely than a bin, and in practice a little less.

**Derived, and worse than that.** The Hann transform is `|W(d)| = |sin(πd)|/(π|d||d²−1|)`, verified
against the true DTFT to 0.000 dB, and its skirt falls as `1/d³`. A relative threshold `T` therefore
stays above it out to **`d(T) = (1/(π·10^(T/20)))^(1/3)` bins — 4.72 at −50 dB**. That is the
uncertainty: not the bin width, not the 4-bin main lobe, not bin quantisation. It is one-sided upward
and depends on where the content's edge falls inside a bin, from **1 bin** (edge on a bin) to `d(T)`.

The reported value is therefore a **bin centre plus the resolution it was measured at**. A lower/upper
bound contract was derived and then falsified — coherent tones one bin apart overshoot by 8.5 bins — and
must not be reintroduced. **Display granularity must be coarser than the bias**, which is 23–111 Hz at a
42.67 ms window: a tenth of a kHz is the finest defensible step.

The window is **time-locked at ≈ 42.67 ms** with 75 % overlap, because the persistence criterion is
defined on windows and a sample-locked one makes it rate-dependent: ten bursts totalling 5 % of a file
read 12.65 % of windows at 44.1 kHz and 6.73 % at 192 kHz. `fftSize` and `hop` are part of the method
identity.

**The measurement therefore reports a frequency together with the resolution it was measured at**, and
the surface must not print more precision than that supports. `21.73 kHz` is a lie at 192 kHz;
`≈ 21.7 kHz` with a stated bin width is not. The domain carries the number and the bin width; rounding
for display is presentation's job, as it already is for loudness.

## 6. Relationship to `average spectrum`

`docs/roadmap.md` also lists an average spectrum, unbuilt. Both want the same STFT. The order that
avoids computing it twice:

1. **this change** — its own STFT, its own reduction, no shared stage;
2. **a later change** — extract the STFT stage once `average spectrum` gives it a second consumer, and
   move both onto it, with equivalence proved against the values this change already pins.

Building the shared stage now would be designing for one consumer and guessing at the second's needs.

## 7. What the wire and the surface may say

A **fact**, with its methodology, and nothing else. The presentation states what was measured —
*"highest frequency region carrying persistent energy above the analysis threshold"* — and never why.
The export carries the value, the resolution, and the method identity, additively under `measurements`,
with `schemaVersion` still 1.

## 8. The inference this enables later, and its limits

Recorded here so the boundary is explicit before anyone crosses it, in the repo's own vocabulary
(`docs/analysis-methodology.md`):

- **Evidence** — *declared sample rate 96 kHz; significant bandwidth ≈ 21.8 kHz at 93.8 Hz resolution.*
- **Inference** (a later change) — *compatible with a source of narrower bandwidth than the declared
  rate implies*, with alternatives that must travel with it: an analogue or band-limited master,
  deliberate filtering, programme material with no high-frequency content, a prior encoder, or a
  lower-rate source.
- **Conclusion limit** — it does **not** demonstrate upsampling, does **not** demonstrate transcoding,
  and does **not** identify a source codec. One indicator is not an evidence engine.

## 9. Comparison between two files

Deferred to its own change, and the shape is noted so it is not improvised: two bandwidths are
comparable only **within their resolutions**, so the outcome is an overlap test rather than equality —
21 800 Hz ± 94 and 21 850 Hz ± 94 are not "different". `FileComparison` compares only technical
properties today, and a measurement comparison is an extension of its contract rather than a row added
to it.
