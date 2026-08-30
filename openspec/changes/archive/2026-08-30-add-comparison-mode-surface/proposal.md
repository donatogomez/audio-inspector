## Why

**Comparison is still a page.** R1–R7 turned one scrolling report into five workspace sections, and every
one of them now has content of its own — for a single file. The moment a second file is chosen, the
Overview falls back to the transitional report page R7 could not remove, because that page is the only
host of `ComparisonSection`. So a reader who was in Waveform, started a comparison and returned to
Overview lands on the surface the redesign exists to replace.

ADR-0026 §2 decided the shape: **a comparison is a mode of the same workspace, not a document of its
own.** §3 decided that the same five sections exist in both modes and that *what changes is what each
one contains, not which ones there are.* This is R8 of `restructure-inspection-workspace` (task 3.7),
and it is the slice that makes both true.

## What Changes

- **Each of the five sections presents a comparison in place**, using the semantic values the domain
  already produces. Nothing is re-derived, re-worded or re-decided: `ComparisonFormatter.rows(for:)`,
  `MeasurementComparisonFormatter.blocks(for:)` and `PairedVisualsPresentation` are the same values the
  legacy page was rendering.
- **A Comparison Overview**, strictly ADR-0026 §8: the two identities and the existing factual framing.
  No count, no score, no differences list, no Notes, no Result comparison, and nothing whose presence or
  **absence** could mean *the two files match*.
- **Waveform and Spectrum need no change at all.** They already take `ReportVisuals`, which the
  composition root already builds from the comparison — R5 and R6 wired the pairing in when they were
  built.
- **`legacyReportSurface`, `ReportView` and `ComparisonSection` are removed**, once their call sites are
  proven empty.
- **`ComparisonSection.warningSummary` is deleted, not migrated.** It renders *"1 warning on this file"*
  — a per-file count of notes, written before R3 made *"A note MUST NOT be counted, scored, ranked by
  severity, or summarised into a total"* canonical. It has two callers, both inside the view being
  removed, and no test.

**No BREAKING change.** No measurement semantics, no comparison semantics, no analysis, no export, no
schema. Nothing is read, decoded or recomputed to present any of this.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `audio-file-inspection`: the five workspace sections present a comparison in place; the legacy report
  page is gone; Notes are never counted or summarised on any surface.
- `audio-two-file-comparison`: **presentation only** — where each comparison is read, and that no
  surface may publish an aggregate, by a value or by an absence. Its semantics are untouched.

`audio-two-file-visual-presentation` is **not** modified: R5 and R6 already satisfied its paired
presentation requirements, and R8 changes neither drawing.

## Impact

**Production**

- `Sources/AudioInspectorApp/RootView.swift` — the five sections routed for both modes from the one read
  of the comparison; the transitional branch removed.
- `Sources/FeatureAnalysis/` — a Comparison Overview; comparison inputs on the Details and Measurements
  sections; `ReportView.swift` and `ComparisonView.swift` removed.

**Untouched, and asserted rather than intended**

`AudioInspectorDomain`, `AudioInspectorAnalysis`, `AudioInspectorMedia` and `FeatureImport`; every
comparison and measurement semantic, including which pairs are comparable and the LU-only difference
rule; `ComparisonFormatter`, `MeasurementComparisonFormatter` and their copy owners; the paired axes,
ramps and out-of-range rules; the export, `ReportExportToolbar`, `ExportableMeasurements` and
`schemaVersion` 1; the one PCM read per file; and R1's navigation lifetime.

## The risk this change is written against

`audio-two-file-comparison` carries a scenario that is easy to satisfy by accident and hard to satisfy on
purpose:

> **WHEN** every comparable measurement agrees **THEN** the system offers no single value, flag or
> phrase meaning "the two files match"

An aggregate need not be a number. A differences list that renders empty, a badge that disappears, a
success colour that only appears when nothing differs — each of them **says** it, and the absence is the
statement. So the Comparison Overview is built with no place for such an absence to occur, and the
all-agree case is a gate rather than an afterthought: the surface must be unable to tell a reader
anything about whether the files are alike.
