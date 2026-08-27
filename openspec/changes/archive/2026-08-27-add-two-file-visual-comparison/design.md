# Design — paired visuals for two files

Every decision here is **ADR-0025's**; this document says how the code arrives at them and what it must
not do on the way. Where the two disagree, the ADR is right and this file is wrong.

## 1. What the flow already pays for, and throws away

The compared file runs the same `SourceInspectionAction` as the primary one. One shared read produces six
analyses; four become `ReportMeasurements`, and two are dropped:

```
SourceInspectionOutcome.inspected(report, analyses: InspectionAnalyses)
        │
        ├── analyses.settledMeasurements ──► comparedMeasurements ──► MeasurementComparison
        └── analyses.waveform, analyses.spectrogram ──► out of scope   ← this change stops here
```

The discard is one line, in `ImportFlowModel.settle(_:against:restoringOnCancellation:andMeasurements:)`.
It is measured rather than assumed: `ComparisonMeasurementsReachTheComparisonTests` asserts
`decodersMade == 1`, `decodeCalls == 1`, and both visualisations `.available` for the compared file.

**Nothing in this change touches how either artefact is produced.** It changes what happens to a value
that already exists at that line.

## 2. Ownership — a sibling container, never a field of `ReportMeasurements`

Per file: what became of the envelope, what became of the spectral model, and the
`PCMStreamDescription` the read used. `SettledMeasurements.swift` already states the rule this obeys —
*"A waveform and a spectrogram are pictures of the samples rather than measurements of them…
`ReportMeasurements` has no field either could occupy, so this is enforced by the type rather than by
this comment."*

**The stream description is load-bearing, not stored in advance of a need.** `WaveformEnvelope` is
deliberately poor: it carries `frameCount` and `channelCount` and **no sample rate**, so an envelope alone
cannot state a duration and two envelopes alone cannot share a time axis. `Spectrogram` carries
`sampleRate` and can. The description resolves that asymmetry from **one** source the read already holds
— `AudioDecoding` returns it, and returns `nil` exactly when the file exposed no usable frame count, in
which case every analysis is absent anyway. Nothing is added to `WaveformEnvelope`.

Both drawing kinds therefore take their extents from the **same** description, so a waveform lane and a
spectrogram lane cannot disagree about how long a file is.

## 3. Settling — where lifecycle stops, for the second time

Five states exist across the two sides. **None of them belongs in a paired payload**, and the collapse
happens in `FeatureImport`, in the seam `SettledMeasurements.swift` already established:

| state | first file (`…State`) | compared file (`…Outcome`) | in the pair |
| --- | --- | --- | --- |
| `loading` | yes | — | **no pair yet.** It is a state of the flow, never a result |
| `available` | yes | yes | the artefact, carried |
| `unavailable` | yes | yes | **absence**, carried as absence and stated in words |
| `failed` | yes | yes | **failure**, kept distinct from absence and stated in words |
| `cancelled` | — | yes | **not settled.** No pair. It says nothing about the file and must never be shown as one |

Two rules follow, and both are testable:

- **A pair exists only when both sides have settled**, in the shape
  `publishMeasurementComparisonIfBothSettled` already has. A first file still reading is not a first file
  with no pictures.
- **Absence and failure stay apart**, per side and per artefact — the distinction `SpectrogramCopyTests`
  exists to protect, plus the spectrogram's third statement, *too short to analyse*, which is a model with
  zero columns and not an absence.

## 4. Atomicity — one payload, or none

Five things must belong to one pair of inspections: the technical comparison, both files' measurements,
and both files' visuals. The refusal is ADR-0024 §3's, applied unchanged: *"it would put two values and
one outcome on screen from two different places, free to belong to two different operations."*

So the surface receives **one value**, assigned once, and never assembles a pair by reading the first
file's pictures from `InspectionPresentation` and the second's from a retained field. The retained
per-comparison payload must be structured so a visuals bundle **cannot** be paired with another
operation's measurements or technical comparison — one merged value, or sibling fields cleared in
lockstep by the same three events. The property is fixed; the mechanism is not.

`MeasurementComparisonAtomicityTests` and `InspectionAnalysesStaleAtomicityTests` are the shape to reuse,
including their handshake: a scripted action released step by step, with no sleep, no polling and no
`Task.yield()`, and two files with **deliberately distinguishable** pictures so that "entirely B" is
observed rather than inferred from fields that merely stayed empty.

## 5. Replacement and staleness

The flow already supersedes by `currentComparisonOperation`, disjoint from the primary operation number,
and already clears its retained bundle on exactly three events. The visuals join that lifecycle and add
none of their own:

| event | technical comparison | measurements | paired visuals | single-file drawings |
| --- | --- | --- | --- | --- |
| comparison starts (A → B) | rebuilt | cleared, then rebuilt | cleared, then rebuilt | shown until the pair settles |
| second file replaced (B → C) | rebuilt for C | C's | C's | shown again until C's pair settles |
| B settles late, after C started | dropped (superseded) | dropped | **dropped** | unaffected |
| second inspection cancelled | previous restored | previous restored | previous restored | follow the restored pair |
| comparison dismissed | cleared | cleared | cleared | restored |
| new primary inspection | ends the comparison | cleared | cleared | the new file's own |
| second file failed to open | `.failed` | none | **none** | stay |

**The single-file drawings are shown whenever there is no settled pair.** That one rule covers dismiss,
cancel, supersede, failure and *not yet* without a case for each, and it is why restoring costs nothing:
the first file's own `WaveformState` and `SpectrogramState` were never taken away.

## 6. Waveform geometry

Extents in seconds, from each file's own description: `duration = frameCount / sampleRate`.

```
shared = max(durationFirst, durationSecond)
fraction(file) = duration(file) / shared          // 1.0 for the longer file
```

Each lane draws its buckets across `fraction · width`, using the existing bucket→band arithmetic
unchanged, and **stops there**. Beyond it: no bar, no baseline through it, no `WaveformBucket.silent`
substituted — a silent bucket is a **measured** zero, and past a file's last frame nothing was measured.
The region is stated in words as **outside that file's audio**.

Amplitude keeps the fixed `WaveformGeometry.drawnRange` (`-1 … +1`) both lanes, with the clamp applied
**when drawing and only then**, exactly as today. No per-file normalisation, no auto-range, no scaling to
either file's peak.

**Equal durations are the ordinary case** — two copies of one track — and give two full-width drawings
with no remainder, which is the picture the naive layout would have produced. The rule costs nothing when
the files agree and refuses to lie when they do not.

No stretching, no clipping, no alignment: nothing here asserts that the two files start at the same
moment, and the surface may not say or imply that a position in one lane is the same position in the
other.

## 7. Spectrogram geometry

Time follows §6 unchanged, from the same description.

Frequency:

```
sharedNyquist = max(nyquistFirst, nyquistSecond)   // nyquist = sampleRate / 2
verticalFraction(file) = nyquist(file) / sharedNyquist
```

Each grid draws from 0 Hz upward across `verticalFraction · height`. Above it: **no cell**, and a
treatment **visually distinct from the ramp's floor colour**. This is the whole point of the decision:
*"this file cannot represent this range"* and *"this file was measured here and is very quiet"* are
different facts, and `SpectrogramColourRamp`'s darkest colour already means the second. It is also stated
in words.

The shared axis is **never cropped to the lower Nyquist**, for the reason `SpectrogramAxes` already gives
for one file: *"A 96 kHz file that holds nothing above 22 kHz is showing exactly the thing a collector is
looking for."* A 44.1 kHz file beside a 96 kHz one is therefore **shorter on the axis**, not rescaled to
match.

Energy keeps the same ramp, the same `Spectrogram.floorDecibels` (−120) and the same legend for both
lanes. Nothing is re-ranged per file.

**Channels are not paired.** Both models already combine channels — the envelope by min/max across all of
them, the spectrogram by maximum in the frequency domain — and differing counts are not an error, not
reconciled and not compared here. ADR-0024 §7 already compares channel counts where a per-channel
measurement exists.

## 8. Surface

Without a settled pair — unchanged from today:

```
Waveform          [ first file's envelope, full width ]
Spectrogram       [ first file's grid, full height ]
…property rows…
Comparison        …technical rows…  …measurement rows…
```

With a settled pair — the two visual sections **stand in for** those two:

```
Waveform          First   [■■■■■■■■■■■■■■■■■■■■]              3:30
                  Second  [■■■■■■■■■■■■■■■  ·······]  3:00 · no audio beyond here
Spectrogram       First   [ grid to 22.05 kHz, upper region marked out of range ]  44.1 kHz
                  Second  [ grid to 48 kHz, full height ]                          96 kHz
…property rows…            unchanged
Comparison                 unchanged — technical rows and measurement rows both stay
```

**Why standing in rather than adding beneath** — the product decision this change records: adding would
put the first file on screen **twice at once**, at two different geometries (full axis in its own section,
a fraction of the shared axis in the pair), which is two answers to one question. While a pair is settled
the surface's question changes from *what is this file like?* to *how do these two files present under one
common visual reference*, and the paired drawing is the answer. The reduction in raster memory is a
consequence, not the reason.

Nothing else is replaced or hidden: the property rows, the technical comparison and the measurement
comparison are exactly where they were.

## 9. Absence and failure on the paired surface

Per file and per artefact, in words beside the drawn one, and never as a picture:

- **absent** — the file offered nothing to build it from;
- **failed** — producing it did not succeed, in a neutral sentence naming no path and no framework;
- **too short** — the spectrogram's own third statement, a model with no columns, kept distinct from both.

No empty envelope, no black grid, no zero-filled array, no floor-coloured rectangle stands in for any of
them. **One side's absence never withholds the other side's drawing**, and never removes the shared axis
the present side is drawn on.

## 10. Performance

| | |
| --- | --- |
| retained now | first file's envelope + model ≈ **2.02 MiB** |
| retained after | that, plus the second file's ≈ **2.02 MiB** → ≈ 4.03 MiB |
| `Spectrogram.values` | 1024 × 512 × 4 B = **2 MiB exactly** |
| `WaveformEnvelope` | 2048 × 8 B = **16 KiB** |
| raster, per drawn spectrogram | RGBA8 at model size = **2 MiB**, held while on screen |
| PCM retained | **none** — chunks stay bounded by chunk size, as today |
| new DSP | **none** |

Moving a `Spectrogram` into the pair copies a COW reference, not 2 MiB, as long as nothing mutates it —
which nothing does. Because the paired sections **stand in for** the single ones, the number of
spectrogram rasters on screen at once stays at two rather than rising to three.

## 11. Boundaries

- **Domain** — unchanged. No new type, no new field, no `Codable`, no port. `WaveformEnvelope`,
  `Spectrogram` and `PCMStreamDescription` are used as they are.
- **FeatureImport** — owns the per-file container, the collapse from lifecycle to settled, the retained
  payload and the atomic publication. It already owns both `…State` and `…Outcome`.
- **FeatureAnalysis** — owns the paired geometry and the paired section. It sees no `URL`, no
  AVFoundation type and no lifecycle.
- **Media / Analysis** — untouched. No decoder, no accumulator, no Accelerate, no second read.
- **Export** — untouched, and unreachable: neither artefact is `Codable` (ADR-0009), so the exclusion is
  enforced by the types rather than by a rule someone has to remember.

## 12. Rejected designs

- **Two independent UI sources** — the first file's pictures read from `InspectionPresentation`, the
  second's from a retained field, joined by the view. The obvious shape, and the one ADR-0024 §3 already
  refused for values: the two sides would be free to belong to two operations.
- **Retain the whole `InspectionAnalyses`** for the compared file. Smallest diff, and everything would be
  available later. Rejected: retains six outcomes to use two, re-introduces `.cancelled` into what a
  surface reads, duplicates the measurements already held, and invites a refactor that makes the
  measurement comparison's atomicity depend on this one's.
- **Extend `ReportMeasurements`** with the two artefacts. Rejected on the container's own recorded reason;
  it would also make the export mapping the place a picture has to be explicitly excluded, instead of a
  place it cannot reach.
- **Recompute either artefact for the pair** — from a second read, or from a re-run of the accumulators.
  Rejected: a second decode by another name, against ADR-0020 and ADR-0021, and detectable by the decoder
  counter that already exists.
- **A visual diff** — difference image, correlation, residual, matching regions, a similarity figure.
  Rejected: ADR-0017 §9's evidence comparison, every step a heuristic with a threshold.
- **Each drawing on its own axes, side by side.** Rejected: two equal lanes make a 3:00 file and a 3:30
  file look the same length and a 44.1 kHz file and a 96 kHz one look like they cover the same spectrum.
  That is the silent stretch this change exists to refuse.
- **Share axes at the `min` of the two extents.** Tidier — every drawing full width, no remainder.
  Rejected: it crops the longer file and hides the higher file's upper range. Cropping to make a layout
  tidy is the same act as cropping to make a verdict easy.
- **Add the paired drawings beneath the single-file ones**, keeping both. Evaluated and **rejected by
  product decision**: it shows the first file twice simultaneously, at two different geometries, and a
  reader comparing the two representations of the same file is being asked a question the surface did not
  mean to pose. Restoring the single drawings when the pair goes gives the same information without ever
  showing both at once.
