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

   **What may be said, now that the derivation exists and has been measured**: *integrated loudness per
   ITU-R BS.1770-5 Annex 1; at 48 kHz the published coefficients; at 44.1, 88.2, 96 and 192 kHz a
   weighting derived to reproduce that response, measured within 0.0077 dB.* **What may never be said**:
   that BS.1770 publishes coefficients for any rate other than 48 kHz, or that a derived measurement is
   "normative" or "certified" at that rate.

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

8. **The measurement carries its methodology**, as `TruePeakMeasurement` does (ADR-0019) — as **two
   identities and no constants**. `LoudnessMethod` holds an **algorithm identity**, with the standard's
   revision embedded in it rather than beside it, and a **weighting identity** naming where the
   coefficients came from. The second exists because of decision 3: the published 48 kHz set and a later
   derivation are different provenances for the same algorithm, and a figure whose provenance was not
   visible would let an exact claim and a derived one look identical on the page.

   **The block length, the hop and both gate values are deliberately not fields.** They are fixed by the
   algorithm identity, and carrying them would make contradictory states representable — a block length
   disagreeing with the identifier naming it — which the type could not police, because it cannot see the
   evidence the constants came from. This supersedes what this record predicted before the type existed.

   **The same identity implies the same number.** Changing any rule the algorithm identity names requires
   a new version of it, and changing how the coefficients are obtained requires a new weighting identity.

9. **The result records what ran, and never that it conformed.** There is no compliance, conformance,
   certification, "EBU Mode" or target-level field, and none may be added. A measurement cannot certify
   itself: conformance is a claim about a process, asserted by whoever holds the evidence, and agreement
   with an independent meter is *test-time evidence about an implementation* rather than a property of a
   file. Mono/stereo is a supported scope, not a certification; 48 kHz is where the coefficients are
   published, not a grade. Recording a verdict here would also be the one thing decision 13 forbids
   everywhere else in the report.

10. **It is a sibling type, not an extension of `SignalLevelMetrics`.** Those are direct sample-domain
   facts, per channel, unweighted and untimed. Loudness is frequency-weighted, gated, time-blocked and
   whole-file — there is no per-channel loudness, because the channels are combined before the quantity
   exists. One type holding both would invite exactly the confusion this product exists to avoid.

11. **It is a consumer of the existing shared read**, the fifth, at the price the fourth paid: one field,
    one accumulator, one line in each composition method. **No second read**, no new abstraction.

    **Cost, now measured on the implementation rather than projected**: the fold is **0.243 s** over ten
    minutes of stereo in Release, and the gating pass at the end is 0.0001 s. The spike projected 0.14 s
    from Accelerate's biquad; the implementation is **1.7× that**, and the whole difference is the price
    of decision 15 below. It remains under the waveform's own 0.30 s fold and comfortably affordable on a
    read that already happens — but the earlier figure is superseded, not merely refined.

    **And the claim of "no second read" is now measured end to end.** Wiring it as the fifth consumer
    takes the shared pass from **1.269 s to 1.524 s** at 48 kHz over ten minutes of stereo — a delta of
    **0.255 s** against loudness's own 0.236 s in isolation. The increase *is* its DSP; nothing else
    appeared. The proportion holds at every rate, which is what a per-sample cost looks like and what an
    extra decode would not. Its share of the pass is **11–17 %** by container against the projected
    7–12 %: over at the cheap end, where decode is nearly free, and inside it for FLAC and AAC.

12. **Per-block energies are retained; an exact O(1) implementation is not attempted, because none
    exists.** The relative gate is derived from the whole programme, so whether a block survives eq. (7)
    cannot be decided when that block is produced. Memory is therefore **one energy per block** — 10
    blocks per second, ≈288 kB per hour as `Double` — which keeps the standing rule that memory is a
    function of the block count and never of the sample count. A histogram was rejected: it trades an
    exactness the standards budget at ±0.1 LUFS for memory the measurement does not need.

13. **No verdict, ever.** The report states the measurement. Not "too loud", not "too quiet", not "ready"
    for any platform, no platform target named, no normalisation advice, no comparison against −14 or
    **−23 — including the −23.0 LUFS target that EBU R 128 itself recommends**, which this project reads
    as a broadcast delivery requirement and not as a property of a file. Loudness is the metric most
    likely to invite a judgement, which is why the prohibition is written into the record rather than
    left to taste. Loudness *findings* are a different capability and are out of scope.

14. **The acceptance targets are the published ones.** EBU Tech 3341 Table 1 tests **1–5** are pure tones
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

15. **Chunk independence is exact, and it cost the fast primitive.** `vDSP_biquadD` was implemented first
    and rejected on measurement: its output changed in the last two or three significant digits with the
    chunk size it was handed, because how it groups an IIR's work depends on the length of the run. A
    scalar transposed-direct-form-II recurrence has no such grouping. Every other analysis in this package
    is chunk-independent *exactly*, and a loudness figure that moved with the decoder's buffer size would
    be a reproducibility defect at any magnitude — so the slower, exact route is the one that ships, and
    the ~0.1 s it costs is recorded rather than hidden.

16. **`Double` throughout, decided by measurement and not inherited.** `Float` and `Double` filter state
    were both implemented and compared over the published vectors: they differ by at most **1.4 × 10⁻⁵
    LU**, both are chunk-exact, and both cost 0.469 s in the sequential form. `Float` buys nothing
    measurable, so the wider type keeps the headroom for free. This is deliberately *not* the answer
    `TruePeakAccumulator` reached for its own arithmetic, and the difference is that a maximum accumulates
    no error while an IIR and an energy sum both can.

17. **The per-rate derivation is a per-stage prewarped bilinear round-trip, and the numbers behind that
    choice are recorded.** Recover the analogue section each published one is the bilinear transform of,
    prewarped at **that section's own natural frequency** — derived from the section, not chosen — then
    re-discretise at the target rate. Measured against the alternatives (spike Part D): no prewarp gives
    0.0157 dB, one shared frequency gives 0.0521 dB, and a numerical fit gives 0.00736 dB — a **4.6 %**
    improvement bought with two magic numbers that would need re-deriving whenever anything changed. The
    chosen construction gives **0.0077 dB** worst case with a one-line definition. Resampling to 48 kHz
    stays rejected (decision 3), and offline tables are rejected as a second source that can drift from
    the published one: the coefficients are built at construction, in half a microsecond.

18. **48 kHz never goes through the derivation.** The round-trip reproduces the published response to
    0.000000 dB but **not** the coefficients bit for bit — 4.4 × 10⁻¹⁶ on stage 1 — and "the published
    numbers ran" should mean exactly that. So the published rate uses the published table literally, and
    it is the only rate whose weighting identity is `published`.

19. **The response tolerance is 0.02 dB, and it was chosen after measuring rather than before.**
    BS.1770-5 states none. It sits five times inside the publishers' ±0.1 LUFS, under FFmpeg's own 0.03 LU
    drift across the same rates, and leaves a factor of 2.6 over the 0.0077 dB actually produced. It is
    deliberately **not** set at the observed error, which would test nothing but the day it was taken.

20. **Derived rates carry their own weighting identity**, `itu_r_bs1770_5_48k_prototype_rediscretised_v1`.
    It names the **method** rather than the goal, because two different constructions could both claim to
    match a response, and changing the construction requires `v2` on the same rule the algorithm identity
    follows. The algorithm identity is unchanged at every rate: only the filter's provenance moves.

21. **The supported rates are enumerated, not open-ended.** 44.1, 48, 88.2, 96 and 192 kHz, because each
    is a rate the derivation has been measured at. An unmeasured rate is refused rather than derived for,
    since deriving would claim a response nobody checked — and a near miss like 48 001 Hz is refused as
    firmly as an absurd one.

22. **`Double` coefficients, for a measured reason.** Quantising them to `Float` costs 0.0146 dB of
    response error at 192 kHz — three quarters of the whole budget, on top of the derivation's own
    0.0077 — against 0.000025 dB at 48 kHz. All remain stable, so this is accuracy rather than safety,
    and there is no cost to avoiding it.

23. **Loudness is the first consumer of the shared read with no reachable failure of its own**, and the
    composition says so rather than inventing one. Every way it ends without a value is an absence: the
    accumulator declining a stream whose rate has no derived weighting or that carries more than two
    channels, or the standard defining no result for the file. The one path that would be a genuine
    failure — a loudness that came out non-finite — cannot be reached from `PCMChunk`'s finite `Float`s,
    whose squares are bounded ~10²³¹ below `Double`'s ceiling. That is recorded as a limitation, on the
    precedent `SignalLevelMetricsAccumulator` set for its own `nil`, rather than met with a fabricated
    error path.

24. **An unsupported configuration is loudness's absence and nobody else's.** It does not fail the shared
    read, does not touch the other four, and does not resample or guess a layout to avoid the absence.
    The shape already had the precedent — the waveform's own `unavailable` — and this is the second use
    of it, which is what makes it a pattern rather than a special case.

25. **How it is presented, and what leaves on the wire.** Recorded here because both decisions are
    consequences of §12's refusal to turn a measurement into a verdict, and both are hard to reverse once
    a document is published.

    **On screen** it is a section of its own between true peak and the spectrogram — a programme
    measurement whose methodology has to travel with it, and a row has nowhere to put one. One value, one
    decimal (Tech 3341 §2.8's own display precision, and the resolution the ±0.1 agreement supports),
    `LUFS`, explicitly signed, never clamped and never floored. Absence is said in words, and the
    sentence **names no single cause**: the state does not carry one, and the four causes §6 identifies
    are honestly a disjunction. **No standard is named on screen at all** — the methodology is stated in
    plain words, because "BS.1770" beside a number reads as certification whatever the surrounding
    sentence says.

    **The two weighting identities read identically on screen and differ on the wire.** The derivation
    exists to reproduce the published response and rate-invariance is demonstrated, so the provenance
    does not change how a reader interprets the number — while a caption that varied by sample rate would
    suggest the two numbers mean different things. It is an audit fact, and it belongs where a consumer
    can act on it.

    **On the wire** it is `measurements.integratedLoudness`, additive under `schemaVersion` **1**, with
    `value` and `method{algorithm, weighting}`. The key names the **quantity, not the family**: a
    `loudness` object carrying one `method` would imply that method covered momentary, short-term and
    LRA, which §11 deliberately does not ship. `value` is the unrounded `Double` in LUFS — the opposite
    of ADR-0019's linear rule for true peak, for the reason §5 gives, and the difference is again the
    point. Both identities come from the measurement's own record; nothing infers a weighting from a
    sample rate the measurement does not carry. **Absence is the key omitted, never `null`**, and no
    cause of it survives to the document: the wire describes measurements, not why one does not exist.

26. **The published targets are met by the product, not only by the accumulator** — and the distinction
    turned out to cost nothing, which is itself the finding. Every vector measured through a real file,
    `AVFoundationAudioDecoder` and `SharedPCMAnalysisGeneration` agrees with the same vector fed straight
    into the accumulator to **better than 1e-9 LU**. The file round-trip and the shared read are
    transparent, so the accumulator-level intermediates — the derived threshold, the block set, the
    chunk-independence matrix — describe the path a user actually takes.

    Worst deviations from the documents, through production: **0.0213 LU** (Tech 3341 test 5), and
    **0.00028 LU** on both BS.1770-5 anchors, against a published ±0.1.

27. **Agreement with the oracle is a single-rate claim, and the rate sweep says why.** At 48 kHz the two
    implementations run the same published coefficients and agree to **0.0071 LU** across every vector,
    every container and a moving-level programme. Away from it they do not, and the measurement locates
    the movement: FFmpeg's reading drifts **0.030 LU** away from the published −23.0 as the rate rises
    (0.010 at 88.2 kHz, 0.020 at 96, 0.030 at 192), while production's own spread over the same five
    files is **0.0065 LU** and it stays within 0.0122 of the document everywhere.

    This is §3's gap showing up as a number rather than as a caveat: BS.1770-5 publishes coefficients for
    48 kHz alone, so at any other rate two implementations run **two different derivations** and a
    disagreement between them is not evidence that either is wrong. **No cross-rate agreement bound is
    therefore claimed against the oracle.** What is asserted per rate is production against the
    *document*, which it meets.

28. **Container variance is the codec's, and it is separated from the meter's rather than assumed to be.**
    On identical files, every lossless container — WAV, float WAV, AIFF, ALAC, FLAC — agrees to
    **1.4 × 10⁻⁵ LU**, which is 16-bit quantisation and nothing else. AAC moves **6.7 × 10⁻⁴ LU** from the
    float reference: about fifty times the whole lossless spread, which is what identifies it as the
    encoder rather than the measurement, and still more than a hundred times inside the published ±0.1.
    Production agrees with the oracle on all six to **0.0060 LU**, including the lossy one, where the two
    are not even decoding the same samples.

## Deliberately left open

- **The oracle comparison tolerance on real files.** The published compliance tolerance is ±0.1 LUFS and
  the oracle's summary prints one decimal, so a tighter bound requires its three-decimal metadata route.
  A definitive figure waits on an implementation to compare. **Partly discharged**: at 48 kHz the
  measured agreement is 0.0071 LU and the bound asserted is 0.01. Across rates it stays open by decision
  rather than for want of data — see decision 27, which declines to claim such a bound at all.

## Alternatives considered

- **Ship Integrated, Momentary and Short-Term together.** They share the weighting, so the marginal cost
  is small. Rejected: each needs a reduction decision before it means anything in a report, and shipping
  them un-reduced publishes numbers whose meaning has not been decided.
- **Resample non-48 kHz audio to 48 kHz and use the published coefficients.** It would make every file an
  exact-tier claim. Rejected — see decision 3: it measures a converted signal rather than the file.
- **Claim plain "BS.1770 compliance" at all rates.** Simpler to say and what most tools say. Rejected: the
  Recommendation does not publish what would make it true, and this product's claim is that it does not
  overstate.
- **Extend `SignalLevelMetrics` with a loudness field.** Fewer types. Rejected — see decision 10.
- **Store linear energy and convert in the view**, as true peak does. Rejected — see decision 5.
- **Assume channel order (0 = L, 1 = R, …) for surround.** It would let us publish a number for any file.
  Rejected: it is a guess wearing a measurement's clothes, and the LFE case in decision 4 shows the guess
  is wrong in a way that exceeds the standard's own tolerance.
- **A histogram of block loudnesses**, as fast reference implementations use. Rejected — see decision 12.
- **Report −70.0 LUFS for silence**, as the reference implementation does. Rejected — see decision 6.
- **Store a compliance or conformance level on the result** — "BS.1770-5 compliant", "EBU Mode", a tier.
  It would make the two-tier claim of decision 3 legible at a glance. Rejected — see decision 9: a value
  type is not in a position to certify the process that produced it, and the weighting identity already
  records the fact the tier is derived *from*.
- **Carry the block length, hop and gate values as fields on the method**, as this record originally
  predicted. Rejected — see decision 8: they are fixed by the algorithm identity, so fields would only
  add states that contradict it and that the type could not police.
- **Store the sample rate or channel count on the measurement.** Rejected: both describe the file, are
  already reported by the technical properties, and would be a second description this type could not
  keep consistent with the first. The rate's only methodological consequence is which coefficients ran,
  and the weighting identity says that directly.
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
- **The absolute gate is not observable from outside the accumulator.** A negative control confirmed it
  again at the production level: applying the relative gate without the absolute one leaves every
  published reading unchanged, because the relative gate happens to exclude the same blocks by itself.
  Only the derived threshold separates them, and `LoudnessMeasurement` carries no threshold — deliberately,
  since widening it so a test could read one would put a DSP intermediate in a domain value. That evidence
  therefore lives one layer down, in the accumulator's own suite and in the oracle's threshold comparison,
  and group 6 cites it rather than duplicating it.

### Neutral
- No port changes, no domain type changes beyond the new one, no export version change, no new
  dependency, and no second read. The export chain now takes a **third** positional optional, which its
  own note called the moment to introduce a container; that refactor is **recorded debt** rather than
  done here, on the reasoning `SourceInspectionOutcome` applied to its fifth payload.
- The oracle remains absent from CI, so its suite stays local evidence behind the existing
  `FFmpegTool.isAvailable` pattern, with a skip message that says a skip is not agreement.
