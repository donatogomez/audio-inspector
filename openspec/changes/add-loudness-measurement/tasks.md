# Implementation Tasks

The investigation is done and lives in `docs/spikes/2026-08-18-loudness-measurement-validation.md`.
Group 1 exists because that spike could not resolve the normative constants, and nothing may be built on
remembered ones.

## 1. The constants, from the standard rather than from memory

- [ ] 1.1 Obtain **ITU-R BS.1770** (current revision) and **EBU R128**, and record which revision was
      used. Extract: the K-weighting filter definition, the coefficients or the prototype to derive them
      from, how they adapt to sample rate, the block length and overlap, the absolute and relative gate
      values, and the LUFS conversion offset.
- [ ] 1.2 Record which document each constant comes from. BS.1770 and R128 are **not** the same
      document and this project does not attribute one's rules to the other; Tech 3341/3342 are different
      again and are not needed for integrated loudness.
- [ ] 1.3 Decide the sample-rate strategy from what 1.1 finds: a published table per rate, a single
      table plus a prescribed transform, or an analog prototype discretised per rate. The spike measured
      the outcome that decision must produce — **rate-invariance to 0.1 LUFS across 44.1/48/88.2/96/192
      kHz**.
- [ ] 1.4 Settle what **digital silence** reports, from what the absolute gate means: `unavailable`
      because no block survived gating, or a measurement stated as below the measurable floor. It must
      not default to publishing the reference's −70.0 as though it measured the file.

## 2. The accumulator

- [ ] 2.1 `LoudnessAccumulator` in `AudioInspectorAnalysis`, taking `PCMChunk` like its three siblings,
      with per-channel filter state and absolute block boundaries carried across chunks.
- [ ] 2.2 Filter with `vDSP_biquad` (measured at 0.117 s for two sections over two channels of ten-minute
      stereo). Its delay state is what makes chunked streaming correct.
- [ ] 2.3 Gate in two passes as the standard prescribes, and keep the surviving block energies bounded —
      memory must stay a function of the block count, never of the samples.
- [ ] 2.4 `finish()` returns optional, like its siblings, so an unmeasurable file becomes an outcome
      rather than a fabricated number.
- [ ] 2.5 Channel weighting for **mono and stereo only**, from the channel count. Measured: stereo reads
      exactly 3.01 dB above the same signal in mono, so both weights are equal and energies sum.
      Anything else reports no value.

## 3. The domain type

- [ ] 3.1 `LoudnessMeasurement` — `Sendable`, `Equatable`, failable, **not** `Codable`. Stores **LUFS**,
      not linear energy: the normative quantity is the logarithmic one.
- [ ] 3.2 It carries its methodology, as `TruePeakMeasurement` does.
- [ ] 3.3 It refuses what cannot describe a measurement — non-finite values above all, the mistake
      `SignalLevelMetrics` had to be repaired for.

## 4. Numbers, decided by measurement

- [ ] 4.1 Compare `Float` against `Double` **filter state** over a ten-minute file against the oracle.
      Do not inherit signal levels' or true peak's answer; an IIR filter accumulates error differently
      from a sum. Record the result either way.
- [ ] 4.2 Energy accumulation in `Double` (measured 0.028 s), for the reason signal levels needed it.
- [ ] 4.3 **Chunk independence, exact**, at 1, 3, 127, 512, 4 096, 65 536 and whole-file. A tolerance
      here would mean the filter state or the block boundaries are not carried correctly — treat one as
      evidence for `Double` state, not as a reason to widen the bound.

## 5. Correctness against the oracle

- [ ] 5.1 Reproduce the spike's **K-weighting response** to a stated tolerance: −6.3 dB at 40 Hz, −1.8 at
      100, −1.0 at 200, −0.7 at 400, 0.0 at 1 k, +2.4 at 2 k, +3.3 at 4 k and 8 k, +3.4 at 12 k and 16 k.
- [ ] 5.2 The **calibration anchor**: a 1 kHz sine at −20 dBFS peak, stereo, reads **−20.0 LUFS**; the
      same signal in mono reads **−23.0 LUFS**.
- [ ] 5.3 The **gating fixture**: 10 s at 0.5 followed by 10 s at 0.005 reads **−6.1 LUFS**, not the
      ungated mean. This is what separates a gated implementation from an ungated one.
- [ ] 5.4 Rate-invariance across 44.1/48/88.2/96/192 kHz.
- [ ] 5.5 Cross-check real files of each container against `ffmpeg -filter_complex ebur128`, with a
      stated tolerance. **Its summary is INFO-level**: `-loglevel error` silently discards it.
- [ ] 5.6 Negative controls, each reverted in full: weighting bypassed, gating removed, filter state
      reset per chunk, block boundaries made per-chunk.

## 6. The fifth consumer

- [ ] 6.1 One field on `SharedPCMAnalysisOutcome`, one accumulator in the composition, one line in each
      of `prepare`/`accumulate`/`failAll`/`finish` — the price true peak and the waveform each paid. No
      protocol, no generic machinery, **no second read**.
- [ ] 6.2 Isolation, with negative controls: its failure is its own, the read outlives it, a producer
      failure ends every consumer separately, cancellation is global, absence stays distinct from
      failure.
- [ ] 6.3 Confirm the read count is **still one**, at the gate that already asserts it.
- [ ] 6.4 Measure the real cost as a fifth consumer. Projected from the spike: **≈0.14 s** on ten minutes
      of stereo, roughly half the waveform's fold and 7–12 % of the pass it joins. A materially larger
      figure means something is being paid that the spike did not see.

## 7. Surface

- [ ] 7.1 One presentation row: "Integrated loudness", one decimal, LUFS, methodology beside it. No
      per-channel row. Absence uses the existing not-computable phrasing.
- [ ] 7.2 **No verdict, and no target.** Not "too loud", not "streaming ready", no platform name, no
      normalisation advice, no comparison against −14 or −23.
- [ ] 7.3 Accessibility: the value and its unit are announced together, as true peak's already are.
- [ ] 7.4 Export additively under `measurements`, absent when not measured, `schemaVersion` stays **1**.

## 8. Gates and closure

- [ ] 8.1 Four gates green plus the Xcode build and `git diff --check`.
- [ ] 8.2 Update `CURRENT.md` and archive through `openspec archive` **after merge**.
