# Design — two-file measurement comparison

Decisions are in **ADR-0024**; this is the shape they imply and the evidence that would settle it.

## 1. What the flow already pays for, and throws away

`compare(using:)` runs the **same** `SourceInspectionAction` a first file runs. The second file
therefore gets a full inspection: one decoder, one shared PCM read, six consumers. Two lines discard all
of it —

```swift
guard case let .report(report) = update else { return }   // progressive: only the report survives
case let .inspected(report, _):                            // final: the analyses are dropped
```

— and the comments say so deliberately. **The compute cost of this change is therefore zero.** What it
adds is retention: four small value types per side. The waveform and spectrogram are produced and
discarded too; they stay discarded, because comparing pictures is `add-two-file-visual-comparison`'s.

A test must pin this rather than assume it: comparing two files creates exactly one decoder and performs
exactly one sample read **for the second file**, with the four measurements present in the comparison.

## 2. Types

```
MeasurementComparison(first: ReportMeasurements, second: ReportMeasurements)
  .signalLevels        SignalLevelsComparison
  .truePeak            TruePeakComparison
  .loudness            LoudnessComparison
  .programmeBandwidth  ProgrammeBandwidthComparison
```

Pure, synchronous, total, deterministic, no `throws`, no Foundation, no `URL`, no framework. Built only
from its two arguments, exactly as `FileComparison` is built only from two reports — the initialiser is
declared so the memberwise one cannot accept assembled results.

`ReportMeasurements` is reused rather than duplicated: it is already a domain container of the four
settled measurements, with no defaults, no lifecycle and four distinct types. Its doc frames it around
export and must be widened to say it is the settled-measurement bundle both consumers take.

**Why not one generic `MeasurementComparison<Value>`.** The four differ in what is comparable, in whether
a method gates it, in whether a difference exists and in whether channels take part. One generic rule
would have to be parameterised until it was four rules wearing one name.

## 3. Per-metric shape

| metric | gate | overall | per channel | difference | classification |
| --- | --- | --- | --- | --- | --- |
| signal levels | none | peak, RMS, DC offset, clipped count — four separate facts | by index | none (ratio) | exact only |
| true peak | `oversamplingFactor` + `filter` | `overallTruePeak` (derived max) | by index | none (ratio) | exact only |
| loudness | `algorithm` + demonstrated weighting pair | the single value | none — channels combine before it exists | **LU** | exact only |
| programme bandwidth | `identifier` | `overall` reading | by index | none (grid) | **indistinguishable / separated** |

Signal levels' four figures are four comparisons, not one: peak, RMS, DC offset and clipped count are
different quantities in different units, and one outcome over them would have to pick a rule for the
worst-fitting of the four. **RMS in particular is compared as a level and nothing more** — "different
RMS" is not "more compressed", and the vocabulary sweep exists to keep it that way.

## 4. Absence, and where lifecycle stops

Four states reach the flow for every measurement — loading, available, unavailable, failed, and for the
second file also cancelled. **None reaches the domain.** `FeatureImport` collapses:

- `…State` (the primary file, held in `InspectionPresentation`) → optional settled value;
- `…Outcome` (the compared file, held in `InspectionAnalyses`) → optional settled value.

Both collapses live in `FeatureImport`, which owns both types. The comparator then sees only
`ReportMeasurements`, and its gap vocabulary reuses ADR-0017's structural shape: which side had nothing,
never a message and never a reason invented here.

**A failure is therefore not a comparison outcome.** "This run's loudness failed" is a fact about a run;
the comparison says only that one side had no value.

## 5. Stale atomicity

The comparison already supersedes by `currentComparisonOperation`, and the update handler drops anything
from an older one. The measurement bundle must be **atomic with the report it belongs to**: a
presentation showing B's technical rows beside A's loudness would be the same class of defect
`InspectionAnalysesStaleAtomicityTests` was written for on the primary path.

The test reuses that suite's handshake — a scripted action, released step by step, with no sleep, no
polling and no `Task.yield()` — and gives A and B **deliberately distinguishable measurements**, so
"entirely B" is observed rather than inferred from fields that merely stayed empty.

There is one new sequencing fact to decide and pin: the comparison is currently published **the moment
the second report arrives**, before its measurements exist. So either the comparison publishes twice
(technical first, measurements when they settle) or it waits. **It publishes twice**: waiting would hold
back a complete technical answer for a measurement the reader may not need, which is the same reasoning
that put the report ahead of the read on the primary path.

## 6. Surface

The existing section is `Property | A | B | Outcome`. Measurements get their **own sub-section beneath
it**, in the report's own order so nothing invents a hierarchy of importance:

```
Signal levels        A            B            Outcome
Peak sample          -1.42 dBFS   -0.31 dBFS   Different
RMS                  -18.0 dBFS   -12.4 dBFS   Different
…
True peak            -0.80 dBTP   +0.30 dBTP   Different
Integrated loudness  -13.8 LUFS   -9.1 LUFS    Different        +4.7 LU
Programme bandwidth  16.1 kHz     20.1 kHz     Separated
                     23 Hz grid   23 Hz grid
```

The fourth column is the existing outcome vocabulary; the fifth exists **only** on the loudness row.
Bandwidth's outcome words are `Indistinguishable at these resolutions` / `Separated`, not `Same` /
`Different`, because they are statements about the grid rather than about the files.

A reader must be able to answer *did the loudness change, did the peak change, did the bandwidth change,
did the levels change* at a glance — and nothing on the surface may answer *why*.

## 7. Fixtures that discriminate

Ten A/B pairs, built from the existing `AudioFixtureSignal` vocabulary and written through the existing
writer; the comparison runs through production, not through hand-made measurements.

| # | pair | discriminates |
| --- | --- | --- |
| 1 | identical files | every metric `same`; exact equality is reachable |
| 2 | same signal, +6 dB | levels/true peak/loudness differ, bandwidth `indistinguishable` |
| 3 | same bandwidth, different loudness | the two are independent |
| 4 | same loudness, different bandwidth | the converse |
| 5 | true peak differs, sample peak does not | true peak is its own fact |
| 6 | stereo against mono | overall compares, per-channel reports the count |
| 7 | 44.1 kHz against 48 kHz, same content | loudness **compares** across weightings; bandwidth uses two grids |
| 8 | bandwidth readings inside one another's cells | `indistinguishable` |
| 9 | bandwidth readings one bin apart | `separated` — the other side of the same rule |
| 10 | one side silent | absence on one side, and the other metrics still compare |

Pairs 8 and 9 are the ones that would fail a naive equality rule, and pair 7 is the one that would fail
a naive method-equality rule. They are the reason those two rules are written the way they are.
