# Design — true peak measurement

## 1. What this document is, and what it is not

It answers, before any DSP is written: what true peak *is* normatively, what ADR-0006 already fixes and
what it leaves open, which native API can implement the methodology without changing its meaning, where
the value lives in the domain, how it is produced, presented and exported, and how it relates to the
clipped-sample count already shipping.

**It commits to no constant that has not been measured.** Every value pinned below — the interpolation
filter, the oversampling factor, the edge policy, the arithmetic width, the cross-check tolerance —
comes from the group-2 spike, recorded in
`docs/spikes/2026-08-11-true-peak-methodology-validation.md`. That is the same discipline
`add-static-spectrogram-visualization` used for the FFT size and `add-computed-technical-properties`
used for the accumulator's placement. **Group 2 is closed; no `Sources/` file exists yet.**

Three things the spike settled *against* this document's first draft are marked where they occur: the
arithmetic width (§4.4), the factor (§4.1), and the withdrawal of the frequency-domain candidate (§5).

## 2. Sample peak and true peak are two different measurements

**Sample peak** is `max |x[n]|` over the file's discrete samples. It is a fact about the samples, it is
exact, and it is already reported (`SignalLevelMetrics.peakSample`).

**True peak** is the maximum absolute value of the continuous-time waveform `x(t)` that those samples
represent. Sampling stores point readings of a band-limited signal; the signal continues to exist
between them, and its extremum generally does not land on a sample instant. So:

> A file whose sample peak is at or below full scale can have a true peak above it.

The mechanism is not exotic. A sinusoid near a quarter of the sample rate, sampled with an unlucky
phase, has its crest fall between two samples: the stored values straddle the peak and read lower than
it. Nothing is wrong with the file; the discrete representation simply does not contain the maximum as a
stored value. It reappears the moment anything reconstructs the waveform — a DAC, a sample-rate
converter, a lossy encoder's decoder output — which is why the quantity is worth measuring at all.

True peak is therefore **estimated, not read**: it requires reconstructing (approximating) `x(t)` and
taking the maximum of the reconstruction. ADR-0006 fixes how: oversample by at least 4×, then detect the
peak.

### 2.1 Normative definition this change adopts

- **True peak** (per channel): the maximum absolute value of the band-limited reconstruction of that
  channel's samples, estimated by oversampling by a factor recorded with the result, following
  ITU-R BS.1770 / EBU R128 practice.
- **Unit, internally**: linear amplitude on the domain's own normalized scale, full scale = `1.0` —
  identical to every other amplitude the domain stores (`SignalLevelMetrics`, `WaveformBucket`,
  `PCMChunk`).
- **Unit, when displayed**: **dBTP** = `20 · log10(truePeakLinear)`, referenced to full scale. The
  "TP" is not decoration: it states that the number came from the reconstructed inter-sample waveform
  rather than from the stored samples, which is precisely the distinction §2 exists to protect. See §4.7
  for why this deviates in *wording* from ADR-0006 and FFmpeg, both of which write "dBFS".
- **Per channel and overall**: per channel is the canonical measurement; overall is the maximum of the
  per-channel values (§7).

### 2.2 The four boundary cases, decided rather than discovered later

| Case | Reported as | Why |
| --- | --- | --- |
| **Silence** (every sample exactly `0`) | linear `0`, displayed at the floor (`-120 dBTP`) | It was measured and the answer is zero. `HumanFormat.decibelsFullScale` already floors `log10(0)` at `Spectrogram.floorDecibels` for exactly this; the dBTP formatter reuses that convention. |
| **Zero frames** (channel carried no audio) | `nil` — "not computable" | A maximum over an empty set does not exist. Identical to `SignalLevelMetrics.Channel.peakSample`'s own rule, and deliberately **not** collapsed with silence. |
| **Samples beyond `\|1\|`** | kept, never clamped; yields a positive dBTP | Inherited from `PCMChunk`'s contract and stated by `SignalLevelMetrics` already: an out-of-range sample is a real fact, and limiting it is a concern of drawing. |
| **True peak below sample peak** | cannot happen — see §4.9 | An estimate that reads *lower* than a value the file literally contains would be an estimate of nothing. Made structurally impossible rather than asserted, and **proven**: worst shortfall over 21 fixtures is exactly `0.0`. |

### 2.3 What true peak is not

- **Not loudness.** LUFS is a gated, K-weighted, time-windowed energy measure; true peak is an
  instantaneous maximum with no weighting and no gating. They answer different questions and are not
  derivable from one another. LUFS is out of scope here (roadmap Phase 3).
- **Not a clipped-sample count.** See §12 — the whole section exists because conflating them is the
  most likely mistake a reader (or a future contributor) could make.
- **Not "clipping".** A true peak above 0 dBTP says the reconstruction exceeds full scale. Whether any
  device or encoder in a given chain actually distorts because of it depends on that chain. Reporting
  the value is evidence; naming it clipping is a conclusion (`docs/analysis-methodology.md`).

## 3. What ADR-0006 already fixes

Read literally, ADR-0006 (Accepted) binds this change to:

1. **The standard** — ITU-R BS.1770 / EBU R128 definitions.
2. **The technique** — oversampling **≥ 4×** *before* peak detection.
3. **The record** — "the oversampling factor and filter are recorded with the result."
4. **The placement** — implemented in `AudioInspectorAnalysis` using Accelerate/vDSP. This is already
   decided; §5's measurement is therefore about *technique*, never about which module the code lives in.
5. **The oracle** — cross-checked against FFmpeg `ebur128`/`loudnorm` during development and in tests,
   with **explicit numeric tolerances** (FFmpeg as reference oracle, ADR-0003 §3 — a dev/test
   dependency, never shipped).
6. **The constants discipline** — every threshold and constant is a named constant tied to the analysis
   engine version, never user-configurable.
7. **No single truth** — where multiple metrics of a family exist, present them side by side.

Its own Follow-ups add: *"Pin the exact constants and tolerances in the loudness OpenSpec change."*
That sentence is this change's mandate, and it is why the open items in §4 are tasks here rather than a
new ADR.

## 4. What ADR-0006 does **not** fix — closed by measurement (group 2)

Six decisions were named here as open. **All six are now closed**, by the spike recorded in
`docs/spikes/2026-08-11-true-peak-methodology-validation.md`. The numbers live there; what follows is
the decision and the one-line reason, so this document states the contract rather than the search.

| # | Decision | Value | Reason |
| --- | --- | --- | --- |
| 4.1 | Oversampling factor | **8×, flat at every sample rate** | Worst-case grid under-read is **−0.169 dB at 4×** and **−0.042 dB at 8×**, measured over 64 signal phases per frequency. R128 limits are quoted to 0.1 dB, so 4×'s error can flip the judgement a reader is making. Rate-dependence was rejected: 2× at 192 kHz would break ADR-0006's own "≥4×". Cost of the choice: **+0.29 s Release / +0.33 s Debug** on a ten-minute stereo file. |
| 4.2 | Interpolation filter | **Polyphase FIR, 48 taps per phase** (384 coefficients at 8×), **Kaiser β = 6.0**, **cutoff = 1.0**, each phase **normalised to unit sum** | Shortest design measured flat within ±0.1 dB up to **0.93·Nyquist** — and 16–20 kHz, the band this product exists to examine, sits at 0.73–0.91·Nyquist at 44.1 kHz. 32 taps reaches only 0.89·N; 64 and 96 buy nothing usable. Image leakage is ≤ +0.02 dB for every design, so it was not the binding constraint. |
| 4.3 | Edge handling | **Zero-extension** | The only policy that neither fabricates nor misses. `constant` reads **1.1303** where the file's own maximum is 1.0; `mirror` reads **0.9432** on a tone whose true peak is provably 0.9; `interior-only` reads **0.000014** on a file whose peak is a full-scale sample at frame 0 — breaking the §2.2 invariant outright. Zero-extension is also the physical truth: a file is surrounded by silence. |
| 4.4 | Arithmetic width | **`Float`** | Worst `float`−`double` difference over 21 fixtures: **1.9 × 10⁻⁷ linear / 2 × 10⁻⁶ dB**. `SignalLevelMetricsAccumulator`'s `Double` precedent does **not** transfer, and the reason is now recorded: it accumulates ~10⁸ additions; a maximum accumulates nothing. |
| 4.5 | Cross-check tolerance | **0.05 dB** against FFmpeg for signals smooth at their boundaries, up to 96 kHz. **0.0042 dB** against analytic truth | Worst measured agreement **0.0236 dB**, plus the oracle's own ±0.0048 dB printing quantisation = 0.029 dB credible worst. Truncated-boundary fixtures (up to 1.05 dB apart) measure the two filters' **edge ringing**, not agreement, and are checked against analytic truth instead. 192 kHz is **not comparable**: the oracle does not oversample there. |
| 4.6 | Oracle in CI | **Gated on FFmpeg's presence**; the **analytic** fixtures carry the CI-enforced claim | The oracle cannot validate 192 kHz and prints to 3 decimals; the analytic fixtures have exact answers, need no external tool, and agree ten times more tightly. Gating the weaker check is not a weakening. |

### 4.7 The unit's name — closed

**dBTP** in the interface, linear everywhere else. The measurement is the argument: fixture 03 has a
sample peak of 0.6364 and a true peak of 0.9, which reads as `−3.92 dBFS` beside `−0.92 dBTP`. Two
numbers 3 dB apart sharing a unit invite the reader to conclude one is wrong. Recorded in **ADR-0019**,
which narrows ADR-0006's wording without editing it.

### 4.8 The one thing that could not be closed, and what was done instead

ADR-0006 refers to BS.1770, whose Annex 2 tabulates its own polyphase FIR. **Those coefficients were not
available to this spike, so they are not used and not reproduced** — writing down remembered numbers
would be fabricated evidence. The filter above is of the same family, **designed** from parameters that
are all recorded with the result, and validated against two independent references: signals whose true
peak is known analytically, and FFmpeg's own R128 meter.

**The consequence is a bounded claim, stated the same way everywhere**: this measures a true peak with a
documented, reproducible methodology that agrees with an independent R128 implementation to 0.05 dB. It
does **not** claim to be BS.1770's own filter. If the annex table becomes available, comparing against
it is a well-defined follow-up, not a redesign.

### 4.9 Why `truePeak >= samplePeak` is structural, and what it costs

`sinc(u)` is **zero at every non-zero integer** — a definition, not an approximation. At phase 0 of the
interpolator every tap argument is an integer, so every tap but the centre one is exactly zero and the
centre one is exactly one: **phase 0 reproduces the input bit for bit**, which puts the stored samples
inside the set the maximum is taken over. Measured: phase-0 taps are exactly `0, …, 1, …, 0`, and the
worst `truePeak − samplePeak` over every fixture and channel is exactly `0.0`.

The implementation must therefore evaluate `sinc` with its integer zeros used as such, rather than
through `sin(πu)/(πu)`, which returns ~1e-16 at integer arguments.

**What it costs**: the cutoff is pinned at exactly 1.0 and stops being a free parameter. The negative
control was run — the same filter at `cutoff = 0.90` has a phase 0 that is no longer the identity, and
the invariant breaks by **−0.16** on a real fixture. Any future change to the cutoff breaks a structural
guarantee, not merely a number, and the production code should say so where the constant is declared.

## 5. The native API — equivalence first, convenience second

Two categories, as required: **(A) methodologically equivalent**, and **(B) convenient but semantically
different**. Only category A may implement a standards-referenced measurement.

### A — vDSP polyphase FIR upsampling, in `AudioInspectorAnalysis`

Interpolating by *L* with an FIR is, by the polyphase identity, *L* separate FIR filters run at the
**input** rate, each producing one of the *L* output phases. `vDSP_conv` performs exactly that
convolution; the *L* phase outputs are then reduced with `vDSP_maxmgv` — the same primitive
`SignalLevelMetricsAccumulator` already uses for the sample peak. Nothing needs to materialise the
zero-stuffed 4× signal, so the memory cost stays a function of the chunk, not of the file.

**Why this is category A**: the filter is *ours*, its coefficients are known, recordable and stable
across OS versions, and it is exactly the operation BS.1770 describes. It satisfies ADR-0006 §3
("factor and filter recorded") literally — the filter can be named because it was chosen.

**Precedent, not novelty**: `SpectrogramAccumulator` already establishes the shape — Accelerate confined
to `AudioInspectorAnalysis`, no `vDSP.*` or `DSPSplitComplex` in any signature, `PCMChunk` in and a
domain model out, non-`Sendable` state confined to one operation. Boundary rule 7 in
`Scripts/check-boundaries.sh` already scopes Accelerate to this module.

### B — `AVAudioConverter` / `AudioConverterRef` (rejected for the measurement)

It resamples, it is native, and it would be a few lines. It is **not** methodologically equivalent:

- **Its filter is unspecified.** Its resampling quality is a *setting*, its coefficients are not
  published, and they may change between OS releases. ADR-0006 requires the filter to be recorded with
  the result; "whatever CoreAudio did on this build of macOS" cannot be recorded, and the same file
  could measure differently after an OS update — which `docs/project-principles.md`'s reproducibility
  rule rules out.
- **It lives in AVFoundation/AudioToolbox**, which by this project's build-enforced boundary belongs to
  `AudioInspectorMedia` alone. Using it would put the measurement in the module that owns *file access*,
  not the one that owns *DSP* — the exact inversion ADR-0016 arranged the seam to avoid.
- **It is designed for playback conversion**, where inaudible filter differences are irrelevant. Here
  the filter *is* the measurement.

Rejected for the measurement. (It remains legitimate for anything that is genuinely a format
conversion; nothing in this change needs one.)

### Not applicable

- **vImage** — image resampling. Its kernels carry no band-limiting guarantee for audio and its
  presence in an audio measurement would be an accident of API shape. Not considered further.
- **`vDSP.FFT` / zero-padding in the frequency domain** — **measured, then withdrawn as a production
  candidate and kept as a reference.** It interpolates the *periodic extension* exactly, which made it
  an independent ground truth for the spike (it returns 0.900000 on a periodic tone whose analytic true
  peak is 0.9, where a zero-padded FIR shows the file's own boundary discontinuity). That same property
  disqualifies it here: a file is not periodic, and the method is whole-buffer rather than streaming.

## 6. Where true peak lives — a sibling, not a new field

Four options were considered.

| Option | Verdict |
| --- | --- |
| **A. Add `truePeak` to `SignalLevelMetrics`** | **Rejected.** That type's own documentation defines it as sample-level facts — "peak, RMS, DC offset and a clipped-sample count", each a direct reduction over stored samples. True peak is a *reconstruction*, produced by a different method, carrying a methodology the type has nowhere to put. It would also change every existing construction site, fixture and export assertion for a value none of them measures. |
| **B. A sibling domain value type** | **Chosen.** Exactly the shape ADR-0018 §2 already established for DSP-derived values ("its own domain value type, living beside the inspection report… a peer, never a member"), and exactly what `WaveformEnvelope`, `Spectrogram` and `SignalLevelMetrics` themselves are. Independent production, independent failure, independent presentation, independent export object. |
| **C. Extend `SignalLevelMetrics` with a methodology section** | **Rejected.** It is A with extra structure: it still puts a reconstruction inside a type defined as direct-sample facts, and it would attach a methodology descriptor to four metrics that do not have one. |
| **D. Fold into a new umbrella "levels" type composing both** | **Rejected for now, named rather than dropped.** It is a plausible eventual shape once the loudness suite exists (Phase 3) and several level metrics want presenting side by side per ADR-0006 §7. Building the umbrella for its second member would be designing for a suite that does not exist. |

**Shape** (recommended; the exact spelling is a task-level decision, not a spec-level one): a value type
in `AudioInspectorDomain/ValueObjects/` with one entry per channel carrying that channel's frame count
and its true peak as `Float?` (`nil` iff the frame count is zero), an overall `Float?` with the same
rule, and a method descriptor carrying the oversampling factor and the filter's identity. Framework-free,
`Sendable`, `Equatable`, and **not `Codable`** — like `SignalLevelMetrics`, the wire form is built by the
export mapper in `AudioInspectorApp`, so the domain never learns that JSON exists (ADR-0009).

**The methodology descriptor is the new thing here**, and it is why ADR-0019 exists: no value type in
this project carries how it was produced. ADR-0006 requires it for this family of metrics, and once it
is exported it is a wire commitment. That is a hard, cross-cutting decision — recorded, not improvised.

**What is deliberately *not* carried**: an analysis-engine version. ADR-0006 ties that to *stored*
results ("record the engine version alongside every stored result"), and there is no result store yet —
ADR-0004 places persistence in Phase 2, and `docs/json-schema-v1.md` states outright that this contract
"has no engine-version field yet". A version field would have to cover every measurement and the
envelope, which makes it the store's or the schema's decision, not this measurement's. Named here so it
is not mistaken for an oversight.

## 7. Per channel and overall

- **Per channel is canonical.** The measurement is per channel; nothing mixes channels before measuring.
  Mixing would synthesise a waveform present in no channel — the same mistake ADR-0016 §10 measured for
  the spectrogram, where time-domain channel combination invented 247 spurious bands.
- **Overall is the maximum of the per-channel values**, and that is exact rather than approximate: a
  maximum of maxima *is* the maximum, which is precisely why `SignalLevelMetrics` treats
  `overallPeakSample` (and not `overallRMS`) as a value that may be combined this way.
- **`nil` iff every channel has zero frames**, matching the existing type's rule exactly.
- **Linear internally, dBTP only at the edge.** The domain stores the linear amplitude; the conversion
  lives in `FeatureAnalysis` alongside `HumanFormat.decibelsFullScale`, as a sibling function with its
  own unit suffix. No presentation string is stored in the domain and no domain type learns what a
  decibel is — the rule `SignalLevelMetrics` already follows.

## 8. The pipeline — is this a fourth PCM read?

Today three operations read samples: the waveform (still on its own private read, deliberately
un-migrated), the spectrogram, and the signal level metrics — the latter two through `AudioDecoding`.

**Yes: a fourth independent operation, and that is the safest slice.** ADR-0016 decision 15 already
settled the general question — "both consumers use the seam, but as independent operations with
independent cancellation" — and rejected a shared pass because it couples lifetimes and makes one
operation the place every future metric must be added. `SignalLevelMetricsGeneration` is the
line-for-line precedent, itself built by mirroring `SpectrogramGeneration`. Choosing this shape:

- changes **no existing type, outcome, state, view or test** — it adds beside them;
- keeps cancellation independent, so a true-peak failure cannot disturb the report, the waveform, the
  spectrogram or the signal levels;
- costs one more full decode per inspection.

**That cost is the one real objection, and it was measured rather than argued.** Group 2 already
answered it: the fourth decode itself costs **0.035 s** (the figure already measured for a ten-minute
stereo file), and the DSP it enables costs **0.69 s in Release and ≈5 s in Debug** for the same file —
next to the spectrogram's own ≈36 s in an unoptimised build. **The fourth read is accepted and the stop
rule below is not triggered.** Group 5 re-measures against the real decode path rather than re-deciding.

Two alternatives were considered and are not chosen:

- **Fold true peak into `SignalLevelMetricsGeneration`** (one decode, two models). Tempting — the two
  metrics genuinely read the same samples — but it couples their cancellation and failure, widens an
  existing outcome type, and contradicts ADR-0016 §15 on the strength of an assumption about cost.
- **A general deduplicating composition** over the port (one read feeding N accumulators). ADR-0016
  explicitly permits this *on top of* the seam "if measurement ever justifies one". It would be a
  cross-cutting refactor of three working operations, and doing it inside a change whose subject is an
  interpolation filter would be two risky things at once.

**Stop rule, written in advance and now evaluated**: if the fourth decode had *not* been clearly
insignificant next to the rest of an inspection, this change would **not** have quietly folded
operations together — it would have recorded the number and opened a separate deduplication change, as
ADR-0016 provides for. Measured, it is insignificant, so the rule stands unused rather than forgotten,
and remains the escape hatch if group 5's numbers against the real decode path disagree.

## 9. Cost — measured, and what it decided

Measured in group 2 with a disposable harness (created, measured, deleted), following
`add-computed-technical-properties` task 3.4's own form. Full tables in the spike report; the figures
that mattered:

| | Release (`-O`) | Debug (`-Onone`) |
| --- | --- | --- |
| 10 min stereo, chosen design, **vDSP** | **0.693 s** | **≈5.2 s** |
| 1 min mono, chosen design, **scalar** | 0.028 s | **151.8 s** |

**Two things this decided, neither of them a matter of taste:**

1. **vDSP is not an optimisation, it is the only viable implementation.** A scalar pass over *one
   minute* of mono audio costs **76–152 seconds** in the build a developer actually runs — three orders
   of magnitude worse than the vectorised path. The production accumulator is `vDSP_conv` per phase plus
   `vDSP_maxmgv`, and that is a correctness-of-workflow decision, not a performance preference.
2. **The fourth read is affordable** (§8). Nothing is deduplicated in this change.

`Float` versus `Double` cost the same to within 1 %, so §4.4's choice is free either way and was decided
on accuracy grounds instead.

**What group 5 still has to do**, and why it is not redundant: every figure above is DSP only, measured
on synthesised buffers. Group 5 measures the **whole inspection** against the real decode path, with
three operations versus four, in Debug — the number that describes what a person waits for. The stop
rule in §8 remains available if that number disagrees.

## 10. Interface — a number and its method, never a verdict

- **Its own section**, titled **True peak**, directly beneath *Signal levels* (both concern level; the
  spectrogram, which concerns frequency, keeps following them). Its own section rather than a fifth row
  inside *Signal levels* because it has its own independent state — a true-peak failure must not blank
  the sample-level rows, and the one-state-one-section shape is what the waveform, the spectrogram and
  the signal levels already establish.
- **Value**: `+0.72 dBTP`, `-1.20 dBTP` — signed always (the sign is the whole point at this scale),
  two decimals, floored exactly as dBFS values already are. Per-channel detail in the established
  `Channel 1: … · Channel 2: …` form, and only when the file has more than one channel.
- **Method, stated plainly**, e.g. *"Estimated from the waveform reconstructed between samples (8×
  oversampling)."* This is the visible half of ADR-0006 §3, and it is what keeps a reader from
  mistaking an estimate for a stored value. **It may not claim conformance to BS.1770's own filter**
  (ADR-0019 §6): the wording says how the value was produced, not which standard's coefficients
  produced it.
- **Zero frames**: *"Not computable — this file has no audio frames."*, the exact wording already used.
- **Forbidden, and swept for by test** (the same negative sweep `SignalLevelMetricsPresentationTests`
  already runs, extended with this metric's own vocabulary): *clipping detected*, *inter-sample
  clipping*, *unsafe*, *too hot*, *bad master*, *distorted*, *poor quality*, *overs*, and any
  colour-only meaning. Nothing is coloured by what the value contains; only a genuine failure to measure
  reads at full weight.
- A positive true peak changes **nothing** else: no inspection warning, no status downgrade, no
  emphasis. It is a fact printed at the same weight as a negative one.

## 11. Export

- **`measurements.truePeak`**, a sibling of `measurements.signalLevels` under the existing, already-
  documented `measurements` object. Additive, **no `schemaVersion` bump** — the schema's own evolution
  rule, and the same route `signalLevels` itself took.
- **Linear, never dBTP.** The wire carries what was measured in the unit it was measured in; the decibel
  conversion is presentation. Identical to `signalLevels`, and stated by `docs/json-schema-v1.md`
  already.
- **Shape**: `overall` (number or explicit `null` — "not computable", never a fabricated `0`),
  `channels[]` with each channel's frame count and value under the same null rule, and a `method`
  object carrying the oversampling factor and the filter's identifier.
- **`method` sits inside `truePeak`**, not at `measurements` level: it describes this measurement, and
  hoisting it would imply it covers `signalLevels` too, which has no such methodology. If a later
  measurement shares it, hoisting is that change's decision with two real cases in hand.
- **Isolation, tested**: a report without a true peak exports byte-identically to today, and
  `measurements` stays omitted entirely when nothing is present — the pattern `signalLevels` established
  in `add-computed-technical-properties` group 6.3.
- **The clipping threshold is still not exported**, unchanged, for the reason already recorded: it is an
  engine constant, not a fact this measurement carries.

## 12. True peak and clipped samples — different questions, kept apart

`clippedSampleCount` counts **stored samples** whose magnitude is at or beyond
`SignalLevelMetricsAccumulator.clippingThreshold` (`1.0`, inclusive). True peak measures the
**reconstructed waveform between** stored samples. Neither implies the other, in either direction:

- A file mastered to just below full scale can have **zero** clipped samples and a true peak **above**
  0 dBTP — the inter-sample case, and the entire reason this metric exists.
- A file with clipped samples necessarily has a true peak at or above 0 dBTP, because a stored sample at
  full scale is itself part of the reconstruction.
- A quiet file has zero clipped samples and a true peak comfortably below 0 dBTP.

**Decision**: they are reported as two separate facts, in two separate sections, and **neither is
derived from the other**. No text anywhere says a positive true peak *is* clipping, and no count is
inferred from a level. The discriminating cases (A/B/C above) become tests — group 8 — because a claim
of independence that no test could falsify is not a claim.

## 13. The scope this change commits to

One metric: **true peak**, per channel and overall, produced by an independent operation, presented in
dBTP with its method, exported linearly under `measurements.truePeak`, tested (including against the
FFmpeg oracle and the clipping-independence cases), and manually validated.

Everything else named in this document is either **rejected** (mixing channels before measuring;
`AVAudioConverter` for the measurement; a true peak inferred from the clipped count) or **deferred with
its reason** (LUFS, LRA, crest factor, significant max frequency, a findings-level inter-sample-clipping
flag, an analysis-engine-version field, decode deduplication, a composed "levels" umbrella type).
