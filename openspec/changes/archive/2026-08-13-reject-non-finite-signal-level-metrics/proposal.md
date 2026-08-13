# Reject non-finite signal level results

## Why

`SignalLevelMetrics` could publish `rms == +infinity` and `dcOffset == NaN` as if they were
measurements, from a file whose every sample was finite. The values reached the presentation layer and
the exported document; only `JSONEncoder`'s own refusal of non-conforming floats stopped the export,
and it stopped it as an encoding failure with no explanation rather than as the impossible measurement
it was.

**The input was valid.** `PCMChunk` refuses `NaN` and infinity at the boundary but deliberately keeps
finite samples of any magnitude, because a file may genuinely carry a sample beyond full scale and this
project reports that rather than clamping it. The defect appeared *after* the boundary, during
accumulation.

**The cause was an implementation detail, not the mathematics.** `vDSP_sve`/`vDSP_svesq` form each
chunk's partial sum in `Float32`, and only the result was widened to the `Double` running total, so the
sum of squares went non-finite from about `1e18` and the plain sum from about `1e37` — with alternating
signs producing a `NaN`. It was also **chunk-dependent**: the same file measured one frame at a time
stayed finite where 4 096 frames at a time did not, which contradicts this capability's own
independence guarantee.

The answer always fits: `|mean| ≤ max|x|` and `RMS = sqrt(mean(x²)) ≤ max|x|`, so a finite `Float`
input has a finite `Float` result. The overflow was purely intermediate.

## What Changes

- **The reduction widens before it reduces.** Each chunk is converted to `Double` and reduced there, so
  no intermediate can overflow — the largest `Float` squared is ~1.16e77, and 2⁵³ of those sum to ~1e93
  against `Double`'s ~1.8e308 ceiling. The measurement is **preserved exactly**; nothing is clamped,
  substituted or invented.
- **The domain model refuses what cannot describe a measurement**, as `TruePeakMeasurement.Channel` and
  `WaveformBucket` already did: non-finite values, a negative maximum-of-magnitudes, a negative RMS, an
  empty channel list, and the `nil`-iff-no-samples rule it documented but never enforced. Values beyond
  full scale stay accepted — that is a real fact about a file.
- **An impossible result propagates as the existing `failed` outcome**, through an optional `finish()`
  like its two sibling accumulators, rather than as a new state or a fabricated number. With the
  reduction fixed this is a backstop the arithmetic cannot reach.

## Impact

- Affected specs: `audio-signal-level-metrics` (one requirement modified — the finiteness guarantee is
  written down rather than left implicit in "a direct mathematical fact").
- Affected code: `SignalLevelMetrics`, `SignalLevelMetricsAccumulator`, and the two call sites that
  consume `finish()`. No new capability, no new metric, no wire-format change, no UI change, and
  `schemaVersion` stays 1.
- **No ADR.** This introduces no durable architectural decision: it applies the failable-value-object
  pattern this project already uses in two sibling types, and the constant-versioning and
  no-judgement rules are untouched.
