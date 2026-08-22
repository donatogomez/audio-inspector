# Compare two files by their measurements, not only by their metadata

## Why

The A/B comparison compares `TechnicalProperties` — what the file's header declares. Everything measured
from its **samples** travels beside the report and is discarded: the flow filters the progressive update
to the report alone, and then drops the analyses outright at `case let .inspected(report, _)`.

That was right when it was written. ADR-0017 §9 deferred an evidence-level comparison because *"none of
the metrics it would compare exist yet."* Four now do — signal level metrics, true peak, integrated
loudness, programme bandwidth — and every one of them is **already computed for the second file** by the
same `SourceInspectionAction` and the same single shared PCM read. The work is done and thrown away.

A person comparing two copies of an album can currently see that both are 44.1 kHz 16-bit FLAC and learn
nothing about whether they sound the same. The measurements that would tell them *what changed* exist,
in memory, and are deleted.

## What Changes

- A new pure domain value, **`MeasurementComparison`**, built from two settled `ReportMeasurements`.
  It is a **sibling** of `FileComparison`, not an extension of it: measurements do not live in a report
  and never will (ADR-0018), and widening `FileComparison` to accept values it cannot derive from its
  two reports would destroy its integrity argument.
- The comparison flow **stops discarding** the second file's analyses and collapses them to settled
  optionals, exactly as the export path already does. Nothing is recomputed and no read is started.
- Per-metric semantics decided by the **units**, not by one generic rule (ADR-0024):
  - **programme bandwidth** is compared on its own grid — cells overlap iff `|f₁ − f₂| < (r₁ + r₂)/2`
    — and reported as `indistinguishable` or `separated`, with **no hertz difference**;
  - **integrated loudness** carries a **difference in LU**, the only one that does, because it is the
    only metric whose stored quantity is already logarithmic and whose difference is a named unit;
  - **true peak and signal levels** are shown as values with **no difference**: theirs would be a ratio
    of linear amplitudes, which ADR-0017 §3 excludes;
  - method identity decides comparability per metric, read from domain identities and never from a
    displayed string.
- One section on the existing comparison surface, beneath the technical rows.

## What This Deliberately Does Not Do

**It compares measurements. It does not interpret what a difference means about the audio.**

It cannot answer, and provides no field in which an answer could be written: whether the two files hold
the same master; whether one is a remaster, a transcode, an upsample or a lossy source; which has more
dynamic range; which is better, more authentic or worth keeping; or whether one derives from the other.
Each is an inference with a threshold, and each belongs to the Findings capability, which carries
evidence, alternatives and a confidence level. This change is a **producer of facts for that capability**,
not a small version of it.

Also excluded, each deliberately: **export** (ADR-0017 §9 settled it — `schemaVersion` 1 describes one
file and gains no second `inspectedFile`); **waveform and spectrogram comparison** (`add-two-file-visual-comparison`);
**alignment, gain matching, residual and correlation** (ADR-0017 §9's evidence comparison — this change
performs no signal processing at all); and **aggregates of any kind** — no score, no similarity, no count
of differences, no `allSame`.

## Impact

- **New**: `MeasurementComparison` and its per-metric comparison types in `AudioInspectorDomain`; one
  presentation type and one section in `FeatureAnalysis`; the collapse from lifecycle to settled values
  in `FeatureImport`.
- **Changed**: `ImportFlowModel.compare(using:)` retains what it already receives; `ComparisonState`
  carries the new value beside `FileComparison`.
- **Untouched**: `FileComparison`, `PropertyComparison`, ADR-0017, the export contract, `schemaVersion`,
  every accumulator, and the shared read. No new port, no second decode, no new dependency.
- **Inherited**: ADR-0017's open accessibility gap on this surface, which this neither fixes nor worsens.
