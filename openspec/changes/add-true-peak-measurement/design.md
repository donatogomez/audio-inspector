# Design — true peak measurement

## 1. What this document is, and what it is not

It answers, before any DSP is written: what true peak *is* normatively, what ADR-0006 already fixes and
what it leaves open, which native API can implement the methodology without changing its meaning, where
the value lives in the domain, how it is produced, presented and exported, and how it relates to the
clipped-sample count already shipping.

**It commits to no constant that has not been measured.** Where a value must be pinned (the
interpolation filter, the oversampling factor above 48 kHz, the cross-check tolerance), this document
names the decision, states the candidates and the criterion, and hands it to a task — it does not
silently choose one. That is the same discipline `add-static-spectrogram-visualization` used for the FFT
size and `add-computed-technical-properties` used for the accumulator's placement.

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
  rather than from the stored samples, which is precisely the distinction §2 exists to protect. See §11
  for why this deviates in *wording* from ADR-0006 and FFmpeg, both of which write "dBFS".
- **Per channel and overall**: per channel is the canonical measurement; overall is the maximum of the
  per-channel values (§7).

### 2.2 The four boundary cases, decided rather than discovered later

| Case | Reported as | Why |
| --- | --- | --- |
| **Silence** (every sample exactly `0`) | linear `0`, displayed at the floor (`-120 dBTP`) | It was measured and the answer is zero. `HumanFormat.decibelsFullScale` already floors `log10(0)` at `Spectrogram.floorDecibels` for exactly this; the dBTP formatter reuses that convention. |
| **Zero frames** (channel carried no audio) | `nil` — "not computable" | A maximum over an empty set does not exist. Identical to `SignalLevelMetrics.Channel.peakSample`'s own rule, and deliberately **not** collapsed with silence. |
| **Samples beyond `\|1\|`** | kept, never clamped; yields a positive dBTP | Inherited from `PCMChunk`'s contract and stated by `SignalLevelMetrics` already: an out-of-range sample is a real fact, and limiting it is a concern of drawing. |
| **True peak below sample peak** | must not happen — see §4.5 | An estimate that reads *lower* than a value the file literally contains would be an estimate of nothing. Made structurally impossible rather than asserted. |

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

## 4. What ADR-0006 does **not** fix — the open decisions, named

None of the following is decided by any existing record. Each is listed with its candidates and the
criterion that will settle it; **none is chosen here by assumption**.

### 4.1 The oversampling factor above 48 kHz

ADR-0006 says "≥ 4×". BS.1770's 4× is specified relative to a 48 kHz base rate — the point being to
reach a high enough reconstructed rate, not to multiply by four regardless of input. A file at 192 kHz
already carries four times the resolution a 48 kHz file does.

**Open**: whether the factor is a flat 4× at every sample rate (simplest, most conservative, most
expensive at high rates) or rate-dependent so the *reconstructed* rate meets a fixed target (fewer
operations at 96/192 kHz, but a second constant to justify and record). **Criterion**: measured
agreement with the FFmpeg oracle at each supported rate, and the cost table in group 5. Whichever wins,
the factor is recorded with the value, so a reader is never left guessing which was used.

### 4.2 The interpolation filter

ADR-0006 requires the filter to be *recorded*, which presumes one is *chosen*; it does not choose one.

**Candidates**: (a) the polyphase FIR of BS.1770's own annex, if its coefficients can be reproduced
exactly from the standard's text; (b) a windowed-sinc polyphase FIR designed to a stated passband
ripple and stopband attenuation, with the design parameters recorded; (c) frequency-domain zero-padding
(exact band-limited interpolation, but block-boundary handling of its own). **Criterion**: agreement
with the oracle within a tolerance decided in 4.5, at acceptable cost. **This is the single largest
unknown in the change and is why group 2 is a spike, not an implementation.**

### 4.3 Edge handling

An FIR interpolator needs samples on both sides of the point it reconstructs; at the very first and last
samples of the file there are none. **Open**: zero-extension (treats the file as surrounded by silence —
the reconstruction a decoder would also produce), reflection, or restricting the estimate to the region
the filter fully covers. The spectrogram's own precedent is instructive but not binding: it discards the
final incomplete window rather than zero-padding it, because padding *invented* samples and read the
level 6 dB low. **Criterion**: whichever does not fabricate a peak the file cannot produce, verified
against the oracle on a fixture whose energy sits at the very first and last frames.

### 4.4 Precision and accumulation

`SignalLevelMetricsAccumulator` accumulates in `Double` and narrows to `Float` at the end, measured to
cost nothing. A maximum has no accumulation error, so the same reasoning does not transfer
automatically: the question here is the *filter arithmetic*, not the running total. **Open**: whether the
convolution runs in `Float` (matching the sample type and vDSP's fastest path) or `Double`. **Criterion**:
whether the difference from the oracle is dominated by the filter design or by the arithmetic width —
measurable, and measured before choosing.

### 4.5 The cross-check tolerance

ADR-0006 requires "explicit numeric tolerances" and states none. **Open**: the dB tolerance at which the
native value must agree with FFmpeg `ebur128 peak=true`, per fixture class. **Criterion**: the observed
spread across the fixture set, chosen so the tolerance describes the agreement actually achieved rather
than being loosened until the test passes. Recorded in the spike report with the measurements behind it.

### 4.6 Whether the cross-check can run in CI

`ffmpeg` is present on the development machine (Homebrew 8.1.2, and its `ebur128` filter exposes both
`peak=true` → `true_peak` and `sample_peak`, giving both halves of §12's comparison from one oracle).
It is **not** installed on the CI runner (`.github/workflows/ci.yml`, `macos-26`, no install step).
**Open**: gate the oracle tests on the tool's presence — the pattern `MP3WaveformEvidenceTests` already
uses for a locally-available tool — or install FFmpeg in CI, which makes a GPL binary part of the
pipeline (never of the product; ADR-0003 §4 governs shipping, not CI). **Criterion**: the gated form is
the default unless CI coverage of the oracle is judged necessary; whichever is chosen is stated, because
"cross-checked in tests" meaning "cross-checked only on one machine" must not be discovered later.

### 4.7 The unit's name

ADR-0006 writes "true peak > 0 **dBFS**"; `docs/analysis-methodology.md` writes "true peak (dBFS)";
FFmpeg's own option is documented as "true peak (dBFS)". EBU R128 / Tech 3341 write **dBTP**, and that
is the notation a reader of mastering tools will recognise. **Open, and small**: this design recommends
**dBTP** in the interface (§10) precisely because the two numbers sit next to each other on screen and
"peak sample: −0.10 dBFS / true peak: +0.30 dBFS" invites the reader to think one of them is wrong. The
recommendation is recorded in ADR-0019 so the divergence from ADR-0006's wording is a decision and not
a drift.

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
- **`vDSP.FFT` / zero-padding in the frequency domain** — genuinely exact band-limited interpolation,
  and therefore category A on correctness grounds, but it converts a streaming, `O(chunk)` problem into
  a blocked one with its own edge handling at every block boundary. Kept in §4.2 as candidate (c) and
  measured, not dismissed by assertion.

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

**That cost is the one real objection, and it is measured rather than argued** (§9, group 5). Two
alternatives were considered and are not chosen *now*:

- **Fold true peak into `SignalLevelMetricsGeneration`** (one decode, two models). Tempting — the two
  metrics genuinely read the same samples — but it couples their cancellation and failure, widens an
  existing outcome type, and contradicts ADR-0016 §15 on the strength of an assumption about cost.
- **A general deduplicating composition** over the port (one read feeding N accumulators). ADR-0016
  explicitly permits this *on top of* the seam "if measurement ever justifies one". It would be a
  cross-cutting refactor of three working operations, and doing it inside a change whose subject is an
  interpolation filter would be two risky things at once.

**Stop rule, written in advance**: if group 5's measurement shows the fourth decode is *not* clearly
insignificant next to the rest of an inspection, this change does **not** quietly fold operations
together. It records the number and opens a separate deduplication change, exactly as ADR-0016 provides
for. The slice's own scope stays what it is.

## 9. Cost, measured before it is designed around

Same method as `add-computed-technical-properties` task 3.4, which produced a four-row table and let the
number choose the implementation. A **disposable harness** (created, measured, deleted — never committed
to `Sources/` or `Tests/`), over a real file, reporting:

| Axis | Values |
| --- | --- |
| Duration | 1 min, 10 min |
| Channels | mono, stereo |
| Build | Debug (`-Onone`), Release (`-O`) |
| Baseline | decode only, no accumulation |
| Implementations | naive scalar interpolation; vDSP per-phase `vDSP_conv` + `vDSP_maxmgv`; and, if §4.2 keeps it alive, the frequency-domain variant |
| Factor | the candidates from §4.1 |

Also measured, because §8 depends on it: the **whole-inspection** wall time with three operations versus
four, in Debug, which is the build a developer actually runs.

**Decision rules, fixed in advance**: the implementation with the best measured cost that is
methodologically equivalent wins (§5 — never performance alone); and the fourth read is accepted only if
the measured whole-inspection delta is insignificant beside the existing work, otherwise §8's stop rule
applies. The numbers land in a spike report under `docs/spikes/`, following
`2026-08-06-static-spectrogram-validation.md`'s own form.

## 10. Interface — a number and its method, never a verdict

- **Its own section**, titled **True peak**, directly beneath *Signal levels* (both concern level; the
  spectrogram, which concerns frequency, keeps following them). Its own section rather than a fifth row
  inside *Signal levels* because it has its own independent state — a true-peak failure must not blank
  the sample-level rows, and the one-state-one-section shape is what the waveform, the spectrogram and
  the signal levels already establish.
- **Value**: `+0.72 dBTP`, `-1.20 dBTP` — signed always (the sign is the whole point at this scale),
  two decimals, floored exactly as dBFS values already are. Per-channel detail in the established
  `Channel 1: … · Channel 2: …` form, and only when the file has more than one channel.
- **Method, stated plainly**, e.g. *"Estimated from the waveform reconstructed between samples (4×
  oversampling)."* This is the visible half of ADR-0006 §3, and it is what keeps a reader from
  mistaking an estimate for a stored value.
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
