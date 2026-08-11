# ADR-0019: True peak as a self-describing measurement, reported as a value rather than a flag

- **Status**: **Proposed.** The tolerance its promotion conditions referred to is now pinned by
  measurement — **0.05 dB** against FFmpeg `ebur128` for signals smooth at their boundaries up to
  96 kHz, 0.0042 dB against analytic truth
  (`docs/spikes/2026-08-11-true-peak-methodology-validation.md`). It stays Proposed until that agreement
  is demonstrated **against production code** rather than a spike, and the resulting surface passes
  manual validation on a file whose true peak genuinely exceeds its sample peak. Partial evidence does
  not promote it.
- **Date**: 2026-08-11
- **Deciders**: Project maintainer
- **Related**: **ADR-0006** (loudness/true-peak methodology — this ADR *applies and narrows* it;
  *referenced, never edited*), ADR-0003 (FFmpeg as a dev/test oracle, never shipped), ADR-0004
  (persistence, Phase 2), ADR-0008 (certainty model), ADR-0009 (domain report vs JSON contract),
  ADR-0016 (shared PCM seam, independent operations), ADR-0018 (where a computed property may live),
  `docs/analysis-methodology.md`, change `add-true-peak-measurement`

## Context

ADR-0006 fixed the *methodology* for true peak before any of it existed: ITU-R BS.1770 / EBU R128,
oversampling ≥ 4× before peak detection, the factor and filter **recorded with the result**,
implemented in `AudioInspectorAnalysis` with Accelerate, cross-checked against FFmpeg `ebur128`, every
constant named and tied to the analysis engine version. Implementing it surfaces questions that record
does not answer, and they are structural rather than numeric — which is why they are here and not in the
change's own `design.md`, where the pinned constants belong (ADR-0006's own Follow-ups place them there).
Two were visible before any measurement; the third only became visible once the methodology was actually
measured.

**First: nothing in this project records how a value was produced.** Every value type so far —
`TechnicalProperties`, `WaveformEnvelope`, `Spectrogram`, `SignalLevelMetrics` — carries the measurement
and nothing about the method, because for each of them the method was either trivial (a maximum, a mean)
or fixed once for the whole type (the spectrogram's FFT size lives in the accumulator, not in the
model). True peak is the first metric whose *number is not interpretable without its method*: the same
file measured at 4× and at 8×, or with two different interpolation filters, produces two legitimately
different values. ADR-0006 requires the method to travel with the result; it does not say where it
lives, and once it is exported it becomes a wire commitment.

**Second: ADR-0006 says the positive case is flagged.** Its exact sentence is *"Inter-sample clipping is
flagged when true peak > 0 dBFS."* This project's own analysis rules say something narrower:
`docs/analysis-methodology.md` separates evidence from inference from conclusion, requires alternative
explanations, and attaches a confidence level to anything that is not a direct measurement — and
ADR-0016 §17 already deferred an equivalent interpretive step (automatic lossy-origin detection) to a
capability that can carry that structure. "Inter-sample clipping" is an inference: whether a
reconstruction exceeding full scale actually distorts depends on the converter, encoder or player in a
given chain, not on the file alone. Shipping it as a flag beside a bare number would be the shape this
project has refused everywhere else.

**Third, and only visible after the measurements** (`docs/spikes/2026-08-11-true-peak-methodology-validation.md`):
BS.1770's own Annex 2 filter coefficients were not available, so the shipped filter is one *designed* to
recorded parameters and validated against analytic truth and an independent R128 implementation. That is
a real, permanent constraint on **what the product may claim**, and a constraint on claims is exactly
what an ADR is for.

## Decision

1. **A true peak carries its own methodology.** The oversampling factor and the interpolation filter are
   part of the measurement's value type, travel with it into the interface and into the
   `schemaVersion` 1 export, and are named constants tied to the analysis engine version — never
   user-configurable, since a measurement a user could retune would make the same file produce different
   results across runs.

2. **The methodology descriptor belongs to the measurement, not to the envelope.** It sits inside the
   true-peak value (and inside `measurements.truePeak` on the wire), not hoisted to a report-wide or
   export-wide location. It describes this measurement; hoisting it would imply it covers measurements
   that have no such method. If a second measurement ever shares it, hoisting is that change's decision,
   made with two real cases in hand.

3. **True peak is a sibling value type, never a field of `SignalLevelMetrics`.** That type is defined by
   its own documentation as sample-level facts — direct reductions over stored samples. True peak is an
   estimate of a *reconstruction*, produced by a different method and carrying metadata the type has
   nowhere to put. This applies ADR-0018 §2's existing rule ("its own domain value type… a peer, never a
   member") to a case that record was not written for, without changing it.

4. **A positive true peak is reported as a value, not raised as a flag.** In this slice the app states
   the measured number, its unit and its method, at the same visual weight whatever it contains. It
   emits no inspection warning, does not change the global inspection status, and is never described as
   clipping, distortion, or a quality of the file or its master. **This narrows ADR-0006's "flagged"
   sentence rather than contradicting it**: the flag is an inference and therefore belongs to the
   schema's still-unused `findings` object, where evidence, alternative explanations and a confidence
   level can accompany it — a capability of its own, named and deferred, not dropped.

5. **The unit is written dBTP in the interface.** ADR-0006 and FFmpeg both write "dBFS" for this value.
   dBTP is EBU R128 / Tech 3341 notation and states that the number came from the reconstructed
   inter-sample waveform rather than from the stored samples — which matters exactly because the sample
   peak, in dBFS, sits next to it on screen. The stored and exported value stays linear; dBTP exists
   only at the presentation edge.

6. **What may be claimed is bounded by what was validated.** The interpolation filter is a **designed**
   polyphase windowed-sinc whose parameters are recorded, **not** the coefficient table of ITU-R
   BS.1770 Annex 2 — that text was not available when the methodology was measured, and remembered
   numbers would be fabricated evidence. So the app, its documentation and its export may state that
   true peak is measured *following BS.1770 / R128 practice*, with a stated factor and filter, agreeing
   with an independent R128 implementation to a measured tolerance. **They may not state or imply
   conformance to the standard's own filter, nor quote a conformance tolerance from it.** If the annex
   table later becomes available, comparing against it is a bounded follow-up; until then the weaker,
   true claim is the only one permitted.

7. **No analysis-engine-version field is introduced.** ADR-0006 ties that to *stored* results, there is
   no result store yet (ADR-0004, Phase 2), and `docs/json-schema-v1.md` states the contract has no such
   field. A version field would have to cover every measurement and the export envelope, which makes it
   the store's or the schema's decision. Recorded here so its absence is a decision rather than an
   oversight.

## Alternatives considered

- **Add `truePeak` to `SignalLevelMetrics`.** One type, one section, one export object, no new wiring.
  Rejected: it puts a reconstruction inside a type whose first line defines it as sample-level facts,
  gives four metrics a methodology descriptor none of them has, and forces every existing fixture,
  assertion and export test to change for a value they do not measure.
- **Keep the methodology out of the model and document it only in code comments and the spec.** Simpler
  model, smaller wire object. Rejected: it makes the exported number uninterpretable — two files
  measured under different engine versions would export identical-looking values with no way to tell
  them apart — and it fails ADR-0006 §3 literally, which requires the factor and filter to be recorded
  *with the result*.
- **Hoist the methodology to a report-wide or export-wide "analysis" object now.** Tidier if several
  measurements eventually carry methods. Rejected as premature: exactly one measurement has one, and a
  shared location invented for a single case would have to be reshaped by the second, at which point it
  is already a wire commitment.
- **Ship the inter-sample-clipping flag now, as ADR-0006's sentence reads.** Faithful to the letter of
  that record and useful to a mastering engineer. Rejected for this slice: it is an inference presented
  as a fact, without the alternatives or the confidence level this project requires of inferences, and
  the flag's real home (`findings`) does not exist yet. Deferring it keeps ADR-0006's intent available
  and refuses only its premature form.
- **Use `AVAudioConverter` to oversample.** Native, brief, and it would work. Rejected on methodology,
  not on performance: its filter is unpublished and may change between OS releases, so it cannot be
  recorded as ADR-0006 requires and cannot promise the same file measures the same way after a system
  update. It would also place the measurement in `AudioInspectorMedia`, the module that owns file
  access rather than DSP.
- **Write dBFS for true peak, matching ADR-0006's own wording and FFmpeg's option text.** Consistent
  with the two references most likely to be consulted. Rejected: the sample peak, genuinely in dBFS,
  appears directly beside it, and two numbers sharing a unit while differing in method is precisely the
  confusion this metric exists to remove.

## Consequences

### Positive

- An exported true peak is interpretable on its own terms: a reader can tell which factor and filter
  produced it, and two engine versions cannot silently masquerade as one.
- `SignalLevelMetrics` keeps meaning exactly what it says it means, and none of its shipped tests,
  fixtures or wire fields move.
- The honesty rules hold at the one place they were most likely to bend: the app measures something
  alarming-sounding and still declines to characterise it.
- Establishes the shape for every later methodology-bearing metric (LUFS, LRA, significant max
  frequency) without committing to a shared container before there is a second case.

### Negative / costs

- **A reader wanting "the peak" now has two numbers** — sample peak in dBFS, true peak in dBTP — and
  must understand the difference to use either. Accepted deliberately: collapsing them into one would
  hide the very phenomenon this metric measures, and the interface states the method beside each.
- **The export grows a `method` object whose shape is a wire commitment** before any second measurement
  exists to validate the shape against. Mitigated by keeping it inside `truePeak` rather than hoisted,
  so a later measurement can differ without renegotiating this one.
- **Deferring the flag will read as an unfinished feature** to a user who knows R128 and expects a
  red "over" indicator. The same trade ADR-0016 accepted for the spectrogram: showing and concluding
  are different jobs.
- **Divergence in wording from ADR-0006** (dBTP vs dBFS, value vs flag) is a cost in itself — anyone
  reading the two records in isolation could believe they conflict. Which is exactly why the divergence
  is written down here instead of appearing only in code.

### Neutral

- Introduces no new mechanism in the architecture: the port, the module boundaries, the independent-
  operation shape and the certainty conventions are all existing decisions, applied to a new value.
- Leaves ADR-0006 fully in force for LUFS, LRA and the rest of the loudness suite; nothing here narrows
  anything beyond this one metric's presentation.

## Follow-ups

- **Promotion criteria** (see Status): oracle agreement within a measured tolerance against production
  code, plus manual validation of the surface. Until then this ADR asserts a direction, not a proven
  result.
- **The pinned constants** — the filter, the factor, edge handling, arithmetic width and the
  cross-check tolerance — were settled by `add-true-peak-measurement`'s own spike, per ADR-0006's own
  Follow-up placing them in the implementing change. They live in that change's `design.md` §4 and in
  the spike report, deliberately **not** here: this record holds the decisions that outlive a constant,
  and a constant that moves should not need a new ADR to move it.
- **Comparing against BS.1770 Annex 2's own coefficients**, if the standard's text becomes available, is
  a bounded follow-up under decision 6 — a validation, not a redesign.
- **An inter-sample-clipping finding** — with evidence, alternative explanations and a confidence level,
  under the schema's `findings` object — is a future capability. Nothing in this ADR authorises a
  verdict without that structure.
- **An analysis-engine-version field** becomes due when results are stored (ADR-0004) or when the
  schema gains an envelope for it, whichever comes first.
