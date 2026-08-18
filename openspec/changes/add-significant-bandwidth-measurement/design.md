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
Three parameters, all of which travel with the result: threshold, persistence fraction, and the
resolution the answer is quantised to.

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

## 3. What the spike did **not** settle

Honesty about the gap, because it determines the first task group:

- **The threshold is undetermined.** Sweeping −20 → −100 dB moved the answer only 328 Hz, but the
  fixture has an *infinitely sharp* edge — no content above 20 kHz at all — so it cannot discriminate
  between thresholds. **Graded fixtures** (a roll-off, not a cliff) are required before any value is
  fixed.
- **The persistence fraction is undetermined.** p50 and p95 agreed on every fixture tried, because each
  was stationary. Non-stationary programme material is needed to separate them.
- **Nothing was measured on real music**, only on synthetic signals.

None of these may be chosen by intuition. Group 1 settles them by measurement, before an accumulator
exists — the order `add-loudness-measurement` used, and the reason its constants survived review.

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

The FFT is 2048 points, so a bin is `sampleRate / 2048` wide: **21.5 Hz at 44.1 kHz, 93.8 Hz at
192 kHz**. A Hann window spreads a pure tone across neighbouring bins, so the true edge is known no
more precisely than a bin, and in practice a little less.

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
