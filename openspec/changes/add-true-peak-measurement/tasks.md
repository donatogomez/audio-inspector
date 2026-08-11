# Implementation Tasks

**Only group 1 is done: this change is the contract, written before any DSP.** No `Sources/` and no
`Tests/` file is touched by this change. Every task from group 2 onward is a roadmap for a future
session, not work performed here.

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

- [ ] 2.1 Build a **disposable** spike (`Spike/`, deleted when the slice's own tests cover its
      observations, exactly as `Spike/validate-static-spectrogram` was scoped) that measures a true peak
      against FFmpeg `ebur128 peak=true` on a fixture set: a near-full-scale tone at a phase that hides
      its crest between samples, a full-scale square-ish signal, real music, silence, a single sample
      beyond full scale, a file whose energy sits at the very first and last frames, and one file per
      supported sample rate.
- [ ] 2.2 Settle **4.2 — the interpolation filter**: BS.1770's own annex filter if its coefficients can
      be reproduced exactly from the standard's text, a windowed-sinc polyphase FIR designed to stated
      parameters, or frequency-domain zero-padding. Decide on measured agreement with the oracle, and
      record the coefficients or the design parameters, not just the name.
- [ ] 2.3 Settle **4.1 — the oversampling factor** at each supported sample rate: flat 4×, or
      rate-dependent to a fixed reconstructed target. Whichever wins is recorded with the value.
- [ ] 2.4 Settle **4.3 — edge handling** at the first and last samples, on a fixture whose energy sits
      exactly there. The criterion is that nothing fabricates a peak the file cannot produce; the
      spectrogram's own "discard rather than pad" precedent is instructive, not binding.
- [ ] 2.5 Settle **4.5 — the cross-check tolerance**, per fixture class, chosen from the agreement
      actually observed. A tolerance widened until the test passes is not a tolerance.
- [ ] 2.6 Settle **4.6 — whether the oracle runs in CI**: gated on the tool's presence (the pattern
      `MP3WaveformEvidenceTests` already uses) or FFmpeg installed on the runner. State the answer, so
      "cross-checked in tests" can never quietly mean "on one machine only". FFmpeg stays a dev/test
      dependency and is never shipped (ADR-0003 §4).
- [ ] 2.7 Write the spike report under `docs/spikes/`, in the form
      `2026-08-06-static-spectrogram-validation.md` established: what was checked, what was measured,
      what changed the design rather than confirming it, and the deletion criterion for the spike.

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

- [ ] 4.1 Implement the interpolation chosen in 2.2 as a polyphase FIR: one FIR per output phase run at
      the input rate via `vDSP_conv`, reduced with `vDSP_maxmgv` — never materialising the zero-stuffed
      oversampled signal, so memory stays a function of the chunk and not of the file's duration.
- [ ] 4.2 Preserve continuity across chunk boundaries: an interpolator needs samples on both sides of
      the point it reconstructs, so the tail of each chunk is carried into the next. **The result must
      not depend on how the file was chunked** — the same guarantee `SignalLevelMetricsAccumulator` and
      `SpectrogramAccumulator` both make, and the same one the capability's existing spec already
      requires of level metrics.
- [ ] 4.3 Guarantee the "never below the sample peak" invariant **structurally**, by including the
      original samples in the candidate set, rather than by clamping the result afterwards — a clamp
      would hide a broken filter instead of failing on it.
- [ ] 4.4 Settle **4.4 — arithmetic width** (`Float` vs `Double` in the convolution) on measurement:
      whether the difference from the oracle is dominated by the filter design or by the arithmetic.
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
