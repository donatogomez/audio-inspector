## Why

Audio Inspector measures sample peak, RMS, DC offset, clipped samples and true peak, and can say
nothing about **loudness** — the one measurement the audience actually compares masters by. RMS is not
loudness: it weights 40 Hz and 4 kHz identically, and the ear does not.

ADR-0006 already decided the methodology (ITU-R BS.1770 / EBU R128, implemented natively in
`AudioInspectorAnalysis`, cross-checked against FFmpeg `ebur128`) and left the constants to be pinned by
this change. **They are now pinned**: ITU-R BS.1770-5 (11/2023), EBU R 128 v5.0, EBU Tech 3341 v4,
EBU Tech 3342 v4 and Report ITU-R BS.2217-2 were obtained and read, and every constant is sourced to a
document, a revision and a section in `docs/spikes/2026-08-18-loudness-measurement-validation.md`.

The read is already shared, so the measurement costs no extra decode: measured on ten minutes of stereo,
the whole fold is **≈0.14 s**, about half what the waveform's costs.

## What Changes

- **Integrated loudness (LUFS-I) only**, as a new capability `audio-loudness-measurement`. It is the one
  loudness quantity with an unambiguous value in a *static report*; momentary and short-term are meter
  readings that would have to be reduced to a maximum or a series before they mean anything on a page,
  and that reduction is a product decision this change does not make. LRA additionally uses a **different
  relative gate** (−20 LU against integrated loudness's −10 LU), a constant best kept out of this change.
- **A fifth consumer of the shared PCM read**, exactly as true peak and the waveform became the third
  and fourth: one accumulator, one outcome, no extra decode, no new abstraction.
- **The measurement carries its methodology**, as `TruePeakMeasurement` already does — and more of it than
  true peak needs, because the compliance claim is not the same at every sample rate (below).
- **Compliance is claimed in two tiers, and both are stated honestly.** BS.1770-5 publishes filter
  coefficients **for 48 kHz only** and requires other rates merely to *match that frequency response*,
  publishing no prototype, no per-rate table and no transform. So the claim is **exact at 48 kHz** and a
  **demonstrated equivalence** elsewhere, against a derivation this project chooses and records.
- **Compliance is claimed only where the channel weighting can be determined.** For **mono and stereo**
  it follows from the channel count. Beyond that the standard weights channels by **position**, and a
  three-channel file could carry an **LFE that the standard excludes entirely** — so no value is
  published rather than a wrong one.
- **Silence and "too short to measure" both report no value**, and neither reports the reference's −70
  floor: −70 LUFS is the standard's absolute *gate*, never a result. The boundary is exact — 400 ms
  measures, 399 ms does not.
- **The acceptance targets are published, not observed.** EBU Tech 3341's compliance tests 1–5 and its
  §2.9 calibration signal are synthesisable from their descriptions and carry published expected values
  at **±0.1 LUFS**; the spike's own measured fixtures are demoted to corroboration.

## Impact

- New capability: `audio-loudness-measurement`. `audio-signal-level-metrics` is **not** modified — a
  frequency-weighted, gated, time-blocked quantity does not belong beside direct sample-domain facts.
- Affected code: a new accumulator in `AudioInspectorAnalysis`, a new domain value type, one field on
  `SharedPCMAnalysisOutcome` and its composition, one presentation row, one export field.
  `AudioDecoding`, `PCMChunk` and every existing analysis are untouched.
- **`schemaVersion` stays 1**: the field is additive and absent when not measured.
- **A new ADR is required.** ADR-0006 chose the standard; it did not decide how far compliance may be
  claimed, what happens beyond stereo **or beyond 48 kHz**, whether the domain stores LUFS or linear
  energy, or what silence reports. Those are durable decisions and live in ADR-0022.
- FFmpeg stays a **local, qualified oracle** — it passes EBU Tech 3341 tests 1–5 within the published
  tolerance — and is **absent from CI**, so its suite remains skippable local evidence.
- **Explicitly out of scope**: momentary, short-term, LRA, any timeline, loudness *findings*, platform
  targets, normalisation advice, real-time metering, and any channel configuration beyond stereo.
