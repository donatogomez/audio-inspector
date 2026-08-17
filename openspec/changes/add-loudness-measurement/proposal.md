## Why

Audio Inspector measures sample peak, RMS, DC offset, clipped samples and true peak, and can say
nothing about **loudness** — the one measurement the audience actually compares masters by. RMS is not
loudness: it weights 40 Hz and 4 kHz identically, and the ear does not.

ADR-0006 already decided the methodology (ITU-R BS.1770 / EBU R128, implemented natively in
`AudioInspectorAnalysis`, cross-checked against FFmpeg `ebur128`) and left the constants to be pinned by
this change. The read is already shared, so the measurement costs no extra decode: measured on ten
minutes of stereo, the whole fold is **≈0.14 s**, about half what the waveform's costs.

## What Changes

- **Integrated loudness (LUFS-I) only**, as a new capability `audio-loudness-measurement`. It is the one
  loudness quantity with an unambiguous value in a *static report*; momentary and short-term are meter
  readings that would have to be reduced to a maximum or a series before they mean anything on a page,
  and that reduction is a product decision this change does not make.
- **A fifth consumer of the shared PCM read**, exactly as true peak and the waveform became the third
  and fourth: one accumulator, one outcome, no extra decode, no new abstraction.
- **The measurement carries its methodology**, as `TruePeakMeasurement` already does — gate values,
  block length, and the weighting's identity — because a loudness figure without its method is not
  reproducible.
- **Compliance is claimed only where it can be demonstrated.** For **mono and stereo** the channel
  weighting is fully determined by the channel count, and that was measured. Beyond stereo the pipeline
  does not know which channel is which, so no value is published rather than a wrong one.
- **Silence and "too short to measure" stay distinct**, and neither is reported as the reference's −70
  floor: a file shorter than one block produced no measurement at all.

## Impact

- New capability: `audio-loudness-measurement`. `audio-signal-level-metrics` is **not** modified — a
  frequency-weighted, gated, time-blocked quantity does not belong beside direct sample-domain facts.
- Affected code: a new accumulator in `AudioInspectorAnalysis`, a new domain value type, one field on
  `SharedPCMAnalysisOutcome` and its composition, one presentation row, one export field.
  `AudioDecoding`, `PCMChunk` and every existing analysis are untouched.
- **`schemaVersion` stays 1**: the field is additive and absent when not measured.
- **A new ADR is required.** ADR-0006 chose the standard; it did not decide how far compliance may be
  claimed, what happens beyond stereo, whether the domain stores LUFS or linear energy, or what silence
  reports. Those are durable decisions.
- **Explicitly out of scope**: momentary, short-term, LRA, any timeline, loudness *findings*, platform
  targets, normalisation advice, and real-time metering.
