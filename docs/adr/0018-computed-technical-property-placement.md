# ADR-0018: Where a computed technical property may live

- **Status**: Accepted (2026-08-11) — both promotion conditions are met: `averageFileBitrate` is
  implemented and exported against production code, and this change's own manual validation is done —
  a person confirmed the real on-screen `Signal levels` surface and the real exported
  `measurements.signalLevels` JSON, on a build whose process identity was verified rather than assumed,
  reproducibly, twice. See `docs/manual-validation-mvp.md`, "Signal level metrics — resolved: a stale
  app instance, not a code defect."
- **Date**: 2026-08-08
- **Deciders**: Project maintainer
- **Related**: ADR-0006 (loudness/true-peak methodology), ADR-0008 (property availability and certainty),
  ADR-0009 (domain report vs JSON contract), ADR-0012 (audio property extraction strategy), change
  `add-computed-technical-properties`

## Context

An audit of the technical-property model found two additions worth making — a bitrate calculated from
file size and duration, and a set of sample-level signal metrics (peak, RMS, DC offset, clipped-sample
count) — and both raise the same underlying question before either is implemented: **where does a
computed value live, relative to `TechnicalProperties`, and how is it kept from being confused with a
value the file itself declares?**

`TechnicalProperties.swift` already states a boundary in its own first line: *"Basic, metadata-level
technical properties of an audio file — **no DSP**."* That line predates this ADR and is not being
revisited; the question is what follows from taking it literally now that a real DSP-derived candidate
exists. Separately, `estimatedBitrate` already carries one computed/estimated value; adding a second,
independently-derived one (from size and duration rather than from the framework's own track estimate)
raises the same question ADR-0012's discrepancy policy already answers for disagreeing *declared*
sources, but for two *estimates* instead.

## Decision

1. **A property computed from metadata already read (no sample access) may join `TechnicalProperties`
   as a new field**, provided it follows the same certainty discipline as every existing field
   (ADR-0008): a calculated value is never `.available`, because a calculation over incomplete inputs
   (here, whole-file size standing in for audio-payload size) can never be presented as measured fact.
   `averageFileBitrate` is this case.

2. **A property that requires decoding sample data may never join `TechnicalProperties`.** It is
   modelled as its own domain value type, living beside the inspection report exactly as `WaveformEnvelope`
   and `Spectrogram` already do — a peer, never a member. This is not a new pattern; it is the existing
   one, applied to a new kind of value.

3. **Two independently-derived estimates of the same underlying fact are never merged into one field.**
   When `estimatedBitrate` (the framework's own track estimate) and `averageFileBitrate`
   (size ÷ duration) exist for the same file, both are reported, separately, each labelled by its own
   method. Neither is presented as more authoritative than the other by default; a future discrepancy
   policy, if one is needed, is a decision for whoever observes real files where they diverge
   meaningfully; this ADR does not pre-empt it.

4. **A DSP-derived metric that requires a threshold to mean anything (a clipping level, a noise-floor
   cutoff for a frequency-extent metric) carries that threshold as a named constant tied to the analysis
   engine version**, per the pattern ADR-0006 already established for loudness. This is confirmed as the
   general rule, not a one-off borrowed from that ADR.

## Alternatives considered

- **Add every new property to `TechnicalProperties`, DSP or not, for a single flat property surface.**
  Simpler for a consumer to enumerate, but breaks the boundary that keeps `AudioInspectorDomain`
  framework-free and metadata-only, and makes it impossible to tell, from the type alone, whether
  producing a value ever requires decoding the file. Rejected.
- **Reconcile `estimatedBitrate` and `averageFileBitrate` into one field, preferring whichever is
  "more reliable."** No general rule decides that correctly across formats — the framework's estimate is
  more trustworthy for a lossy file with embedded artwork; the calculated one is the only one that exists
  at all for PCM. Blending or silently preferring one repeats the mistake ADR-0012 already rejected for
  disagreeing declared sources. Rejected.
- **Give the new sample-level metrics their own port, separate from `AudioDecoding`.** Unnecessary: the
  existing port already serves two independent consumers (waveform, spectrogram) under ADR-0016's
  "separate operations" rule, and a third consumer is additive, not a reason to change the port's shape.
  Not decided here either way — left to the implementing change under ADR-0016's own precedent.

## Consequences

### Positive

- Keeps `TechnicalProperties`'s existing "no DSP" boundary meaningful rather than eroding it one
  convenient field at a time.
- Two disagreeing bitrate estimates are visible to a reader as two facts, not silently resolved into one
  that hides which method produced it — consistent with this project's refusal of single aggregate
  truths.

### Negative / costs

- A consumer wanting "the file's bitrate" now has three fields to read and reconcile itself
  (`declaredBitrate`, `estimatedBitrate`, `averageFileBitrate`) rather than one. This is treated as
  an acceptable cost: reconciling them silently would be exactly the fabricated precision ADR-0012
  already rejected.
- Sample-level metrics living outside `TechnicalProperties` means a consumer wanting "everything about
  the file" must read two value types instead of one, mirroring the existing cost of reading the report,
  the waveform and the spectrogram separately today.

### Neutral

- Establishes no new mechanism — it applies the `Property<Value>` certainty model (ADR-0008) and the
  "peer value type beside the report" shape (already used for `WaveformEnvelope`/`Spectrogram`) to a case
  neither was written for, without changing either.

## Follow-ups

- The exact clipping threshold, its engine-version tie, and whether the new accumulator needs Accelerate
  or can stay pure Swift are implementation decisions for `add-computed-technical-properties`'s own
  tasks, not fixed here.
- If a future file is observed where `estimatedBitrate` and `averageFileBitrate` disagree
  meaningfully, deciding whether that disagreement itself becomes a reported observation (rather than two
  silent numbers) is a decision for that moment, made with a real example in hand rather than
  speculatively here.
- ~~Promote this ADR once `add-computed-technical-properties` has implemented at least
  `averageFileBitrate` against production code and its own manual validation is done, following the
  same promotion discipline ADR-0017 already uses.~~ **Done — see Status above.**
