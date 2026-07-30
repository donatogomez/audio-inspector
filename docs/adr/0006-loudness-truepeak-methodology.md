# ADR-0006: Loudness and true-peak methodology

- **Status**: Accepted (approach); constants pinned per engine version during implementation
- **Date**: 2026-07-30
- **Deciders**: Project maintainer
- **Related**: ADR-0003, docs/analysis-methodology.md

## Context

Loudness (LUFS M/S/I, LRA) and true peak must be **documented, reproducible, and versioned**. The
brief warns that a single FFmpeg invocation must not be assumed to answer everything, and that no
metric should be presented as a single universal truth.

## Decision

- Follow **ITU-R BS.1770 / EBU R128** definitions for LUFS (momentary/short-term/integrated),
  Loudness Range, and true peak.
- **True peak** is estimated by oversampling (≥4×) before peak detection; the oversampling factor
  and filter are recorded with the result. Inter-sample clipping is flagged when true peak > 0
  dBFS.
- Implement these in `AudioInspectorAnalysis` using Accelerate/vDSP, and **cross-check against
  FFmpeg `ebur128`/`loudnorm`** during development and in tests (FFmpeg as a reference oracle, per
  ADR-0003) with explicit numeric tolerances.
- Every threshold/constant (gating, oversampling factor, window sizes, silence thresholds) is a
  **named constant tied to the analysis engine version**. Changing any bumps the version and
  invalidates cached results.
- Where multiple dynamic-range metrics exist, present them side by side and explain differences —
  never a single "dynamic range" truth.

## Alternatives considered

- **Shell out to FFmpeg `loudnorm`/`ebur128` for the shipped values.** Simple and accurate, but
  ties shipped correctness to bundling FFmpeg (ADR-0003) and yields less control over methodology
  and versioning. Rejected for shipping; embraced as the test/reference oracle.
- **Ad-hoc RMS-based "loudness."** Not standards-based, not comparable to R128 tooling. Rejected.

## Consequences

### Positive
- Standards-based, reproducible, versioned, independently verifiable against FFmpeg; no shipping
  dependency on FFmpeg for correctness.

### Negative / costs
- More implementation effort than shelling out; requires a careful, tested vDSP implementation and a
  fixture/tolerance strategy.

### Neutral
- Establishes the "named constants tied to engine version" pattern reused by all later metrics.

## Follow-ups

Pin the exact constants and tolerances in the loudness OpenSpec change (Phase 3); record the engine
version alongside every stored result.
