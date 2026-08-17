# Design — integrated loudness as a fifth consumer

Evidence in `docs/spikes/2026-08-18-loudness-measurement-validation.md`. Everything below either cites a
measurement from it or is marked **UNRESOLVED**.

## 1. The blocking unknown, stated first

**The normative constants are not in this repo and were not read.** No coefficients, gate values, block
length or overlap appear in this design as normative facts, and none may be written from memory into the
implementation. Task 1 is to obtain them from the standard text.

What the spike supplies instead is an **acceptance target** the constants must reproduce — a measured
K-weighting response curve, a calibration point, a gating fixture and rate-invariance — plus the oracle.
An implementation that hits those is right; one that merely compiles is not.

## 2. The four metrics, and why only one ships

| | what it is | window | needs whole file | value in a static report |
| --- | --- | --- | --- | --- |
| **Integrated (LUFS-I)** | gated mean loudness of the programme | whole file, in blocks | **yes** — the relative gate depends on the mean | **one number, unambiguous** |
| Momentary (LUFS-M) | loudness of the last ~400 ms | sliding | no | a *meter* reading; a report would have to pick max or a series |
| Short-term (LUFS-S) | loudness of the last ~3 s | sliding | no | same problem, longer window |
| Loudness Range (LRA) | spread of short-term loudness | derived from S | yes | meaningful, but needs S plus its own gate and percentiles |

Integrated is the only one whose single value is self-explanatory on a page. Momentary and short-term
are not omitted because they are hard — they are cheap once the weighting exists — but because
**"Momentary: −14.2 LUFS" is meaningless without saying *when***, and answering that means choosing a
reduction (max? last? a timeline?) that is a product decision, not a measurement one. Shipping them
un-reduced would be publishing a number whose meaning we had not decided.

LRA is deferred for the same reason plus one more: it depends on short-term, so it cannot precede it.

## 3. Channel layout — the hard constraint

`PCMStreamDescription` carries `sampleRate`, `channelCount`, `frameCount` and **no layout**. The property
reader takes `channelCount` from the ASBD and its own comment says it is "never inferred from channel
layouts, labels, or names". Nothing reads `AVAudioChannelLayout`.

Measured (spike §3): a stereo pair of identical channels reads exactly **3.01 dB = 10·log₁₀2** above the
same signal in mono. So both channels carry the **same weight** and their energies sum — for one and two
channels the weighting is a function of the *count* alone, and no layout knowledge is needed.

Beyond stereo, the standard weights channels by position, and we cannot tell which channel is which.

**Decision: measure mono and stereo; report nothing for anything else.** Not a failure — an absence,
because the file offered no way to size the measurement honestly. Reading `AVAudioChannelLayout` to
extend this is a **separate change**: it touches the property reader, the domain and the boundary rules,
and it should not ride along inside a loudness feature.

## 4. Where the DSP lives

`AudioInspectorAnalysis`, behind the existing `AudioDecoding` seam, as ADR-0006 says and as the
spectrogram and true peak already do. `AudioInspectorMedia` keeps AVFoundation; the domain keeps the
value type. No new port: the accumulator takes `PCMChunk` like its three siblings.

**`vDSP_biquad` is the implementation route**, measured at 0.117 s for two cascaded sections over two
channels of ten-minute audio. It carries its own delay state, which is exactly what a chunked stream
needs. `AVAudioUnitEQ` and `AVAudioConverter` were considered and rejected: both live in Media, both
would drag a media framework into a DSP decision, and neither exposes coefficients we could record with
the measurement.

## 5. The algorithm, as far as it is known

1. K-weight each channel (two cascaded biquads, per-channel filter state carried across chunks);
2. accumulate squared weighted samples into fixed-length blocks;
3. per block, combine channels with their weights (1.0 each for mono/stereo, §3);
4. discard blocks below the **absolute gate**;
5. compute the mean of the survivors, derive the **relative gate** from it, discard again;
6. recompute the mean of what survives, convert to LUFS.

**UNRESOLVED and required from the standard**: the coefficients and how they adapt to sample rate; the
block length and overlap; both gate values; the LUFS conversion offset; the treatment of a trailing
partial block.

**Resolved by measurement**: the result must be rate-invariant (spike §5 — identical to 0.1 LUFS across
44.1/48/88.2/96/192 kHz), and gating must exclude a 40 dB-quieter half (spike §6).

## 6. Numeric strategy

**Not inherited from a sibling.** Signal levels widen to `Double` before reducing because their sums
overflow in `Float`; true peak reconstructs in `Float`. Loudness has a third shape: an **IIR filter**,
where `Float` state can accumulate error over millions of samples, followed by an energy sum that has
the same overflow exposure signal levels had.

**Starting position, to be confirmed by measurement, not assumed**: filter in `Float` via `vDSP_biquad`
(measured 0.117 s), widen to `Double` before squaring and accumulating (measured 0.028 s). Task group 4
measures `Float` against `Double` filter state on a long file and picks with numbers. If `Float` state
drifts measurably against the oracle, the filter moves to `Double` and the cost is re-measured.

## 7. Chunk independence — the risk this feature carries

An IIR filter plus fixed-length blocks is the most chunk-sensitive thing this codebase has attempted.
Filter state must cross chunk boundaries and block boundaries must be absolute, not per-chunk.

The guarantee must be the one every other analysis already keeps: **identical at every chunk size**, over
the sizes the suites already use (1, 3, 127, 512, 4 096, 65 536, whole file). A tolerance here would be
admitting the state is not carried correctly. If exact equality proves impossible in `Float`, that is
evidence for `Double` state (§6), not for a widened tolerance.

## 8. Domain model

A **sibling type**, `LoudnessMeasurement`, beside `SignalLevelMetrics` and `TruePeakMeasurement` —
`Sendable`, `Equatable`, failable, not `Codable` (ADR-0009).

Extending `SignalLevelMetrics` was rejected: it holds direct sample-domain facts, per channel, with no
weighting and no time structure. Loudness is frequency-weighted, gated, time-blocked and **whole-file**;
there is no per-channel loudness to report, because the channels are summed before the number exists.
Putting them in one type would invite exactly the confusion the product exists to avoid.

It carries its **method** — the weighting's identity, the gate values, the block length — for the reason
ADR-0019 gives for true peak: a measurement whose methodology is not attached is not reproducible.

Zero frames and files shorter than one block yield **no measurement** (§9). Silence is discussed there
too.

## 9. Unit, silence, and the too-short file

**Decision: the domain stores LUFS.** True peak stores linear because dBTP is a *presentation* of a
linear peak; here the normative quantity **is** the logarithmic one — "−14.2 LUFS" is the measurement,
not a rendering of it. Storing linear energy and converting in the view would invent a unit the standard
does not use and would put the conversion offset in the presentation layer, where it cannot be tested
against the oracle.

Measured (spike §7): the reference reports **−70.0 LUFS for both** five seconds of digital silence and a
300 ms file. Those are two different situations and this project does not collapse them:

- **shorter than one block** → `unavailable`. No block was ever completed, so nothing was measured — the
  same shape as a channel with no frames in signal levels.
- **digital silence** → **UNRESOLVED, and deliberately so.** Either it is `unavailable` (every block was
  gated out, so the gated mean is undefined) or it is a real measurement reported as "below the
  measurable floor". Both are defensible; the answer depends on what the standard says the absolute gate
  *means*, which task 1 will settle. It must not default to publishing −70.0 as though it were a
  measurement of the file.

## 10. Presentation and export

**Copy, not implementation.** Label "Integrated loudness", value "−14.2 LUFS" at one decimal, method
shown beside it as true peak's already is. No per-channel row. Absence reads as the existing "not
computable" phrasing rather than a number.

**Forbidden, and this is the whole point of the feature being a measurement**: "too loud", "too quiet",
"bad master", "streaming ready", any platform target, any normalisation advice, any comparison to −14 or
−23. The report states what was measured.

Export: additive under `measurements`, alongside `signalLevels` and `truePeak`, absent when not
measured. `schemaVersion` stays **1**. No path, no location, deterministic for a given file and engine
version.

## 11. Alternatives considered

| | | |
| --- | --- | --- |
| **A** | **Integrated only** | **Chosen.** The one metric with an unambiguous single value in a static report. |
| B | Integrated + Momentary + Short-Term | Rejected *for now*: cheap to compute, but each needs a reduction decision (max? series?) that is a product question, and shipping them unreduced publishes numbers whose meaning is undecided. |
| C | Integrated + LRA | Rejected: LRA needs short-term, so B precedes it. |
| D | Extend `SignalLevelMetrics` | Rejected: mixes weighted temporal quantities with direct sample facts. |
| E | Shell out to FFmpeg for shipped values | Rejected by ADR-0006 and unchanged: it ties correctness to bundling FFmpeg. It remains the oracle. |
| F | Read `AVAudioChannelLayout` to support surround now | Rejected as scope: it touches the property reader, the domain and the boundaries, and belongs in its own change. |
