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

## 6. Correctness of the accumulator, against the vectors already fixed — **CLOSED**

The note that stood here said evidence existed at 48 kHz and was deliberately not ticked. It is now
ticked, and **the subject changed**: every target below is met by the *whole path* — a real file through
`AVFoundationAudioDecoder` and `SharedPCMAnalysisGeneration` — not by the accumulator in isolation. The
two agree to **< 1e-9 LU**, which is asserted rather than assumed, and that is what lets the
accumulator-level intermediates (the derived threshold, the block set, the chunk-independence matrix)
count as evidence about the product.

- [x] 6.1 Reproduce **Tech 3341 §2.9 and tests 1–5** within the published ±0.1 — the same vectors group 5
      fixed, now measured against production instead of against the oracle. **Done through the production
      path**, worst deviation **0.0213 LU** on test 5; §2.9 and tests 1–2 at 0.0067, tests 3–4 at 0.0139.
      Tests 3 and 4 read *identically*, which a missing absolute gate would break.
- [x] 6.2 Reproduce **BS.1770-5's anchor** (mono, 997 Hz, 0 dBFS → −3.01 LKFS) and its attenuated form.
      **Both to 0.00028 LU** through the production path, and the two sit exactly 23 LU apart — a
      relationship far tighter than either vector's own ±0.1.
- [x] 6.3 The **undefined cases** yield no value: 400 ms measures, 399 ms does not, digital silence does
      not. Assert the absence; never −70. **Done through the production path**, plus a file with no audio
      frames, plus a sweep proving no undefined case carries a number at all — and that the four analyses
      beside loudness still answer for themselves when it is absent.
- [x] 6.4 Rate-invariance across 44.1/48/88.2/96/192 kHz, and the 48 kHz round-trip. **Both demonstrated**
      — the reading moves at most 0.0066 LU across the five rates (FFmpeg's own moves 0.03), and deriving
      back to 48 kHz reproduces the published response to 0.000000 dB and its coefficients to
      1e-14. Chunk independence stays **bit-exact at every rate**.
- [x] 6.5 **Corroboration, ranked below 6.1–6.2**: the spike's measured K-weighting response curve
      (−6.3 dB at 40 Hz … +3.4 dB at 16 kHz) and the 40 dB gating fixture reading −6.1 LUFS. **Both
      reproduced through the production path**, at all ten frequencies, against ±0.05 dB on the spike's
      absolute column (half its printed digit) and ±0.1 dB on its relative column (a difference of two
      already-rounded values carries twice the rounding). The gating fixture reads −6.0795 against −6.1.
      Ranked below the published vectors in the suite's own header, as the spike itself ranks it.
- [x] 6.6 Cross-check **real files of each container** against the oracle helper built in 5.5, with a
      tolerance stated from measurement. Remember FFmpeg's own rate-invariance is 0.03 LU, so a bound
      tighter than that cannot be claimed against the oracle across rates. **Done, and the rate warning
      turned out to understate it**: at 96 and 192 kHz production and the oracle differ by 0.031 and
      0.042 LU, and the measurement shows the movement is the *oracle's* — its reading drifts 0.030 LU
      away from the published −23.0 as the rate rises while production's own spread is 0.0065 LU and it
      stays within 0.0122 of the document everywhere. So no cross-rate agreement bound is claimed;
      production is asserted against the **document** at every rate instead. Per container, on identical
      files: every lossless container agrees to **1.4e-5 LU** (bounded at 0.001), AAC moves **6.7e-4 LU**
      (bounded at 0.01, separated from meter error by being ~50× the lossless spread), and production
      agrees with the oracle to **0.0060 LU** on every one of the six.
- [x] 6.7 Negative controls against **production**, each reverted in full: weighting bypassed, gating
      removed, filter state reset per chunk, block boundaries made per-chunk, the trailing partial block
      included, and the relative gate applied without the absolute one. **All six applied and reverted**,
      plus four more (−70 adopted for silence, a measurement fabricated below 400 ms, the published
      weighting claimed at every rate, the value rounded before export). **Two findings**: the trailing
      partial block initially changed nothing, because every published vector's duration is a whole
      number of hops at 48 kHz — a fixture with a deliberately unaligned tail now closes that; and the
      relative gate without the absolute one is invisible in the *reading*, exactly as this change
      already recorded, so it is caught by the threshold evidence in "Analysis — integrated loudness
      (48 kHz)" rather than by a production assertion. `LoudnessMeasurement` was deliberately **not**
      widened to expose the threshold for a test's convenience.

## 7. The fifth consumer — **CLOSED**

- [x] 7.1 One field on `SharedPCMAnalysisOutcome`, one accumulator in the composition, one line in each
      of `prepare`/`accumulate`/`failAll`/`finish` — the price true peak and the waveform each paid. No
      protocol, no generic machinery, **no second read**. The accumulator became `public` here, which is
      the only reason it was not before.
- [x] 7.2 Isolation, with negative controls. **Loudness is the first consumer whose accumulator declines
      perfectly valid streams**, and the shape absorbed that as an **absence** rather than a fault, on
      the precedent the waveform's own already set: an unsupported rate or more than two channels leaves
      it `unavailable` and every other analysis producing a complete model. A producer failure ends all
      five, each with its own sentence; cancellation is global; and a producer that fails *after the last
      chunk* still publishes nothing.
- [x] 7.3 The read count is **still one**, at the gate that already asserts it — now with loudness in the
      list of analyses that must actually have been produced. The gate's fixture grew from 8 192 frames
      to 22 050 for that assertion to mean anything: 0.186 s is shorter than one gating block, so
      loudness would have reported no value for a reason that has nothing to do with the wiring.
- [x] 7.4 Measure the real cost as a fifth consumer. **Measured 4-against-5 rather than projected**: the
      pass goes 1.269 s → 1.524 s at 48 kHz over ten minutes of stereo, a delta of **0.255 s** against
      loudness's own **0.236 s** in isolation — so the whole increase is its DSP and no second read is
      hiding in it. The proportion holds across rates (44.1 → 0.230, 96 → 0.488, 192 → 0.885), which is
      what a per-sample cost looks like. Its share of the pass is **11–17 %** depending on container
      against the spike's projected 7–12 %: over at the cheap end (WAV, where decode is nearly free) and
      inside it for FLAC and AAC.
- [x] 7.5 **No reachable failure of its own**, audited rather than assumed. Every way loudness ends
      without a value is an absence — the accumulator declining the stream, or the standard defining no
      result — and the one path that would be a genuine failure, a non-finite loudness, is unreachable
      from `PCMChunk`'s finite `Float`s. Recorded as a limitation, exactly as signal levels' own `nil` is.

## 8. Surface — **CLOSED**

- [x] 8.1 One presentation row: "Integrated loudness", one decimal — also Tech 3341 §2.8's display
      precision — LUFS, methodology beside it. No per-channel row. Absence uses the existing
      not-computable phrasing. **A section of its own**, between true peak and the spectrogram: it is a
      programme measurement with a methodology that has to travel with it, and a row has nowhere to put
      one. `LoudnessRow` has no `detail` field at all, because the channels are combined before the
      quantity exists. `HumanFormat.loudnessFullScale` converts nothing and floors nothing — unlike its
      two decibel siblings there is no `log10(0)` to reach an infinity through.
- [x] 8.2 **No verdict, and no target.** Swept over every string the surface can produce, in every
      state, by word-split rather than substring (so "loudness" is not read as "loud"). Also swept: no
      platform, no −14/−16/−23 quoted in prose, and **no standard worn as a seal** — the methodology is
      stated in plain words, and naming BS.1770 or R 128 on screen would read as certification. The full
      identity travels on the wire instead. Five negative controls applied and reverted: −70 as absence,
      "too loud" in the copy, dBFS as the unit, positives clamped, a platform target added.
- [x] 8.3 Accessibility: the value and its unit are announced together, as true peak's already are —
      `"Integrated loudness, -23.0 LUFS"`. The method is spoken separately, prefixed "How it was
      measured." A positive value gets no different name, no different shape and no colour.
- [x] 8.4 Export additively under `measurements`, absent when not measured, `schemaVersion` stays **1**.
      **`measurements.integratedLoudness`, naming the quantity rather than the family** — a `loudness`
      object with one `method` would imply it covered momentary, short-term and LRA too. **LUFS on the
      wire, unrounded**, deliberately the opposite of true peak's linear rule: here the logarithmic
      quantity is the normative one. Both identities come from the measurement's own record; the mapper
      never infers a weighting from a sample rate it cannot see. Absence is the key omitted, never
      `null`. Five export negative controls applied and reverted: a rounded value, linear energy, a
      hardcoded published weighting, `"integratedLoudness": null`, and `compliant: true`.
      `docs/json-schema-v1.md` updated.

## 9. Gates and closure

- [x] 9.1 Four gates green plus the Xcode build and `git diff --check`. **All seven green from the final
      documentary state**, with `swift test` run twice to catch a flake and none appearing: 1 252 tests in
      126 suites, boundaries respected, a zero-warnings build, the Xcode Debug app target built, OpenSpec
      strict at 8/8, and a clean `git diff --check`.
- [ ] 9.2 Update `CURRENT.md` and archive through `openspec archive` **after merge**.
