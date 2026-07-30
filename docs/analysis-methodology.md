# Analysis Methodology

This document defines **how Audio Inspector reasons** so that its output is honest, reproducible,
and auditable. It is the reference the analysis engines and the UI must follow.

## Evidence / Inference / Conclusion

Every statement the app makes belongs to exactly one of three tiers, and the UI labels them:

- **Evidence** — a directly measured fact with units and methodology. *"Spectral energy drops by
  >60 dB above 16.1 kHz for 92% of the file."*
- **Inference** — reasoning from evidence to a likely cause, with alternatives. *"This is
  consistent with prior lossy compression, but also with a low-pass filter in the master."*
- **Conclusion** — a judgment, always carrying a confidence level. *"Possible transcoding —
  medium confidence."*

We never present an inference or conclusion styled as raw fact, and never a fact dressed up as a
verdict.

## Confidence levels

Discrete, defined, and shown to the user:

| Level | Meaning |
| --- | --- |
| `none` | No notable evidence found for the hypothesis. |
| `weak` | A single soft indicator; easily explained otherwise. |
| `medium` | Multiple consistent indicators; plausible alternatives remain. |
| `strong` | Several independent indicators converge; alternatives are unlikely. |
| `inconclusive` | Evidence is contradictory or insufficient to decide. |

`inconclusive` is a valid, first-class outcome. "I can't tell" beats a confident wrong answer.

## The evidence engine, not a single rule

Source/quality hypotheses (transcoding, upsampling, bit-depth padding, analog source, etc.) are
evaluated by combining **independent indicators**, each with its own measurement, threshold, and
weight. Rules we hold ourselves to:

- **Never** decide transcoding from a fixed frequency cutoff alone. Consider the cutoff's
  **persistence over time**, residual noise above it, band structure, pre-echo/temporal smearing,
  inter-channel differences, behavior during silence, sample rate, and effective bit depth.
- Always attach at least one **alternative explanation** when it exists (master, deliberate
  filtering, analog bandwidth limit, production choices).
- Distinguish container properties from signal properties: container bit depth vs signal bit
  depth vs real dynamic range vs noise floor are four different things and are reported
  separately.

## Reference metric definitions (to be pinned per engine version)

The MVP fixes documented, reproducible definitions and records the engine version alongside each
result. Planned baselines:

- **Sample peak**: max |sample| in dBFS, per channel and overall.
- **True peak**: estimated inter-sample peak via oversampling (≥4×) per ITU-R BS.1770 / EBU
  R128 practice; methodology and oversampling factor recorded.
- **RMS**: windowed RMS in dBFS.
- **LUFS (M / S / I)** and **LRA**: per ITU-R BS.1770 / EBU R128. The exact implementation
  (native vs FFmpeg `ebur128`/`loudnorm`) is an ADR-tracked decision; a single FFmpeg invocation
  is **not** assumed to answer everything, and cross-checks are used where practical.
- **Crest factor**: peak-to-RMS ratio.
- **DC offset**: mean sample value per channel.
- **Clipping**: consecutive full-scale samples (and near-0 dBFS run detection); **inter-sample
  clipping** flagged when true peak exceeds 0 dBFS.
- **Effective bit depth**: highest bit plane carrying real signal (distinguishes 16→24 padding),
  plus LSB usage / dither presence analysis.
- **Significant max frequency**: highest frequency with energy meaningfully above the local noise
  floor, measured over time (not a single global threshold).

Every threshold above is a **named constant tied to the engine version**. Changing one bumps the
version and invalidates cached results (see [architecture.md](architecture.md)).

## Separating the four "qualities"

The app keeps these explicitly distinct and never collapses them into one score:

1. **Format quality** — container/codec (lossless vs lossy, declared specs).
2. **Master quality** — dynamics, loudness, clipping of the mastered signal.
3. **Source quality** — the origin (CD, vinyl, tape, lossy file, degraded master).
4. **Capture/rip quality** — how well the source was digitized (noise, speed, offsets, clipping).
5. **Post-processing** — normalization, de-noising, de-clipping, trimming applied afterward.

A file can be excellent format + poor master, or great capture + mediocre source, and the report
must make that legible.

## Reporting contract

Each analysis produces two coordinated views:

- **Plain summary**: what was found, whether it warrants review, what seems reliable, what seems
  suspicious, which copy to keep (if comparing), and **what cannot be known**.
- **Technical view**: metrics, plots, methodology, thresholds, confidence, observations, raw data,
  and the analysis engine version.

## Reproducibility

Given the same input bytes and the same engine version, results must be deterministic. Randomized
or platform-dependent steps (if any) are seeded and documented. Numerical comparisons in tests use
explicit tolerances.
