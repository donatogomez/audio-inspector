# ADR-0022: Integrated loudness — how far compliance is claimed, and what the domain stores

- **Status**: **Proposed.** It stays Proposed until the normative constants are obtained from the
  standard (change `add-loudness-measurement`, group 1) and the implementation reproduces the spike's
  measured acceptance targets — the K-weighting response, the calibration anchor, the gating fixture and
  rate-invariance — each by a test that fails when the property is broken. Partial evidence does not
  promote it.
- **Date**: 2026-08-18
- **Deciders**: Project maintainer
- **Related**: **ADR-0006** (which chose the standard and the oracle and left the constants to this
  change; *referenced, not edited*), ADR-0009, ADR-0019, ADR-0020, ADR-0021,
  `docs/spikes/2026-08-18-loudness-measurement-validation.md`, change `add-loudness-measurement`

## Context

ADR-0006 decided that loudness follows ITU-R BS.1770 / EBU R128, is implemented natively in
`AudioInspectorAnalysis`, is cross-checked against FFmpeg `ebur128`, and pins every constant to the
analysis engine version. All of that stands.

It did not decide four things that turn out to matter more than the algorithm:

1. **how far compliance may be claimed**, given that the pipeline does not know channel layout;
2. **what the domain stores** — LUFS, or linear energy converted at the surface;
3. **which of the four loudness quantities ships first**;
4. **what a silent or too-short file reports**.

The spike answered the first three with measurement. The fourth is deliberately left open here.

## Decision

1. **Integrated loudness ships alone.** It is the only one of the four whose value is unambiguous in a
   static report. Momentary and short-term are meter readings: "Momentary: −14.2 LUFS" is meaningless
   without saying *when*, and choosing the reduction — maximum, last, a timeline — is a product decision
   this record does not make. They are cheap to compute; that is not the reason to ship them. LRA depends
   on short-term and therefore cannot precede it.

2. **Compliance is claimed for mono and stereo, and for nothing else.** Measured: a stereo pair of
   identical channels reads exactly **3.01 dB = 10·log₁₀2** above the same signal in mono, so both
   channels carry equal weight and their energies sum — for one and two channels the weighting follows
   from the channel *count* alone. Beyond that the standard weights channels by position, and
   `PCMStreamDescription` carries no layout; the property reader takes `channelCount` from the ASBD and
   deliberately never infers position from layouts or labels.

   **So for other configurations no value is published.** An absence, not a failure, and not a number
   computed from a guessed layout. Reading `AVAudioChannelLayout` to extend this is a separate change:
   it touches the property reader, the domain and the boundary rules.

3. **The domain stores LUFS.** True peak stores linear because dBTP is a *presentation* of a linear peak;
   here the normative quantity **is** the logarithmic one. Storing linear energy and converting at the
   surface would invent a unit the standard does not use and would move the conversion offset into a
   layer that cannot be checked against the oracle. This is deliberately **not** the rule ADR-0019 set for
   true peak, and the difference is the point.

4. **The measurement carries its methodology**, as `TruePeakMeasurement` does (ADR-0019): the weighting's
   identity, the gate values and the block length travel with the value. A loudness figure without its
   method is not reproducible, and this project's constants are tied to an engine version precisely so
   that a change of method is visible.

5. **It is a sibling type, not an extension of `SignalLevelMetrics`.** Those are direct sample-domain
   facts, per channel, unweighted and untimed. Loudness is frequency-weighted, gated, time-blocked and
   whole-file — there is no per-channel loudness, because the channels are combined before the quantity
   exists. One type holding both would invite exactly the confusion this product exists to avoid.

6. **It is a consumer of the existing shared read**, the fifth, at the price the fourth paid: one field,
   one accumulator, one line in each composition method. **No second read**, no new abstraction. Measured
   cost of the fold: **≈0.14 s** on ten minutes of stereo — roughly half the waveform's, and 7–12 % of the
   pass it joins.

7. **No verdict, ever.** The report states the measurement. Not "too loud", not "too quiet", not "ready"
   for any platform, no platform target named, no normalisation advice, no comparison against −14 or −23.
   Loudness is the metric most likely to invite a judgement, which is why the prohibition is written into
   the record rather than left to taste. Loudness *findings* are a different capability and are out of
   scope.

8. **The constants come from the standard, not from memory.** No coefficient, gate value or block length
   is recorded here, because neither BS.1770 nor R128 was read when this was written. What is recorded
   instead is the **acceptance target** the constants must reproduce, measured from the reference
   implementation: the K-weighting response curve, a 1 kHz calibration anchor, a gating fixture, and
   rate-invariance across 44.1–192 kHz. An implementation that hits those is right; one built on
   half-remembered numbers is unverifiable.

## Deliberately left open

**What digital silence reports.** The reference returns **−70.0 LUFS** for five seconds of silence *and*
for a 300 ms file — the same value for two different situations. The too-short case is settled: nothing
was measured, so it is *not computable*. Silence is not: either every block was gated out and the gated
mean is undefined, or it is a real measurement stated as below the measurable floor. The answer depends
on what the absolute gate *means*, which requires the standard text. **It must not default to publishing
−70.0 as though it measured the file.**

## Alternatives considered

- **Ship Integrated, Momentary and Short-Term together.** They share the weighting, so the marginal cost
  is small. Rejected: each needs a reduction decision before it means anything in a report, and shipping
  them un-reduced publishes numbers whose meaning has not been decided.
- **Extend `SignalLevelMetrics` with a loudness field.** Fewer types. Rejected — see decision 5.
- **Store linear energy and convert in the view**, as true peak does. Rejected — see decision 3.
- **Assume channel order (0 = L, 1 = R, …) for surround.** It would let us publish a number for any file.
  Rejected: it is a guess wearing a measurement's clothes, and this product's whole claim is that it does
  not do that.
- **Shell out to FFmpeg for the shipped value.** Accurate and free. Rejected by ADR-0006 and unchanged;
  it remains the oracle.

## Consequences

### Positive
- The measurement most users compare masters by, produced from a read that already happens.
- The compliance claim matches what can actually be demonstrated, per configuration.
- The unit decision keeps the conversion offset where it can be tested.

### Negative / costs
- **Surround and multichannel files get no loudness figure at all** until a separate change teaches the
  pipeline about layout. For those users the feature is simply absent, and that will look like a gap.
- **Momentary, short-term and LRA are absent**, which some will read as an unfinished loudness suite.
  Accepted deliberately: a meter reading without a stated reduction is not a report.
- The correctness burden is high and front-loaded: the constants must be sourced, and the acceptance
  targets are tight.

### Neutral
- No port changes, no domain type changes beyond the new one, no export version change, no new
  dependency, and no second read.
