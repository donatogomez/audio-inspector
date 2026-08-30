# Implementation Tasks

**R8 of `restructure-inspection-workspace` (task 3.7).** It makes ADR-0026 §2 and §3 true — a comparison
is a mode of the same workspace — and removes the transitional page R7 could not.

Boundaries inherited and not spent here: the domain, the media adapter and the analysis target are not
touched; `ImportFlowModel` and `ComparisonState` remain the only sources of the data lifecycle; the
selected section is named by no target below the composition root; the export, `ReportExportToolbar`,
`ExportableMeasurements` and `schemaVersion` 1 are untouched; no second PCM read and no recomputation;
and no semantic test is retired by calling it legacy.

## 1. Before writing anything

- [x] 1.1 Confirm the three formatters R8 re-homes exist and are reachable from a section view:
      `ComparisonFormatter.rows(for:)`, `MeasurementComparisonFormatter.blocks(for:)`, and
      `RootView.reportVisuals(for:in:)`.
      All three reachable from a section view. `RootView.reportVisuals` stays in the composition root and the paired value is passed in, as R5 and R6 already had it.
- [x] 1.2 Confirm `warningSummary`'s call sites and coverage before deleting it.
      Two callers, both inside `ComparisonSection.contextBlock`; **no test at all**. It dies with the view.
- [x] 1.3 Confirm what the bottom bar owns — Compare, Close comparison, Choose another file — and that
      none of it lives in `ReportView`, so removing that view loses no control.
      Compare, Close comparison and Choose another file are all in `RootView`'s own bottom bar — **zero occurrences in `ReportView`**. Removing that view loses no control.
- [x] 1.4 Confirm the export is already above the routing and independent of the comparison, so R8 must
      not move it.

      `.reportExportToolbar(` at line 334, the section switch at 361. Above the routing, once, and it reads no comparison. R8 does not move it.
## 2. The Comparison Overview

- [x] 2.1 `ComparisonOverviewView` — the two identities and the existing framing, and nothing else.
      `ComparisonOverviewView` — the framing and the two identities.
- [x] 2.2 **Unconditional by construction**: no element on it varies with any outcome, so no appearance
      or disappearance can mean the files are alike.
      Held **structurally**: the view reads each file's `AudioFileReference` and the copy, and never a property, a measurement, a warning, a status or any comparison type — asserted term by term. Nothing on it can vary with an outcome, so no appearance or disappearance can mean the files are alike.
- [x] 2.3 No Notes, no count, no Result, no technical property, no measurement, no outcome, no path.

      None of them present, swept by literal and by source. Every literal is digit-free, because a count reaches a reader as a digit before it reaches a word.
## 3. Details in comparison mode

- [x] 3.1 `ReportDetailsView` takes an optional comparison and presents the technical properties through
      `ComparisonFormatter.rows(for:)` when it has one.
      `ComparisonFormatter.rows(for:)`, unfiltered — asserted, and the row count asserted equal for an all-agree and an all-differ pair.
- [x] 3.2 Both identities, positionally labelled.
      Both, under `ComparisonCopy.firstFile` / `.secondFile`, with no outcome column — there is none, so none can appear.
- [x] 3.3 Each file's notes, in the report's own words, **never counted**.
      Each file's notes through `ReportPropertyFormatter.displays(for:)`, per file. The deleted sentence is refused by literal, and `warnings.count`, `severity`, `priority` and `sorted(` are refused by source.
- [x] 3.4 Each file's result, presented per file and **never compared**.

      Both results, side by side, with the result block read and asserted to contain no outcome.
## 4. Measurements in comparison mode

- [x] 4.1 `ReportMeasurementsView` takes an optional comparison and presents
      `MeasurementComparisonFormatter.blocks(for:)` in the section's own groups — in place, not appended.
      In place, with the inspection groups as the `else` branch — asserted by ordering, so it cannot become a block appended after them.
- [x] 4.2 The LU difference stays on the loudness row; no other row gains a place for one.
      Asserted against the formatter, where the rule lives: exactly one row publishes a difference, and it is the loudness one.
- [x] 4.3 Absence, failure and not-comparable keep their own words; no zero, no placeholder.

      `MeasurementComparisonSection` keeps its own words. No placeholder stands in for a loading second file, swept across all three surfaces.
## 5. The visual sections

- [x] 5.1 Confirm Waveform and Spectrum already pair through `ReportVisuals` and need no change.
      Confirmed: both take `ReportVisuals`, which `reportVisuals(for:in:)` has paired since R5. **Zero production lines changed in either.**
- [x] 5.2 Assert their scales, axes, out-of-range sentences and single shared legend are untouched.

      Their suites run unchanged, and the negative control that broke the shared absolute ramp was caught with **239 issues**.
## 6. Routing, and the page that goes

- [x] 6.1 The five sections routed for both modes from the one read of `flow.comparison`.
      One read of `flow.comparison`, in both vocabularies, feeding all five sections and both drawings — asserted to occur exactly once.
- [x] 6.2 `legacyReportSurface` removed.
      Removed. No caller anywhere.
- [x] 6.3 `ReportView` and `ComparisonSection` removed, **after** a call-site audit proves them dead.
      `ReportView.swift` and `ComparisonView.swift` deleted after the audit. **`ReportSection` was extracted first** — it was declared inside `ReportView.swift` and four live sections use it, so deleting the file without extracting it would have taken a shared container out with a dead page.
- [x] 6.4 `warningSummary` deleted, not migrated.
      Deleted. Nothing stands in for it: no badge, no icon, no pluralised phrase, no severity.
- [x] 6.5 Compare, Close comparison and Choose another file unchanged; the export untouched.

      All three controls asserted still built; the export asserted still above the routing, once, taking no comparison.
## 7. Loading and failure

- [x] 7.1 Loading says the second file is being inspected, where its values would be, with no placeholder.
      `ComparisonCopy.loading` where the second file's values would be, on all three surfaces.
- [x] 7.2 Failure states the flow's own message, attributes no cause, and leaves the first file intact.

      `ComparisonCopy.failedHeadline` plus the flow's own message, asserted to name no cause in the audio, with the first file's content untouched.
## 8. Tests

- [x] 8.1 **Overview** — both identities; no path; no count, score, percentage, similarity, confidence,
      differences list or empty differences state; no Notes; no warning summary; no Result comparison; no
      better/worse; no provenance.
      `ComparisonModeTests` — identities, no location, and a sweep of 27 forbidden terms plus every digit.
- [x] 8.2 **The all-agree gate** — an all-agree pair and a maximally-different pair render the same
      elements; the strings differ only where the two files' own facts differ.
      Both the structural gate (no outcome can reach the surface) and the differential (the two pairs render the same elements).
- [x] 8.3 **Nothing-comparable** — each measurement states its own reason; no total, proportion or single
      phrase about how much was comparable.
      Each measurement keeps its own reason; no surface states a total or a proportion.
- [x] 8.4 **Measurements** — rows preserved; First/Second positional; the four semantics intact; LU
      difference only; no true-peak delta; bandwidth wording intact; absence ≠ zero; failure ≠ absence.
      Rows preserved, positional labels, the four semantics untouched by their own suites, LU difference only, no invented delta, absence in words.
- [x] 8.5 **Details** — both files' facts; no same/different aggregate label; notes not counted; results
      not compared; no path; no provenance.
      Both files' facts, unfiltered; notes never counted; results never compared; no path; no provenance.
- [x] 8.6 **Visual** — paired presentations used; scales, geometry, out-of-range and legend unchanged.
      `ComparisonModeRoutingTests` asserts the paired value is what both visual sections take, and that a pair which has not settled is still not a pair.
- [x] 8.7 **Lifecycle** — the section survives entering, loading, ready, failed, closing and superseding;
      a new successful primary returns to Overview.
      R1's lifecycle suites run unchanged over all five sections and all comparison states — **87 tests across 9 suites**.
- [x] 8.8 **Functionality** — Compare, Close, Choose another and Export retained; export reachable from
      all five sections and independent of the comparison; `schemaVersion` 1; no comparison export.
      Every control asserted; the export asserted reachable above the routing and independent of the comparison; `schemaVersion` 1 and the export suites unchanged at **159 tests**.
- [x] 8.9 **Architecture** — `legacyReportSurface`, `ReportView`, `ComparisonSection` and
      `warningSummary` have no callers; no second PCM read; no new DSP; active changes intact.

      All four names asserted to have no caller; the decode counters and retention suites green at **82 tests**.
## 9. Negative controls — each seen to fail, then reverted and verified

- [x] 9.1 **A** — *"All measurements agree"* on the Overview.
      **A** — *All measurements agree* on the overview copy: **2 issues**.
- [x] 9.2 **B** — a *"Properties that differ"* list, including its empty case.
      **B** — the compared rows filtered to `.different`: **2 issues**.
- [x] 9.3 **C** — *"2 differences"*.
      **C** — *2 differences*: **3 issues**.
- [x] 9.4 **D** — *"95% similar"*.
      **D** — *95% similar*: **3 issues**.
- [x] 9.5 **E** — a numeric delta invented for true peak.
      **E** — a difference given to every `.different` row rather than to loudness alone: **20 issues**.
- [x] 9.6 **F** — *First* renamed *Original*.
      **F** — `firstFile` renamed *Original*: **3 issues**.
- [x] 9.7 **G** — each spectrogram normalised separately.
      **G** — the shared absolute ramp replaced by a per-file range: **239 issues**.
- [x] 9.8 **H** — Close comparison removed.
      **H** — the Close comparison button removed: **2 issues**.
- [x] 9.9 **I** — the new surface and the old page visible together.
      **I** — both overviews rendered in the same branch: **2 issues**.
- [x] 9.10 **J** — the section reset to Overview when a comparison becomes ready.
      **J** — the navigation guard removed so a settling comparison moves the reader: **39 issues**.
- [x] 9.11 **K** — *"1 warning on this file"* reintroduced.
      **K** — *1 warning on this file* reintroduced: **1 issue**.
- [x] 9.12 **L** — the export toolbar moved inside one section.

      **L** — the export toolbar moved inside the Details branch: **2 issues**.
## 10. Visual validation

- [x] 10.1 Comparison Overview: all-agree, several differences, nothing comparable — **the three must not
      communicate different outcomes.**
      Rendered at all three sizes for an all-agree pair and a pair agreeing about nothing, plus loading and failed. **The two render the same elements in the same order**; only the files' own names and extensions differ. No verdict, no badge, no colour.
- [ ] 10.2 Measurements: same values, mixed differences, absence and failure, long bandwidth wording.
      **Open.** The waiting state rendered. **Not rendered**: settled comparisons with mixed differences, absence, failure and long bandwidth wording — reaching them needs a settled `MeasurementComparison` fixture the harness did not build.
- [x] 10.3 Details: long filenames, differing codec and container, notes on one side only, result states.
      Rendered at all three sizes with a very long filename, differing codec and container, notes on the first file only, and two different result states. **This is what found the clipped-reason defect.**
- [ ] 10.4 Waveform: same duration, shorter second, shorter first.
      **Open: not rendered.** R8 changed no line of the waveform section; R5 rendered it paired at three sizes in five states, and its suites run green here.
- [ ] 10.5 Spectrum: same rate, 44.1 against 96, 96 against 44.1.
      **Open: not rendered**, for R5's reason: R6 rendered 44.1 against 96 by eye and R8 changed nothing.
- [x] 10.6 At 720 × 480, 1000 × 620 and 1440 × 900. Record what could not be rendered, and why.

      720 × 334, 1000 × 500 and 1440 × 760 (the content heights those windows leave). At the minimum the compared grid runs past the window and scrolls inside its section — the closed decision this slice was given. The two limitations above are recorded rather than implied.
## 11. Vocabulary sweep — R8's own gate

- [x] 11.1 Sweep production, tests, copy, accessibility and previews for every term that could carry an
      aggregate, and report each occurrence as allowed or prohibited **with its reason** — not a blind ban.

      22 terms swept over the three surfaces. Twenty have **zero** occurrences. Two survive and are audited: `source` is `AudioFileReference.source`, the domain's field for *how the file was selected* — never *source file*, which the positional test refuses as a phrase; `warnings` is the domain field read to produce the notes, which reaches a reader as *Notes* and is never counted.
## 12. Gates

- [x] 12.1 `./Scripts/check-boundaries.sh`
      `✅ architecture boundaries respected`
- [x] 12.2 `swift build -Xswiftc -warnings-as-errors`
      Clean.
- [x] 12.3 The full test suite, twice.
      **1897 tests in 205 suites**, twice.
- [x] 12.4 `xcodebuild -destination platform=macOS`
      `** BUILD SUCCEEDED **`
- [x] 12.5 `openspec validate --strict` for R8 and for every active change; `git diff --check`.

      R8 valid; all three active changes valid; `git diff --check` clean.
## 13. Closing, pre-merge only

- [x] 13.1 Post-review of the diff against `design.md` and this change's boundaries.
      Walked against `design.md`'s seven decisions. 23 files, +1815/−883; `AudioInspectorDomain`, `AudioInspectorAnalysis`, `AudioInspectorMedia` and `FeatureImport` have **zero files changed**.
- [x] 13.2 The umbrella stays **17/29** and §3.7 stays open until merge; ADR-0026 stays `Proposed`.

- [ ] 13.3 **Post-merge only.** The administrative close: the PR, the merge, the umbrella's §3.7, and
      `openspec archive add-comparison-mode-surface`. R8 is not administratively closed before any of
      them exists.

**No push, no PR, no merge, no archive. R9 is not implemented here.**

      Umbrella **17/29**, §3.7 open; ADR-0026 `Proposed`; `docs/` and `openspec/specs/` untouched.