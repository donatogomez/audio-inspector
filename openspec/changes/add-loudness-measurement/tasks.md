# Implementation Tasks

The investigation is done and lives in `docs/spikes/2026-08-18-loudness-measurement-validation.md` —
**Part A normative, Part B measured, never mixed.** Group 1 existed because the first session could not
resolve the normative constants. **It is now closed**: the standards were obtained and read, and every
constant is sourced. Nothing below may be built on a remembered number.

## 1. The constants, from the standard rather than from memory — **CLOSED**

- [x] 1.1 Obtain the standards and record the revisions used: **ITU-R BS.1770-5 (11/2023)**,
      **EBU R 128 v5.0 (11/2023)**, **EBU Tech 3341 v4 (11/2023)**, **EBU Tech 3342 v4 (11/2023)** and
      **Report ITU-R BS.2217-2 (10/2016)**. Extracted into spike Part A: both K-weighting stages with
      their 48 kHz coefficients (A2), channel weights and the LFE exclusion (A4), the 400 ms block and
      75 % overlap (A5), Γ<sub>a</sub> = −70 LKFS and the 10 LU relative offset (A6), and the −0.691
      conversion offset (A7).
- [x] 1.2 Record which document owns each constant — spike Part A **§A1, the attribution matrix**.
      **Every algorithm constant is BS.1770-5 Annex 1**; R 128 supplies the unit name, the *Programme
      Loudness* definition and the instruction to use eq. (7), and **no constant of its own**. Tech 3341
      supplies meter obligations, the compliance set and the LFE prohibition. Tech 3342 was read **only**
      to confirm LRA's relative gate is **−20 LU** and must not leak into this change.
- [x] 1.3 Decide the sample-rate strategy. **Found: BS.1770-5 publishes coefficients for 48 kHz only and
      states other rates as a goal — no prototype, no per-rate table, no transform, no tolerance**
      (A3). Decision recorded in ADR-0022 §3 and design §3: **recover an analogue prototype from the
      published 48 kHz coefficients and re-discretise per rate; do not resample the audio.** The claim is
      therefore **exact at 48 kHz and a demonstrated equivalence elsewhere** — a two-tier compliance
      statement the measurement's methodology must carry.
- [x] 1.4 Settle what **digital silence** reports. **Undefined**: a silent block's loudness is −∞, so no
      block passes the absolute gate, the gated set is empty and eq. (7) divides by zero (A7). BS.2217-2
      corroborates — for a file with no measurable signal the expected reading is the lowest resolvable
      value **or −infinity**, not −70. So silence → **`unavailable`**, and −70.0 is the gate, never a
      result.
- [x] 1.5 Settle the **too-short** case separately. Below 400 ms the block index set is empty, so no
      block exists at all, and Tech 3341 §2.8 states the indication before sufficient data is
      deliberately unspecified → **`unavailable`**. The boundary is **exact and inclusive: 400 ms
      measures, 399 ms does not**, confirmed against the oracle at the boundary sample.
- [x] 1.6 Confirm the treatment of **samples above unity**: BS.1770-5's loudness path has **no clamp**;
      its only attenuation is a 12.04 dB integer-headroom step in the *true-peak* Annex, which that text
      calls unnecessary in floating point (A8).
- [x] 1.7 Determine the **streaming state and memory bound** the standard implies (B9): per-sample state
      is bounded (biquad delays, a frame counter, four 100 ms sub-block sums per channel — **no sample
      buffering**), but **exact O(1) is impossible in principle** because the relative gate depends on
      the whole programme. **Chosen: one energy per block**, ≈288 kB per hour; histogram rejected.
- [x] 1.8 Identify the **official test vectors** and what may be reproduced locally (A9): **EBU Tech 3341
      Table 1 tests 1–5 and its §2.9 calibration signal** are pure tones fully specified by level and
      duration, with **published** expected values at **±0.1 LUFS**, and contain no protected material.
      Tests 7–8 are authentic programme segments — usable locally, **never committed**. BS.2217-2's WAVs
      were not obtained; the Report describes them.

## 2. The accumulator

- [ ] 2.1 `LoudnessAccumulator` in `AudioInspectorAnalysis`, taking `PCMChunk` like its three siblings,
      with per-channel filter state and **absolute** block boundaries carried across chunks.
- [ ] 2.2 Filter with `vDSP_biquad` (measured at 0.117 s for two sections over two channels of ten-minute
      stereo). Its delay state is what makes chunked streaming correct. Coefficients at 48 kHz are the
      published Table 1 / Table 2 values; other rates come from the derivation of 1.3.
- [ ] 2.3 Accumulate energy in **100 ms sub-blocks** and form each 400 ms block from the last four, so
      that **no samples are buffered**. Blocks start at frame 0; the trailing incomplete block is
      discarded; one valid block requires **T ≥ 400 ms**.
- [ ] 2.4 Gate in two passes exactly as design §6: absolute at **−70 LKFS** on the channel-weighted block
      loudness with a **strict** inequality, then a relative threshold **10 LU** below the absolutely-
      gated loudness, with **both** conditions surviving into the final set. Means are over **energies**,
      converted afterwards — never a mean of dB values. Memory stays a function of the **block count**.
- [ ] 2.5 `finish()` returns optional, like its siblings, so an unmeasurable file becomes an outcome
      rather than a fabricated number. **Both undefined cases return no value**: an empty gated set
      (silence) and an empty block set (shorter than 400 ms).
- [ ] 2.6 Channel weighting **G = 1.0** for mono and for both stereo channels (BS.1770-5 Table 3), from
      the channel count alone. **Three or more channels report no value** — the count cannot exclude an
      LFE, which the standard removes from the measurement entirely.

## 3. The domain type

- [ ] 3.1 `LoudnessMeasurement` — `Sendable`, `Equatable`, failable, **not** `Codable`. Stores **LUFS**,
      not linear energy: the normative quantity is the logarithmic one.
- [ ] 3.2 It carries its methodology, as `TruePeakMeasurement` does, and enough of it to tell the two
      compliance tiers apart: the **standard revision**, the weighting's identity, **whether the
      coefficients were the published 48 kHz set or derived for the file's rate**, block length and
      overlap, and both gate values — tied to the analysis engine version.
- [ ] 3.3 It refuses what cannot describe a measurement — non-finite values above all, the mistake
      `SignalLevelMetrics` had to be repaired for. **−∞ is not storable**, which is why the undefined
      cases are an absence rather than a value.

## 4. Numbers, decided by measurement

- [ ] 4.1 Compare `Float` against `Double` **filter state** over a ten-minute file against the published
      targets. Do not inherit signal levels' or true peak's answer; an IIR filter accumulates error
      differently from a sum. Record the result either way.
- [ ] 4.2 Energy accumulation in `Double` (measured 0.028 s), for the reason signal levels needed it.
- [ ] 4.3 **Chunk independence, exact**, at 1, 3, 127, 512, 4 096, 65 536 and whole-file. A tolerance
      here would mean the filter state or the block boundaries are not carried correctly — treat one as
      evidence for `Double` state, not as a reason to widen the bound.
- [ ] 4.4 Fix the **tolerance for "the same frequency response"** at rates other than 48 kHz, from
      measurement, and record it with the method. ADR-0022 leaves it open deliberately: the standard
      states none, and choosing one before the derivation exists is picking a number to be right about.

## 5. Correctness against published targets, then against the oracle

- [ ] 5.1 **EBU Tech 3341 Table 1, tests 1–5**, synthesised from their published description, each to the
      published **±0.1 LUFS**: #1 −23.0, #2 −33.0, **#3 −23.0 (relative gate)**, **#4 −23.0 (absolute
      gate)**, #5 −23.0 (negative control — correct gating changes nothing). These are the primary
      targets **because their expected values are published rather than observed**.
- [ ] 5.2 The two published calibration anchors: **Tech 3341 §2.9** — stereo 1 kHz at −18 dBFS peak reads
      **−18.0 LUFS**; and **BS.1770-5 Annex 1** — one channel at 0 dBFS, 997 Hz reads **−3.01 LKFS**.
- [ ] 5.3 The **undefined cases**: 400 ms measures and 399 ms does not; digital silence yields no value.
      Assert the absence, never −70.
- [ ] 5.4 Rate-invariance across 44.1/48/88.2/96/192 kHz, and the 48 kHz round-trip: the derivation of
      1.3 must reproduce the published Table 1 / Table 2 coefficients at 48 kHz.
- [ ] 5.5 **Corroboration, ranked below 5.1–5.2**: the spike's measured K-weighting response curve
      (−6.3 dB at 40 Hz … +3.4 dB at 16 kHz) and the 40 dB gating fixture reading −6.1 LUFS.
- [ ] 5.6 Cross-check real files of each container against `ffmpeg -filter_complex ebur128`, with a
      stated tolerance, behind the existing `FFmpegTool.isAvailable` pattern — **FFmpeg is not in CI**,
      and the skip message must say a skip is not agreement. **Its summary is INFO-level**:
      `-loglevel error` silently discards it. Read `I:` and the `Integrated loudness:` block's
      `Threshold:` (the **relative gate**) — **not** the `Loudness range:` block's threshold, which is a
      −20 LU gate and a silent 10 LU error. For more than one decimal use
      `ebur128=metadata=1` with `lavfi.r128.I`.
- [ ] 5.7 Negative controls, each reverted in full: weighting bypassed, gating removed, filter state
      reset per chunk, block boundaries made per-chunk, the trailing partial block included, and the
      relative gate applied without the absolute one.

## 6. The fifth consumer

- [ ] 6.1 One field on `SharedPCMAnalysisOutcome`, one accumulator in the composition, one line in each
      of `prepare`/`accumulate`/`failAll`/`finish` — the price true peak and the waveform each paid. No
      protocol, no generic machinery, **no second read**.
- [ ] 6.2 Isolation, with negative controls: its failure is its own, the read outlives it, a producer
      failure ends every consumer separately, cancellation is global, absence stays distinct from
      failure.
- [ ] 6.3 Confirm the read count is **still one**, at the gate that already asserts it.
- [ ] 6.4 Measure the real cost as a fifth consumer. Projected from the spike: **≈0.14 s** on ten minutes
      of stereo, roughly half the waveform's fold and 7–12 % of the pass it joins. Block bookkeeping and
      the two gating passes are per-block, not per-sample, and were not separately measured. A materially
      larger figure means something is being paid that the spike did not see.

## 7. Surface

- [ ] 7.1 One presentation row: "Integrated loudness", one decimal — also Tech 3341 §2.8's display
      precision — LUFS, methodology beside it. No per-channel row. Absence uses the existing
      not-computable phrasing.
- [ ] 7.2 **No verdict, and no target.** Not "too loud", not "streaming ready", no platform name, no
      normalisation advice, no comparison against −14 or **−23 — including R128's own −23.0 LUFS
      target**, which is a delivery requirement, not a property of a file.
- [ ] 7.3 Accessibility: the value and its unit are announced together, as true peak's already are.
- [ ] 7.4 Export additively under `measurements`, absent when not measured, `schemaVersion` stays **1**.

## 8. Gates and closure

- [ ] 8.1 Four gates green plus the Xcode build and `git diff --check`.
- [ ] 8.2 Update `CURRENT.md` and archive through `openspec archive` **after merge**.
