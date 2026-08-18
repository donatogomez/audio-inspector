# ADR-0022: Integrated loudness — how far compliance is claimed, and what the domain stores

- **Status**: **Proposed.** The blocking condition of the first draft — that the normative constants had
  not been read — **is discharged**: BS.1770-5, R 128 v5.0, Tech 3341 v4, Tech 3342 v4 and Report
  BS.2217-2 were obtained and read, and every constant is now sourced in
  `docs/spikes/2026-08-18-loudness-measurement-validation.md` Part A. It stays **Proposed** until the
  implementation reproduces the **published** acceptance targets — EBU Tech 3341 tests 1–5 and its §2.9
  calibration signal, within the published ±0.1 LUFS — plus rate-invariance and chunk-independence, each
  by a test that fails when the property is broken, and until the manual validation battery has run.
  Partial evidence does not promote it.
- **Date**: 2026-08-18
- **Deciders**: Project maintainer
- **Related**: **ADR-0006** (which chose the standard and the oracle and left the constants to this
  change; *referenced, not edited*), ADR-0009, ADR-0019, ADR-0020, ADR-0021,
  `docs/spikes/2026-08-18-loudness-measurement-validation.md`, change `add-loudness-measurement`

## Context

ADR-0006 decided that loudness follows ITU-R BS.1770 / EBU R128, is implemented natively in
`AudioInspectorAnalysis`, is cross-checked against FFmpeg `ebur128`, and pins every constant to the
analysis engine version. All of that stands.

It did not decide five things that turn out to matter more than the algorithm:

1. **how far compliance may be claimed**, given both the pipeline's ignorance of channel layout *and* —
   discovered by reading the text — a gap in the Recommendation itself;
2. **what the domain stores** — LUFS, or linear energy converted at the surface;
3. **which of the four loudness quantities ships first**;
4. **what a silent or too-short file reports**;
5. **what "the methodology" concretely is**, now that it is not the same claim at every sample rate.

The reading settled the fourth and reshaped the first. The decisive discovery is in decision 3 below.

## Decision

1. **Integrated loudness ships alone.** It is the only one of the four whose value is unambiguous in a
   static report. Momentary and short-term are meter readings: "Momentary: −14.2 LUFS" is meaningless
   without saying *when*, and choosing the reduction — maximum, last, a timeline — is a product decision
   this record does not make. They are cheap to compute; that is not the reason to ship them. LRA depends
   on short-term and therefore cannot precede it — **and it uses a different relative gate, −20 LU
   against integrated loudness's −10 LU** (Tech 3342 vs BS.1770-5 eq. (6)), which is exactly the kind of
   constant that leaks between features built together.

2. **The methodology is BS.1770-5, and the attribution is exact.** Every constant — the two filter
   stages, the channel weights, the 400 ms block, the 75 % overlap, both gates, the −0.691 offset —
   comes from **ITU-R BS.1770-5 (11/2023), Annex 1**. **EBU R 128 v5.0 supplies no algorithm constant at
   all**; it supplies the unit name LUFS (equivalent to BS.1770's LKFS), the definition of *Programme
   Loudness*, and the requirement to use BS.1770 eq. (7). This project does not attribute one document's
   rules to the other, and does not cite "R128" for a number that BS.1770 owns.

3. **Compliance is claimed as exact at 48 kHz and as a demonstrated equivalence elsewhere — because
   that is all the Recommendation offers.** BS.1770-5 publishes filter coefficients **for 48 kHz only**
   and states the requirement for every other rate as a *goal*: coefficients should be chosen to give
   the same frequency response as at 48 kHz. It publishes **no** analogue prototype, **no** per-rate
   table, **no** discretisation method and **no** tolerance on "the same response".

   So the honest claim has two tiers, and the product must never blur them:

   - **at 48 kHz** — the published coefficients are used literally; conformance to the published filter
     definition is exact;
   - **at every other rate** — the coefficients are **ours**, derived to satisfy a normative *property*.
     The claim is conformance of a derivation we chose, demonstrated by measurement.

   **The derivation is a decision of this project, recorded here**: recover an analogue prototype from
   the published 48 kHz coefficients and re-discretise it at the target rate, rather than resampling the
   audio to 48 kHz. Resampling was rejected because it inserts a converter into the measurement path,
   alters the signal being measured, and would make the reported figure depend on a resampler this
   project does not otherwise need. The derivation's **acceptance property is testable and mandatory**:
   at 48 kHz it must reproduce the published coefficients, and at every supported rate the measured
   result must be rate-invariant to a stated bound. A derivation that cannot demonstrate that is not
   shipped.

4. **Compliance is claimed for mono and stereo, and for nothing else.** BS.1770-5 Table 3 weights L, R
   and C at 1.0 and Ls/Rs at 1.41; Annex 3 generalises this to a weight that depends on a channel's
   **azimuth and elevation**, never on its index. `PCMStreamDescription` carries no layout, and the
   property reader deliberately never infers position from layouts or labels.

   One channel is safe because it can only be L, C or R and all three weigh 1.0. Two channels are safe
   because the only two-channel BS.2051 configuration weights both at 1.00 and contains no LFE.
   **Three channels is where it breaks, and it is the case that settles the question**: L/C/R would all
   weigh 1.0, but a three-channel file could equally carry an **LFE, which BS.1770-5 excludes from the
   measurement entirely** and which Tech 3341 §2.10 forbids including. Excluding the wrong channel — or
   none — moves the result by far more than the ±0.1 LUFS the standards themselves tolerate.

   **So for other configurations no value is published.** An absence, not a failure, and not a number
   computed from a guessed layout. Reading `AVAudioChannelLayout` to extend this is a separate change: it
   touches the property reader, the domain and the boundary rules.

5. **The domain stores LUFS.** True peak stores linear because dBTP is a *presentation* of a linear peak;
   here the normative quantity **is** the logarithmic one. Storing linear energy and converting at the
   surface would invent a unit the standard does not use and would move the conversion offset into a
   layer that cannot be checked against the oracle. This is deliberately **not** the rule ADR-0019 set for
   true peak, and the difference is the point.

6. **Digital silence and a too-short programme both report no value, and neither reports −70.**
   BS.1770-5 makes both undefined, by two different routes: a silent block's loudness is −∞ and so fails
   the absolute gate, leaving the gated set empty and eq. (7) dividing by zero; a programme shorter than
   one 400 ms block produces no gating block at all, and Tech 3341 §2.8 states that what a meter shows
   before there is sufficient data is deliberately unspecified. Report BS.2217-2 confirms the direction:
   for a file with no measurable signal its expected reading is the lowest resolvable value **or
   −infinity** — the ITU's own compliance material declines to name −70.

   **−70 LUFS is the absolute gate, not a result.** The reference implementation reports exactly
   −70.000 for both cases; that is its floor, and copying it would tell a user their silent file measures
   the same as their 300 ms file — two untruths at once. Both are `unavailable`.

   The **causes stay distinct in the record even though the outcome is one absence**: silence produced
   blocks and gated every one away; a short file produced none. The threshold between them is exact and
   inclusive — **400 ms measures, 399 ms does not** — which follows from the block index set and was
   confirmed at the boundary sample against the oracle.

7. **Samples above unity are measured, not clamped.** BS.1770-5's loudness path contains no clamp, limit
   or headroom step; its only attenuation is a 12.04 dB integer-headroom step in the *true-peak* Annex,
   which the text itself calls unnecessary in floating point. The project's existing no-clamp expectation
   is not merely compatible with the methodology — it is what the methodology says.

8. **The measurement carries its methodology**, as `TruePeakMeasurement` does (ADR-0019) — and decision 3
   makes this heavier than it was. What travels with the value must be enough to reproduce it and to tell
   the two compliance tiers apart: **the standard revision (BS.1770-5), the weighting's identity, whether
   the coefficients were the published 48 kHz set or derived for the file's rate, the block length and
   overlap, and both gate values**, tied to the analysis engine version. A figure whose tier is not
   visible would let an exact claim and a derived one look identical on the page, which is the one thing
   decision 3 exists to prevent.

9. **It is a sibling type, not an extension of `SignalLevelMetrics`.** Those are direct sample-domain
   facts, per channel, unweighted and untimed. Loudness is frequency-weighted, gated, time-blocked and
   whole-file — there is no per-channel loudness, because the channels are combined before the quantity
   exists. One type holding both would invite exactly the confusion this product exists to avoid.

10. **It is a consumer of the existing shared read**, the fifth, at the price the fourth paid: one field,
    one accumulator, one line in each composition method. **No second read**, no new abstraction.

    **Cost, now measured on the implementation rather than projected**: the fold is **0.243 s** over ten
    minutes of stereo in Release, and the gating pass at the end is 0.0001 s. The spike projected 0.14 s
    from Accelerate's biquad; the implementation is **1.7× that**, and the whole difference is the price
    of decision 14 below. It remains under the waveform's own 0.30 s fold and comfortably affordable on a
    read that already happens — but the earlier figure is superseded, not merely refined.

11. **Per-block energies are retained; an exact O(1) implementation is not attempted, because none
    exists.** The relative gate is derived from the whole programme, so whether a block survives eq. (7)
    cannot be decided when that block is produced. Memory is therefore **one energy per block** — 10
    blocks per second, ≈288 kB per hour as `Double` — which keeps the standing rule that memory is a
    function of the block count and never of the sample count. A histogram was rejected: it trades an
    exactness the standards budget at ±0.1 LUFS for memory the measurement does not need.

12. **No verdict, ever.** The report states the measurement. Not "too loud", not "too quiet", not "ready"
    for any platform, no platform target named, no normalisation advice, no comparison against −14 or
    **−23 — including the −23.0 LUFS target that EBU R 128 itself recommends**, which this project reads
    as a broadcast delivery requirement and not as a property of a file. Loudness is the metric most
    likely to invite a judgement, which is why the prohibition is written into the record rather than
    left to taste. Loudness *findings* are a different capability and are out of scope.

13. **The acceptance targets are the published ones.** EBU Tech 3341 Table 1 tests **1–5** are pure tones
    fully specified by level and duration, synthesisable from their description with no protected
    material, and carry **published** expected values at **±0.1 LUFS** — tests 3 and 4 being the relative-
    and absolute-gate discriminators respectively. Its §2.9 calibration signal and BS.1770-5's own anchor
    (one channel at 0 dBFS, 997 Hz, reads −3.01 LKFS) complete the set. **The first session's invented
    fixtures are demoted to corroboration**, because an observed target only proves agreement with the
    thing observed. Tech 3341 tests 7–8 are authentic programme segments: usable locally, **never
    committed**.

    **These targets were made executable before any production existed**, and that ordering is part of
    the decision rather than a scheduling accident: a target fixed after the implementation is a target
    that was fitted to it. Measuring them established the one number that makes the cross-check worth
    running — **FFmpeg 8.1.2 reproduces every published expectation with a worst deviation of 0.021 LU**,
    five times inside the published tolerance — and one that bounds it: **the oracle's own
    rate-invariance is 0.03 LU, not zero**, so no tighter agreement may be claimed against it across
    sample rates.

14. **Chunk independence is exact, and it cost the fast primitive.** `vDSP_biquadD` was implemented first
    and rejected on measurement: its output changed in the last two or three significant digits with the
    chunk size it was handed, because how it groups an IIR's work depends on the length of the run. A
    scalar transposed-direct-form-II recurrence has no such grouping. Every other analysis in this package
    is chunk-independent *exactly*, and a loudness figure that moved with the decoder's buffer size would
    be a reproducibility defect at any magnitude — so the slower, exact route is the one that ships, and
    the ~0.1 s it costs is recorded rather than hidden.

15. **`Double` throughout, decided by measurement and not inherited.** `Float` and `Double` filter state
    were both implemented and compared over the published vectors: they differ by at most **1.4 × 10⁻⁵
    LU**, both are chunk-exact, and both cost 0.469 s in the sequential form. `Float` buys nothing
    measurable, so the wider type keeps the headroom for free. This is deliberately *not* the answer
    `TruePeakAccumulator` reached for its own arithmetic, and the difference is that a maximum accumulates
    no error while an IIR and an energy sum both can.

## Deliberately left open

- **The numeric tolerance of "the same frequency response"** at rates other than 48 kHz (decision 3).
  The Recommendation states none, so it is ours to set, and setting it before the derivation exists would
  be picking a number to be right about. It is fixed by the change's task group, from measurement, and
  recorded with the method.
- **The oracle comparison tolerance on real files.** The published compliance tolerance is ±0.1 LUFS and
  the oracle's summary prints one decimal, so a tighter bound requires its three-decimal metadata route.
  A definitive figure waits on an implementation to compare.

## Alternatives considered

- **Ship Integrated, Momentary and Short-Term together.** They share the weighting, so the marginal cost
  is small. Rejected: each needs a reduction decision before it means anything in a report, and shipping
  them un-reduced publishes numbers whose meaning has not been decided.
- **Resample non-48 kHz audio to 48 kHz and use the published coefficients.** It would make every file an
  exact-tier claim. Rejected — see decision 3: it measures a converted signal rather than the file.
- **Claim plain "BS.1770 compliance" at all rates.** Simpler to say and what most tools say. Rejected: the
  Recommendation does not publish what would make it true, and this product's claim is that it does not
  overstate.
- **Extend `SignalLevelMetrics` with a loudness field.** Fewer types. Rejected — see decision 9.
- **Store linear energy and convert in the view**, as true peak does. Rejected — see decision 5.
- **Assume channel order (0 = L, 1 = R, …) for surround.** It would let us publish a number for any file.
  Rejected: it is a guess wearing a measurement's clothes, and the LFE case in decision 4 shows the guess
  is wrong in a way that exceeds the standard's own tolerance.
- **A histogram of block loudnesses**, as fast reference implementations use. Rejected — see decision 11.
- **Report −70.0 LUFS for silence**, as the reference implementation does. Rejected — see decision 6.
- **Shell out to FFmpeg for the shipped value.** Accurate and free. Rejected by ADR-0006 and unchanged;
  it remains the oracle — and it is now a *qualified* one, having passed Tech 3341 tests 1–5 and the §2.9
  calibration within the published tolerance.

## Consequences

### Positive
- The measurement most users compare masters by, produced from a read that already happens.
- The compliance claim matches what can actually be demonstrated, per configuration **and per sample
  rate**, and the methodology that travels with the value makes the difference visible.
- The unit decision keeps the conversion offset where it can be tested.
- Every constant is sourced to a document, a revision and a section, so a future revision of BS.1770 is a
  diff against a known baseline rather than an investigation.

### Negative / costs
- **Surround and multichannel files get no loudness figure at all** until a separate change teaches the
  pipeline about layout. For those users the feature is simply absent, and that will look like a gap.
- **Momentary, short-term and LRA are absent**, which some will read as an unfinished loudness suite.
  Accepted deliberately: a meter reading without a stated reduction is not a report.
- **The two-tier compliance claim is harder to explain** than "BS.1770-compliant", and is weaker than
  what competing tools assert without qualification. Accepted: the alternative is a claim the
  Recommendation does not support.
- **Silent files show an absence where users expect a number.** Accepted; the number would be a floor
  wearing a measurement's clothes.
- The correctness burden is high and front-loaded — though materially lower than when this record was
  first drafted, because the targets are now published rather than observed.

### Neutral
- No port changes, no domain type changes beyond the new one, no export version change, no new
  dependency, and no second read.
- The oracle remains absent from CI, so its suite stays local evidence behind the existing
  `FFmpegTool.isAvailable` pattern, with a skip message that says a skip is not agreement.
