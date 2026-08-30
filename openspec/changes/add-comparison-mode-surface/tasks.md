# Implementation Tasks

**R8 of `restructure-inspection-workspace` (task 3.7).** It makes ADR-0026 §2 and §3 true — a comparison
is a mode of the same workspace — and removes the transitional page R7 could not.

Boundaries inherited and not spent here: the domain, the media adapter and the analysis target are not
touched; `ImportFlowModel` and `ComparisonState` remain the only sources of the data lifecycle; the
selected section is named by no target below the composition root; the export, `ReportExportToolbar`,
`ExportableMeasurements` and `schemaVersion` 1 are untouched; no second PCM read and no recomputation;
and no semantic test is retired by calling it legacy.

## 1. Before writing anything

- [ ] 1.1 Confirm the three formatters R8 re-homes exist and are reachable from a section view:
      `ComparisonFormatter.rows(for:)`, `MeasurementComparisonFormatter.blocks(for:)`, and
      `RootView.reportVisuals(for:in:)`.
- [ ] 1.2 Confirm `warningSummary`'s call sites and coverage before deleting it.
- [ ] 1.3 Confirm what the bottom bar owns — Compare, Close comparison, Choose another file — and that
      none of it lives in `ReportView`, so removing that view loses no control.
- [ ] 1.4 Confirm the export is already above the routing and independent of the comparison, so R8 must
      not move it.

## 2. The Comparison Overview

- [ ] 2.1 `ComparisonOverviewView` — the two identities and the existing framing, and nothing else.
- [ ] 2.2 **Unconditional by construction**: no element on it varies with any outcome, so no appearance
      or disappearance can mean the files are alike.
- [ ] 2.3 No Notes, no count, no Result, no technical property, no measurement, no outcome, no path.

## 3. Details in comparison mode

- [ ] 3.1 `ReportDetailsView` takes an optional comparison and presents the technical properties through
      `ComparisonFormatter.rows(for:)` when it has one.
- [ ] 3.2 Both identities, positionally labelled.
- [ ] 3.3 Each file's notes, in the report's own words, **never counted**.
- [ ] 3.4 Each file's result, presented per file and **never compared**.

## 4. Measurements in comparison mode

- [ ] 4.1 `ReportMeasurementsView` takes an optional comparison and presents
      `MeasurementComparisonFormatter.blocks(for:)` in the section's own groups — in place, not appended.
- [ ] 4.2 The LU difference stays on the loudness row; no other row gains a place for one.
- [ ] 4.3 Absence, failure and not-comparable keep their own words; no zero, no placeholder.

## 5. The visual sections

- [ ] 5.1 Confirm Waveform and Spectrum already pair through `ReportVisuals` and need no change.
- [ ] 5.2 Assert their scales, axes, out-of-range sentences and single shared legend are untouched.

## 6. Routing, and the page that goes

- [ ] 6.1 The five sections routed for both modes from the one read of `flow.comparison`.
- [ ] 6.2 `legacyReportSurface` removed.
- [ ] 6.3 `ReportView` and `ComparisonSection` removed, **after** a call-site audit proves them dead.
- [ ] 6.4 `warningSummary` deleted, not migrated.
- [ ] 6.5 Compare, Close comparison and Choose another file unchanged; the export untouched.

## 7. Loading and failure

- [ ] 7.1 Loading says the second file is being inspected, where its values would be, with no placeholder.
- [ ] 7.2 Failure states the flow's own message, attributes no cause, and leaves the first file intact.

## 8. Tests

- [ ] 8.1 **Overview** — both identities; no path; no count, score, percentage, similarity, confidence,
      differences list or empty differences state; no Notes; no warning summary; no Result comparison; no
      better/worse; no provenance.
- [ ] 8.2 **The all-agree gate** — an all-agree pair and a maximally-different pair render the same
      elements; the strings differ only where the two files' own facts differ.
- [ ] 8.3 **Nothing-comparable** — each measurement states its own reason; no total, proportion or single
      phrase about how much was comparable.
- [ ] 8.4 **Measurements** — rows preserved; First/Second positional; the four semantics intact; LU
      difference only; no true-peak delta; bandwidth wording intact; absence ≠ zero; failure ≠ absence.
- [ ] 8.5 **Details** — both files' facts; no same/different aggregate label; notes not counted; results
      not compared; no path; no provenance.
- [ ] 8.6 **Visual** — paired presentations used; scales, geometry, out-of-range and legend unchanged.
- [ ] 8.7 **Lifecycle** — the section survives entering, loading, ready, failed, closing and superseding;
      a new successful primary returns to Overview.
- [ ] 8.8 **Functionality** — Compare, Close, Choose another and Export retained; export reachable from
      all five sections and independent of the comparison; `schemaVersion` 1; no comparison export.
- [ ] 8.9 **Architecture** — `legacyReportSurface`, `ReportView`, `ComparisonSection` and
      `warningSummary` have no callers; no second PCM read; no new DSP; active changes intact.

## 9. Negative controls — each seen to fail, then reverted and verified

- [ ] 9.1 **A** — *"All measurements agree"* on the Overview.
- [ ] 9.2 **B** — a *"Properties that differ"* list, including its empty case.
- [ ] 9.3 **C** — *"2 differences"*.
- [ ] 9.4 **D** — *"95% similar"*.
- [ ] 9.5 **E** — a numeric delta invented for true peak.
- [ ] 9.6 **F** — *First* renamed *Original*.
- [ ] 9.7 **G** — each spectrogram normalised separately.
- [ ] 9.8 **H** — Close comparison removed.
- [ ] 9.9 **I** — the new surface and the old page visible together.
- [ ] 9.10 **J** — the section reset to Overview when a comparison becomes ready.
- [ ] 9.11 **K** — *"1 warning on this file"* reintroduced.
- [ ] 9.12 **L** — the export toolbar moved inside one section.

## 10. Visual validation

- [ ] 10.1 Comparison Overview: all-agree, several differences, nothing comparable — **the three must not
      communicate different outcomes.**
- [ ] 10.2 Measurements: same values, mixed differences, absence and failure, long bandwidth wording.
- [ ] 10.3 Details: long filenames, differing codec and container, notes on one side only, result states.
- [ ] 10.4 Waveform: same duration, shorter second, shorter first.
- [ ] 10.5 Spectrum: same rate, 44.1 against 96, 96 against 44.1.
- [ ] 10.6 At 720 × 480, 1000 × 620 and 1440 × 900. Record what could not be rendered, and why.

## 11. Vocabulary sweep — R8's own gate

- [ ] 11.1 Sweep production, tests, copy, accessibility and previews for every term that could carry an
      aggregate, and report each occurrence as allowed or prohibited **with its reason** — not a blind ban.

## 12. Gates

- [ ] 12.1 `./Scripts/check-boundaries.sh`
- [ ] 12.2 `swift build -Xswiftc -warnings-as-errors`
- [ ] 12.3 The full test suite, twice.
- [ ] 12.4 `xcodebuild -destination platform=macOS`
- [ ] 12.5 `openspec validate --strict` for R8 and for every active change; `git diff --check`.

## 13. Closing, pre-merge only

- [ ] 13.1 Post-review of the diff against `design.md` and this change's boundaries.
- [ ] 13.2 The umbrella stays **17/29** and §3.7 stays open until merge; ADR-0026 stays `Proposed`.

**No push, no PR, no merge, no archive. R9 is not implemented here.**
