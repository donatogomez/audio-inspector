# Implementation Tasks

The investigation is done and lives in `docs/spikes/2026-08-18-loudness-measurement-validation.md` —
**Part A normative, Part B measured, never mixed.** Group 1 existed because the first session could not
resolve the normative constants. **It is now closed**: the standards were obtained and read, and every
constant is sourced. Nothing below may be built on a remembered number.

**Group 5 was closed out of order, and deliberately.** The official vectors and the oracle were built
*before* any production, so the targets could not be fitted to whatever got written. They were not
touched afterwards.

**Groups 2, 3 and 4 are closed**, now at every supported sample rate. The accumulator returns the domain
model, and the two weighting tiers — published at 48 kHz, derived elsewhere — are distinguishable on the
value itself. **Group 6 stays open** apart from 6.4: what remains there is the cross-container oracle
comparison and the production negative controls. Groups 7–9 are the shared-read wiring, the surface and
the export, none of it started.

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

## 2. The accumulator — **CLOSED**, at every supported rate

- [x] 2.1 `LoudnessAccumulator` in `AudioInspectorAnalysis`, taking `PCMChunk` like its three siblings,
      with per-channel filter state and **absolute** block boundaries carried across chunks. **Mono and
      stereo only**, at the rates task 2.8 lists, and every refusal is the failable initialiser its
      siblings already use. It is deliberately **not `public`**; it returned a bare LUFS `Double?` until group 3 existed,
      so that the shape crossing the module boundary would be the domain type's rather than the
      accumulator's convenience. It now returns `LoudnessMeasurement?` (task 3.5).
- [x] 2.2 ~~Filter with `vDSP_biquad`.~~ **Implemented and rejected on measurement**: its output changed
      in the last two or three significant digits with the chunk size it was handed
      (−23.385524041147569 at one frame per chunk against −23.385524041147661 whole-file), because how it
      groups an IIR's work depends on the length of the run. Replaced by a scalar transposed-direct-form-II
      recurrence, which has no grouping to vary and is exact. The 48 kHz coefficients are the published
      Table 1 / Table 2 values, transcribed; other rates are derived per task 2.8.
- [x] 2.3 Accumulate energy in **100 ms sub-blocks** and form each 400 ms block from the last four, so
      that **no samples are buffered**. Blocks start at frame 0; the trailing incomplete block is
      discarded; one valid block requires **T ≥ 400 ms**.
- [x] 2.4 Gate in two passes exactly as design §6: absolute at **−70 LKFS** on the channel-weighted block
      loudness with a **strict** inequality, then a relative threshold **10 LU** below the absolutely-
      gated loudness, with **both** conditions surviving into the final set. Means are over **energies**,
      converted afterwards — never a mean of dB values. Memory stays a function of the **block count**.
- [x] 2.5 `finish()` returns optional, like its siblings, so an unmeasurable file becomes an outcome
      rather than a fabricated number. **Both undefined cases return no value**: an empty gated set
      (silence) and an empty block set (shorter than 400 ms).
- [x] 2.6 Channel weighting **G = 1.0** for mono and for both stereo channels (BS.1770-5 Table 3), from
      the channel count alone. **Three or more channels report no value** — the count cannot exclude an
      LFE, which the standard removes from the measurement entirely.
- [x] 2.7 Expose the **derived relative threshold**, because a negative control showed the reading alone
      does not prove the absolute gate ran: with the gate removed, Tech 3341 tests 3 and 4 still produce
      identical values, since the relative gate happens to exclude the same blocks by itself. The
      threshold is where the difference shows, and FFmpeg reports the same quantity.
- [x] 2.8 **Multi-rate weighting.** 44.1 / 48 / 88.2 / 96 / 192 kHz. At 48 kHz the published
      coefficients run **literally** — not through the derivation, whose round-trip is exact in the
      response (0.000000 dB) but not bit-identical in the coefficients (4.4 × 10⁻¹⁶). Every other rate is
      derived by a per-stage prewarped bilinear round-trip, worst response error **0.0077 dB**, all poles
      inside the unit circle, reading invariant to **0.0066 LU**. The supported set is **enumerated**:
      an unmeasured rate is refused rather than derived for. Evidence in spike Part D.

## 3. The domain type — **CLOSED**

- [x] 3.1 `LoudnessMeasurement` — `Sendable`, `Equatable`, failable, **not** `Codable`, and not
      `Hashable` or `Comparable` either: there is no order over two measurements with their own methods,
      and nothing keys a dictionary by one. Stores **LUFS**, not linear energy. It carries **no channel
      count and no sample rate**: both describe the file, are already reported by the technical
      properties, and would be a second description this type could not keep consistent with the first.
- [x] 3.2 It carries its methodology as `TruePeakMeasurement` does — but as **two identities and no
      constants**, which is not the shape this task predicted. `LoudnessMethod` holds an `algorithm`
      identifier (`itu_r_bs1770_5_integrated_v1`, the revision embedded rather than beside it) and a
      `weighting` identifier naming where the coefficients came from
      (`itu_r_bs1770_5_tables_1_2_48k`). Block length, hop and both gate values are **not** fields: they
      are fixed by the algorithm identifier, and carrying them would put contradictory states within
      reach that the type could not police — the same reason `TruePeakMethod` carries an identity rather
      than its filter's design.
- [x] 3.3 It refuses what cannot describe a measurement: `isFinite` rejects `NaN`, signalling `NaN` and
      both infinities in one guard — the check `SignalLevelMetrics` had to be repaired to include, here
      from the start. **−∞ is a silent block's own loudness and is not storable**, which is why the
      undefined cases are an absence rather than a value. **No range is imposed**: the standard states
      none, a programme above full scale legitimately reads positive, and −70 is a threshold on blocks
      rather than a floor on the result.
- [x] 3.4 **No conformance, compliance or certification field, and no target level.** A measurement
      cannot certify itself; agreement with an independent meter is test-time evidence about an
      implementation, not a property of a file. The identities record *what ran*; whether that amounts to
      conformance is a judgement no value type is in a position to make. Asserted by a test over the
      identifiers' own vocabulary, not left to review.
- [x] 3.5 `LoudnessAccumulator.finish()` now returns `LoudnessMeasurement?`, and the accumulator declares
      the method itself — the type that measured is the only one that can name what it ran. Confirmed:
      nothing in App or Feature spells the identifiers. No value changed and no tolerance moved; only
      the return type did.

## 4. Numbers, decided by measurement

- [x] 4.1 Compare `Float` against `Double` **filter state** over a ten-minute file against the published
      targets. **Measured**: both widths implemented, readings differ by at most **1.4 × 10⁻⁵ LU**, both
      chunk-exact, and both cost **0.469 s** — the loop is bound by the recurrence's latency, not by the
      width. `Float` buys nothing, so `Double` keeps the headroom for free. Not the answer true peak
      reached, and the difference is that a maximum accumulates no error while an IIR does.
- [x] 4.2 Energy accumulation in `Double`, for the reason signal levels needed it — and accumulated
      **into the running total** in index order rather than as per-piece partial sums, which is what makes
      the reduction itself chunk-independent.
- [x] 4.3 **Chunk independence, exact**, at 1, 3, 127, 512, 4 096, 65 536 and whole-file. Bit-identical,
      not within a tolerance. This is the assertion that made `vDSP_biquadD` unusable (2.2). The two
      published gating vectors are 80 and 100 seconds long, so they are covered from 512 upwards and
      shapes carrying the same structure cover 1 and 3.
- [x] 4.4 Fix the **tolerance for "the same frequency response"** at rates other than 48 kHz, from
      measurement. **0.02 dB**, chosen after measuring rather than before: five times inside the
      publishers' ±0.1 LUFS, under FFmpeg's own 0.03 LU drift across the same rates, and a factor of 2.6
      over the 0.0077 dB the derivation actually produces. Deliberately not set at the observed error.
- [x] 4.5 Decide the **coefficient precision**. `Double`, measured: quantising to `Float` costs 0.0146 dB
      of response error at 192 kHz — three quarters of the whole budget — against 0.000025 dB at 48 kHz.
      All remain stable, so this is accuracy rather than safety, and avoiding it costs nothing.

## 5. The official vectors and the oracle — **CLOSED**, and closed before any production exists

Fixing the targets first is the point: a target validated after the implementation is a target that was
fitted to it. Nothing in this group compares production against anything, because there is no production.

- [x] 5.1 Transcribe **EBU Tech 3341 §2.9 and Table 1 tests 1–5** as executable vectors carrying the
      publishers' expected readings and the publishers' **±0.1 LUFS**, each tagged with the document and
      section it came from. Tests 6 (5.0), 7–8 (authentic programme, **never committed**) and 9–23 are
      out of scope and recorded as such.
- [x] 5.2 A **native, deterministic** fixture generator: `AudioFixtureSignal` gains one case for a tone
      whose amplitude steps between regions, written as float32 through the existing `AVAudioFile`
      writer. No Python, no FFmpeg to generate, no third-party library, no audio binary in the
      repository, and the phase is absolute so a level change does not inject a step.
- [x] 5.3 Transcription guards that need **no meter**, because the oracle cannot supply them: a steady
      stereo 1 kHz vector's expected reading equals the level it is described with; the published
      durations and levels are stated a second time; the three steady vectors' expectations are
      collinear. A wrong level or a wrong duration is otherwise invisible to a fixture check.
- [x] 5.4 Show each vector **discriminates something its neighbours do not** — and that tests 3 and 5
      *bracket* the relative offset from opposite sides, since neither pins it alone. Demonstrated with a
      deliberately simplified segment reduction that is explicitly **not** BS.1770.
- [x] 5.5 An oracle helper over the existing `FFmpegTool`: one invocation yielding both channels, the
      integrated value from `lavfi.r128.I` at three decimals, and the threshold parsed **section-aware**
      so the `Loudness range:` block's −20 LU gate can never be read as the integrated one. Three
      distinct failure modes — tool absent, tool failed, output unparseable.
- [x] 5.6 **Qualify the oracle**: FFmpeg 8.1.2 reproduces every published expectation within the
      published tolerance, worst deviation **0.021 LU**. Measured, not assumed.
- [x] 5.7 **BS.1770-5's own anchor** as a separate vector — mono, **997 Hz**, 0 dBFS → −3.01 LKFS — with
      the borrowed tolerance recorded as borrowed.
- [x] 5.8 Derived vectors, labelled derived: the **399/400/401 ms** boundary, **digital silence**, the
      **44.1–192 kHz** sweep, and the **mono/stereo** pair. Measured: the boundary is inclusive at 400 ms,
      both undefined cases show the oracle's floor, the sweep drifts 0.03 LU, and the pair differs by
      3.0100 against a predicted 3.0103.
- [x] 5.9 **Split by tool dependence** so CI keeps the vectors' value: transcription, discrimination and
      output parsing run everywhere; only the measurement is gated on `FFmpegTool.isAvailable`, with a
      skip message stating that a skip is not evidence.
- [x] 5.10 **Negative controls, each applied and reverted**: a wrong amplitude, a wrong duration, parsing
      the LRA threshold as the integrated one, and adopting the −70 floor as a reading. Each was caught,
      and by the test that should have caught it.

## 6. Correctness of the accumulator, against the vectors already fixed

**Evidence already exists for most of this at 48 kHz and is deliberately not ticked**, because the group
is written for the finished accumulator and 6.4 cannot be satisfied until the per-rate derivation lands.
What passes today, in "Analysis — integrated loudness (48 kHz)" and the oracle suite: every published
vector within the published ±0.1 (worst deviation **0.0213 LU**, on test 5); both BS.1770-5 anchors to
**0.0003 LU**; agreement with FFmpeg to **0.0071 LU**; the undefined cases; and the negative controls.

- [ ] 6.1 Reproduce **Tech 3341 §2.9 and tests 1–5** within the published ±0.1 — the same vectors group 5
      fixed, now measured against production instead of against the oracle.
- [ ] 6.2 Reproduce **BS.1770-5's anchor** (mono, 997 Hz, 0 dBFS → −3.01 LKFS) and its attenuated form.
- [ ] 6.3 The **undefined cases** yield no value: 400 ms measures, 399 ms does not, digital silence does
      not. Assert the absence; never −70.
- [x] 6.4 Rate-invariance across 44.1/48/88.2/96/192 kHz, and the 48 kHz round-trip. **Both demonstrated**
      — the reading moves at most 0.0066 LU across the five rates (FFmpeg's own moves 0.03), and deriving
      back to 48 kHz reproduces the published response to 0.000000 dB and its coefficients to
      1e-14. Chunk independence stays **bit-exact at every rate**.
- [ ] 6.5 **Corroboration, ranked below 6.1–6.2**: the spike's measured K-weighting response curve
      (−6.3 dB at 40 Hz … +3.4 dB at 16 kHz) and the 40 dB gating fixture reading −6.1 LUFS.
- [ ] 6.6 Cross-check **real files of each container** against the oracle helper built in 5.5, with a
      tolerance stated from measurement. Remember FFmpeg's own rate-invariance is 0.03 LU, so a bound
      tighter than that cannot be claimed against the oracle across rates.
- [ ] 6.7 Negative controls against **production**, each reverted in full: weighting bypassed, gating
      removed, filter state reset per chunk, block boundaries made per-chunk, the trailing partial block
      included, and the relative gate applied without the absolute one.

## 7. The fifth consumer

- [ ] 7.1 One field on `SharedPCMAnalysisOutcome`, one accumulator in the composition, one line in each
      of `prepare`/`accumulate`/`failAll`/`finish` — the price true peak and the waveform each paid. No
      protocol, no generic machinery, **no second read**.
- [ ] 7.2 Isolation, with negative controls: its failure is its own, the read outlives it, a producer
      failure ends every consumer separately, cancellation is global, absence stays distinct from
      failure.
- [ ] 7.3 Confirm the read count is **still one**, at the gate that already asserts it.
- [ ] 7.4 Measure the real cost as a fifth consumer. Projected from the spike: **≈0.14 s** on ten minutes
      of stereo, roughly half the waveform's fold and 7–12 % of the pass it joins. Block bookkeeping and
      the two gating passes are per-block, not per-sample, and were not separately measured. A materially
      larger figure means something is being paid that the spike did not see.

## 8. Surface

- [ ] 8.1 One presentation row: "Integrated loudness", one decimal — also Tech 3341 §2.8's display
      precision — LUFS, methodology beside it. No per-channel row. Absence uses the existing
      not-computable phrasing.
- [ ] 8.2 **No verdict, and no target.** Not "too loud", not "streaming ready", no platform name, no
      normalisation advice, no comparison against −14 or **−23 — including R128's own −23.0 LUFS
      target**, which is a delivery requirement, not a property of a file.
- [ ] 8.3 Accessibility: the value and its unit are announced together, as true peak's already are.
- [ ] 8.4 Export additively under `measurements`, absent when not measured, `schemaVersion` stays **1**.

## 9. Gates and closure

- [ ] 9.1 Four gates green plus the Xcode build and `git diff --check`.
- [ ] 9.2 Update `CURRENT.md` and archive through `openspec archive` **after merge**.
