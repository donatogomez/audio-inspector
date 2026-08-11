# Implementation Tasks

**Groups 1 and 2 are done: the contract, and the measurements that turned its open questions into
constants.** No `Sources/` and no `Tests/` file has been touched — group 2's evidence lives entirely in
`Spike/validate-true-peak/` (outside the production graph) and
`docs/spikes/2026-08-11-true-peak-methodology-validation.md`. Every task from group 3 onward is a
roadmap for a future session, not work performed here.

**The methodology is now fixed and is no longer a decision for a later group**: polyphase FIR, **8×**,
**48 taps per phase**, Kaiser **β = 6.0**, cutoff **1.0**, phases normalised, **zero-extension** at the
edges, **`Float`** arithmetic, **linear** internally and **dBTP** only on screen, agreement with FFmpeg
within **0.05 dB** on signals smooth at their boundaries. A later group that wants to change any of
these changes the analysis engine version, not a preference.

Boundaries no future task may cross: the measurement is **estimated, never read from the samples**;
`TechnicalProperties` gains nothing (ADR-0018 — this needs decoded audio); `SignalLevelMetrics`, its
accumulator, its presentation, its export object and `clippedSampleCount` are **not modified**;
Accelerate stays inside `AudioInspectorAnalysis` and no `vDSP` type crosses a port; no framework type or
error crosses a domain port; **no constant is chosen without a measurement behind it**; no LUFS, no LRA,
no crest factor, no significant max frequency, no finding, no flag, no score.

## 1. The contract

- [x] 1.1 Open the change with `proposal.md`, `design.md`, this task list, and the delta spec on
      `audio-signal-level-metrics` (ADDED only — the existing sample-level requirement, its clipping
      threshold and its isolation requirement are deliberately left untouched, so no requirement is
      duplicated).
- [x] 1.2 Read ADR-0006 literally and separate what it **fixes** (standard, ≥4× oversampling before peak
      detection, factor and filter recorded with the result, `AudioInspectorAnalysis` + Accelerate,
      FFmpeg `ebur128` as the cross-check oracle with explicit tolerances, named constants tied to the
      engine version) from what it **leaves open** (`design.md` §3–4). Six open decisions named rather
      than silently chosen: the factor above 48 kHz, the interpolation filter, edge handling, arithmetic
      width, the cross-check tolerance, and whether the oracle can run in CI.
- [x] 1.3 Define true peak normatively against sample peak, with the four boundary cases decided in
      advance — silence, zero frames, samples beyond full scale, and the "never below the sample peak"
      invariant (`design.md` §2).
- [x] 1.4 Audit the native APIs and split them into **methodologically equivalent** (vDSP polyphase FIR,
      chosen) and **convenient but semantically different** (`AVAudioConverter`/`AudioConverterRef`,
      rejected: unpublished filter, OS-version-dependent, and it would put the measurement in the module
      that owns file access rather than DSP). `vImage` not applicable; frequency-domain interpolation
      kept as a measured candidate rather than dismissed (`design.md` §5).
- [x] 1.5 Decide the domain placement against four options and record why a sibling type wins over
      extending `SignalLevelMetrics` (`design.md` §6), and why no analysis-engine-version field is
      introduced here (ADR-0006 ties it to *stored* results; there is no store yet — ADR-0004).
- [x] 1.6 Write **ADR-0019** in `Proposed` for the two decisions ADR-0006 does not make — a measurement
      carrying its own methodology, and a positive true peak reported as a value rather than raised as a
      flag — with its promotion conditions. Add its row to `docs/adr/README.md`. ADR-0006 is
      **referenced, never edited**.

## 2. The methodology spike — measure before implementing

**Done. All six open decisions are closed by measurement**, and three of them closed *against* what
`design.md` first assumed. Evidence:
`docs/spikes/2026-08-11-true-peak-methodology-validation.md`. Spike package:
`Spike/validate-true-peak/`, outside the production graph, deleted when ADR-0019 is Accepted and this
slice's own tests cover its observations. **No `Sources/` or `Tests/` file was touched.**

- [x] 2.1 Built the disposable spike (`Spike/validate-true-peak/`, its own SwiftPM package, Swift 6 mode
      with `-warnings-as-errors`, importing nothing but Accelerate and Foundation). **21 fixtures**,
      every one synthesised from a formula and written as a hand-built RIFF/WAVE IEEE-float file, so no
      external audio is evidence anywhere and no framework's own conversion sits between the formula and
      the oracle. Covers all seventeen requested characteristics: silence; crest on a sample; crest
      between samples; near Nyquist; sample peak < 1 with true peak > 1; a stored sample of 1.5; an
      impulse; hard edges; energy at the first and at the last frame; mono; stereo with different
      channels; 44.1/48/96/192 kHz; and a music-like programme (12 partials plus seeded noise).
      **Four fixtures were added mid-spike, not planned** (faded and exactly-periodic tones) — see 2.4.
- [x] 2.2 **The filter: polyphase FIR, 48 taps per phase, Kaiser β = 6.0, cutoff = 1.0, each phase
      normalised to unit sum.** Chosen from a 24-design sweep on the criterion this product actually
      needs: flat within ±0.1 dB across 16–20 kHz, which is 0.73–0.91 of Nyquist at 44.1 kHz. 48 taps is
      the shortest design that reaches it (0.93·N); 32 taps stops at 0.89·N; 64 and 96 buy nothing
      usable. Image leakage is ≤ +0.02 dB for every design, so it never became the binding constraint.
      **BS.1770's own annex coefficients were not used and not reproduced: the standard's text was not
      available to this spike**, and remembered numbers would be fabricated evidence. The designed
      filter is validated instead against analytic ground truth and against FFmpeg's own R128 meter, and
      the resulting claim is bounded accordingly everywhere it appears (`design.md` §4.8).
- [x] 2.3 **The factor: 8×, flat at every supported sample rate.** Decided on worst-case behaviour over
      64 signal phases per frequency, not on a single lucky phase: **−0.169 dB at 4× versus −0.042 dB at
      8×**. R128 limits are quoted to 0.1 dB, so 4× — legal under ADR-0006's "≥4×" — can flip the
      judgement a reader is making. Rate-dependence was rejected because 2× at 192 kHz would break
      ADR-0006's own floor. Measured cost of the choice: +0.29 s Release / +0.33 s Debug on a ten-minute
      stereo file.
- [x] 2.4 **Edge handling: zero-extension.** The only policy that neither fabricates nor misses:
      `constant` reads **1.1303** where the file's own maximum is 1.0, `mirror` reads **0.9432** on a
      tone whose true peak is provably 0.9, and `interior-only` reads **0.000014** on a file whose peak
      is a full-scale sample at frame 0 — breaking the `truePeak >= samplePeak` invariant outright.
      **This is also where the spike corrected itself**: the first run showed both this implementation
      *and* the oracle reading above a tone's own amplitude, and faded and exactly-periodic fixtures were
      added to separate edge ringing from filter error. It was entirely edge ringing — a file's boundary
      against silence is a real discontinuity, and its overshoot is a fact about the file, not an
      artefact to remove.
- [x] 2.5 **The tolerance: 0.05 dB against FFmpeg for signals smooth at their boundaries, up to 96 kHz;
      0.0042 dB against analytic truth.** Derived rather than rounded up for comfort: worst measured
      agreement **0.0236 dB**, plus the oracle's own ±0.0048 dB printing quantisation, gives 0.029 dB
      credible worst. Fixtures with truncated boundaries disagree by up to 1.05 dB and are **excluded
      with a reason** — they measure two filters' edge ringing, not agreement — and are checked against
      analytic truth instead. 192 kHz is excluded as **not comparable** (2.6).
- [x] 2.6 **The oracle is gated on FFmpeg's presence; the analytic fixtures carry the CI-enforced
      claim.** Three oracle limitations were measured, not assumed: it prints true peak to three decimal
      places linear (a ±0.0005 floor), it **does not oversample at 192 kHz at all** (its true peak
      equals its own sample peak there, against an analytic 0.9), and on truncated fixtures it measures
      edge behaviour. The analytic fixtures have exact answers, need no external tool, and agree ten
      times more tightly — so gating the weaker check is not a weakening, and "cross-checked in tests"
      never quietly means "on one machine only". FFmpeg stays a dev/test dependency, never shipped
      (ADR-0003 §4).
- [x] 2.7 Spike report written: `docs/spikes/2026-08-11-true-peak-methodology-validation.md` — environment,
      fixtures, verbatim oracle command, every table, the candidates rejected, the corrections this spike
      forced on `design.md`, falsification criteria written before the measurements, and the deletion
      criterion for the package.

**Also closed here, though not listed as a task**: `truePeak >= samplePeak` is proven **structural**, not
patched. Phase 0 of the interpolator is the exact identity because `sinc` is zero at every non-zero
integer, so the stored samples are inside the set the maximum is taken over — worst shortfall over 21
fixtures is exactly `0.0`, and the negative control (cutoff 0.90) breaks it by −0.16 as predicted.
Chunk independence is **bit-exact** at every chunk size from one frame up, and `Float` matches `Double`
to 1.9 × 10⁻⁷ linear, so the accumulator uses `Float` (`design.md` §4.4, §4.9).

## 3. The domain model

- [ ] 3.1 Add the sibling value type: per-channel frame count and true peak (`nil` **iff** the frame
      count is zero), an overall value under the same rule, and the method descriptor carrying the
      oversampling factor and the filter's identity. Framework-free, `Sendable`, `Equatable`, **not
      `Codable`** — the wire form is built by the export mapper, so the domain never learns JSON exists
      (ADR-0009).
- [ ] 3.2 Document in the type itself, as `SignalLevelMetrics` does for its own cases: linear not
      decibels; values beyond full scale kept, never clamped; "not computable" distinct from a measured
      zero; overall is the maximum of the per-channel values and why that combination is exact.
- [ ] 3.3 Unit-test the model's own rules with constructed values and no file: the `nil` rule in both
      directions, the overall/per-channel relationship, and that a value above full scale survives
      construction unchanged.

## 4. The accumulator (`AudioInspectorAnalysis`, Accelerate — placement already fixed by ADR-0006)

- [ ] 4.1 Implement the filter closed in 2.2/2.3 — polyphase FIR, 8×, 48 taps per phase, Kaiser
      β = 6.0, cutoff 1.0, phases normalised to unit sum — as one FIR per output phase run at the input
      rate via `vDSP_conv`, reduced with `vDSP_maxmgv`, never materialising the zero-stuffed oversampled
      signal, so memory stays a function of the chunk and not of the file's duration. Generate the
      coefficients from the recorded parameters rather than pasting a table, and evaluate `sinc` with its
      integer zeros used exactly (4.3 depends on it). Every constant is engine-versioned and **not**
      user-configurable.
- [ ] 4.2 Preserve continuity across chunk boundaries: an interpolator needs samples on both sides of
      the point it reconstructs, so the tail of each chunk is carried into the next. **The result must
      not depend on how the file was chunked** — the same guarantee `SignalLevelMetricsAccumulator` and
      `SpectrogramAccumulator` both make, and the same one the capability's existing spec already
      requires of level metrics.
- [ ] 4.3 Guarantee the "never below the sample peak" invariant **structurally**: with cutoff 1.0 and
      exact integer sinc zeros, phase 0 *is* the identity, so the stored samples are already in the set
      the maximum is taken over. **No clamp** — a clamp would hide a broken filter instead of failing on
      it. Assert phase 0 reproduces its input bit for bit, and keep group 2's negative control (cutoff
      0.90 breaks the invariant by −0.16) as a test rather than as a comment.
- [ ] 4.4 Carry the convolution in **`Float`** — settled in group 2 (worst difference from `Double`
      over 21 fixtures: 1.9 × 10⁻⁷ linear, 2 × 10⁻⁶ dB, at identical cost). Document beside the code why
      this differs from `SignalLevelMetricsAccumulator`'s `Double`: that type accumulates ~10⁸
      additions, a maximum accumulates nothing.
- [ ] 4.5 Unit-test the accumulator with no file and no framework: known signals with known inter-sample
      peaks; a tone whose crest is hidden between samples; silence; zero frames; a single sample beyond
      full scale; chunk-size and feed-order independence; per-channel independence; determinism across
      two runs. Include at least one **negative control** — a deliberately wrong variant (for example,
      peak detection without interpolation) that must break specific named assertions — then revert it
      in full and confirm no residue, as groups 3.5 and 6.3 of `add-computed-technical-properties` did.
- [ ] 4.6 Cross-check against FFmpeg `ebur128 peak=true` within the tolerance from 2.5, gated per 2.6.
      The oracle test compares **both** `true_peak` and `sample_peak`, since the oracle reports both and
      the pair is exactly what §12 of `design.md` claims to keep independent.

## 5. Cost — measured before the architecture is committed to

- [ ] 5.1 Measure with a **disposable harness** (created, measured, deleted — never committed to
      `Sources/` or `Tests/`), following `add-computed-technical-properties` task 3.4's own form: 1 min
      and 10 min, mono and stereo, Debug (`-Onone`) and Release (`-O`), against a decode-only baseline,
      for the naive scalar implementation and the vDSP one — and for each surviving candidate factor and
      filter. Publish the table in the spike report.
- [ ] 5.2 Measure the **whole-inspection** wall time with three operations versus four, in Debug (the
      build a developer actually runs), because that number — not the accumulator's own — is what
      decides whether a fourth read is acceptable.
- [ ] 5.3 Apply the stop rule from `design.md` §8 rather than improvising: if the fourth decode is not
      clearly insignificant beside the rest of an inspection, **do not** fold operations together inside
      this change — record the number and open a separate deduplication change, as ADR-0016 provides
      for.

## 6. Wiring — a fourth independent operation

- [ ] 6.1 Add the generation as a **fourth** independent operation over the existing `AudioDecoding`
      port, with its own decoder instance and its own cancellation, mirroring `SignalLevelMetricsGeneration`
      (which itself mirrors `SpectrogramGeneration`) — the same fault/cancellation/absence/empty-answer
      handling and the same two-guard fault check. It opens no `URL` and no security scope; it runs
      inside the coordinator's existing window (ADR-0010).
- [ ] 6.2 Extend the inspection outcome and the presentation state with a fourth case, exactly as the
      third was added, and confirm by test that each of the four operations stays independently
      cancellable and independently presentable: a failing or cancelled true peak leaves the report, the
      waveform, the spectrogram and the signal levels untouched, **and the reverse direction too**.
      Include a negative control that makes the wiring's own tests fail, then revert it.
- [ ] 6.3 Confirm the source file is never modified and never read outside the access window.

## 7. Presentation

- [ ] 7.1 Add the dBTP conversion as a sibling of `HumanFormat.decibelsFullScale` in `FeatureAnalysis`,
      reusing the existing floor convention rather than inventing a second one, and pin it with exact
      reference points the way the dBFS formatter is pinned (`1.0 → 0.00`, `0.5 → -6.02`, a value above
      full scale reading a signed positive, and silence reading the floor rather than `-∞`).
- [ ] 7.2 Present it in its **own section** titled *True peak*, directly beneath *Signal levels*, with
      its own state (`loading`/`available`/`absent`/`failed`) so a true-peak failure cannot blank the
      sample-level rows. Per-channel detail in the established `Channel 1: … · Channel 2: …` form, and
      only when the file has more than one channel.
- [ ] 7.3 State the method in words beside the value (the visible half of ADR-0006's "factor and filter
      recorded with the result"), and use the existing "Not computable — this file has no audio frames."
      wording for a file with no audio rather than a second phrasing for the same state.
- [ ] 7.4 Extend the existing forbidden-word sweep with this metric's own vocabulary — *clipping
      detected*, *inter-sample clipping*, *unsafe*, *too hot*, *bad master*, *distorted*, *poor
      quality*, *overs* — and confirm no colour-only meaning: only a genuine failure to measure reads at
      full weight, and nothing is coloured by what the value contains.

## 8. True peak versus clipped samples — the independence, proven

- [ ] 8.1 Test case **A**: a fixture with **zero** clipped samples and a true peak **above** full scale
      (the inter-sample case this metric exists for). The two values are reported side by side, neither
      derived from nor overriding the other.
- [ ] 8.2 Test case **B**: a fixture with clipped samples present and a true peak at or above full
      scale — both reported, as two separate facts.
- [ ] 8.3 Test case **C**: a quiet fixture with zero clipped samples and a true peak below full scale.
- [ ] 8.4 Confirm by search and by test that no code path derives one from the other, and that no
      user-facing string describes a positive true peak as clipping.

## 9. Export

- [ ] 9.1 Add `measurements.truePeak` beside `measurements.signalLevels`: `overall` (number or explicit
      `null` for "not computable", never a fabricated `0`), `channels[]` under the same null rule, and a
      `method` object carrying the oversampling factor and the filter identifier. **Linear, never
      dBTP.** No `schemaVersion` bump — additive, per the schema's own evolution rule.
- [ ] 9.2 Confirm isolation the way `signalLevels` did: a report without a true peak exports
      byte-identically to today, `measurements` stays **omitted entirely** (never `null`) when nothing
      is present, and no existing field moves or changes. Include the negative controls that pattern
      established — a DSP key smuggled into `technicalProperties`, and a dBTP value exported where a
      linear one belongs — both reverted in full.
- [ ] 9.3 Update `docs/json-schema-v1.md` with the new object, its null rules and its unit, in the same
      table form the existing `signalLevels` rows use.

## 10. Gates, validation and closure

- [ ] 10.1 Four gates green — `./Scripts/check-boundaries.sh`, `swift build -Xswiftc -warnings-as-errors`,
      `swift test`, `OPENSPEC_TELEMETRY=0 openspec validate --all --strict` — plus the Xcode app build
      and `git diff --check`.
- [ ] 10.2 Manual validation on a **confirmed-fresh** process instance (launched by executable path,
      never `open` — the stale-instance trap `docs/manual-validation-mvp.md` already documents): the
      on-screen *True peak* section and the exported `measurements.truePeak` both correct, on a file
      whose true peak genuinely exceeds its sample peak, reproducibly.
- [ ] 10.3 Decide **ADR-0019**'s status from what was actually implemented, delete the spike per its own
      criterion once the slice's tests cover its observations, update `CURRENT.md`, and archive through
      `openspec archive` **after merge**.

## 11. Deferred, and named so it is not quietly dropped

- [ ] 11.1 **LUFS (M/S/I) and LRA** — governed by the same ADR-0006, placed by the roadmap in Phase 3,
      and a change of their own. Not designed here.
- [ ] 11.2 **Crest factor** — free once peak and RMS exist, deferred for the reason
      `add-computed-technical-properties` `design.md` §12 recorded: alone, outside the loudness suite's
      context, it invites the out-of-context reading the methodology document warns against.
- [ ] 11.3 **An inter-sample-clipping flag or finding** — ADR-0006 names one; interpretation in this
      project carries evidence, alternatives and confidence, which is the schema's still-unused
      `findings` object and a capability of its own. Scoped out here by ADR-0019, not dropped.
- [ ] 11.4 **An analysis-engine-version field** in the domain and on the wire — cross-cutting, tied by
      ADR-0006 to *stored* results, and there is no store yet (ADR-0004, Phase 2).
- [ ] 11.5 **Decode deduplication across the four operations** — permitted by ADR-0016 *on top of* the
      seam once measurement justifies it; opened only by 5.3's stop rule, never folded in silently.
- [ ] 11.6 **Significant max frequency** — unchanged from where `add-computed-technical-properties` left
      it: it needs its own noise-floor/persistence methodology, and is not part of this slice.
