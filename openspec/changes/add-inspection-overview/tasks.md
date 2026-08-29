# Implementation Tasks

**R7 of `restructure-inspection-workspace` (task 3.6).** It gives Overview content of its own and, with
that, makes all five sections real in inspection mode. It keeps the transitional report page alive in
**one** place — Overview while a comparison exists — because that page is the comparison's only host and
R8 owns the comparison.

Boundaries inherited from the umbrella and not spent here: the domain, the media adapter and the analysis
target are not touched; `ImportFlowModel` and `ComparisonState` remain the only sources of the data
lifecycle; the selected section is named by no target below the composition root; the export and
`schemaVersion` 1 are untouched; no second PCM read and no recomputation; and no semantic test is retired
by calling it legacy.

## 1. Before writing anything

- [x] 1.1 **Read the two seams this slice depends on rather than reimplements** —
      `ReportPropertyFormatter.groups(for:)` / `.outcome(for:properties:)`,
      `MeasurementsDisplay.display(for:)`, and `RootView.waveformPresentation(for:)` — and confirm each
      is reachable from `FeatureAnalysis` at its current access level.
      Confirmed: all three are `internal` to `FeatureAnalysis`, where the new view also lives. `waveformPresentation(for:)` stays in the composition root and is passed in, because `AudioInspectorApp` depends on `FeatureAnalysis` and not the reverse.
- [x] 1.2 **Confirm the finding that shapes the branch**: `legacyReportSurface` has exactly one caller,
      and `ComparisonView` exactly one host. If either is false, §3 of `design.md` is wrong and the split
      has to be re-derived before any code is written.
      Confirmed by grep: `legacyReportSurface` has one caller (`case .overview`) and `ComparisonView` one host (`ReportView`). The split in §3 of `design.md` stands.
- [x] 1.3 **Confirm the finding that removes the warning count**: `audio-file-inspection`'s *Keep notes
      and the result apart from the facts* still carries its unqualified sentence. If it does not, the
      count returns under ADR-0026 §7 and this change gains a requirement.

      Confirmed: the sentence is unqualified in `openspec/specs/audio-file-inspection/spec.md`. The count is refused and the requirement is left alone.
## 2. The surface

- [x] 2.1 `InspectionOverviewView` in `FeatureAnalysis`: identity, core technical facts, key
      measurements, the compact drawing, and the result of the reading — in that order, on one reading
      measure, matching the idiom `ReportDetailsView` established.
      `InspectionOverviewView` — File, Technical, Measurements, Waveform, Result, on Details' 640 pt reading measure.
- [x] 2.2 The technical facts come from `ReportPropertyFormatter.groups(for:)`. **No property is named by
      hand anywhere in the file.**
      `ReportPropertyFormatter.coreFacts(for:)` — §6's six, selected beside `groups(for:)` and `summary(for:)` where property meaning already lives. The view names no property; a source sweep refuses one.
- [x] 2.3 The measurements come from `MeasurementsDisplay.display(for:)` — one per measurement, its own
      first row, or its state sentence when it has no rows. No method line, no per-channel breakdown, no
      reordering, no ranking.
      One row each, through `MeasurementsDisplay`. **A defect the render caught**: the row was labelled with the *measurement's* title, so *Signal levels: −3.00 dBFS* did not say which level it was. It carries the row's own name — *Peak sample* — and speaks the measurement aloud.
- [x] 2.4 The identity block reuses the words and the source sentence Details already uses, and carries
      no path, URL, directory or bookmark.
      Details' own words and its own source sentence. No path, URL, directory or bookmark, swept two ways.
- [x] 2.5 The result of the reading is `ReportPropertyFormatter.outcome(for:properties:)`, set apart from
      the facts as it is in Details.
      `outcome(for:properties:)` over **all nine** properties, not the six shown — it is the report's account of its own reading.
- [x] 2.6 `WaveformPlotSizing.overviewCompact` — a fixed strip, smaller than `reportPage`, budgeted and
      justified in the type's own documentation. The workspace sizings are not touched.
      `WaveformPlotSizing.overviewCompact` = `fixed(72)`, budgeted against the 720 × 480 window's ~334 pt of content height. `reportPage`, `workspaceSingle` and `workspaceLane` are asserted unchanged.
- [x] 2.7 The drawing is handed the same `WaveformPresentation` the Waveform section is handed, keeps
      `allowsHitTesting(false)`, and states loading, absence and failure in `WaveformCopy`'s own words.

      The same `WaveformPresentation` the Waveform section is handed. **A second defect the render caught**: only `headline` was rendered, and an envelope carries none — so the one state with a drawing was the one state with no words. Both lines are rendered now.
## 3. The branch, and the comparison it may not delete

- [x] 3.1 `RootView`'s `.overview` case splits on `ComparisonPresentation` — `.none` to the new surface,
      every other case to `legacyReportSurface`, unchanged — derived from the **one** read of
      `flow.comparison` the body already binds.
      Done. `.none` to the new surface, the other three to `legacyReportSurface`, from the one read of `flow.comparison` the body already binds.
- [x] 3.2 The switch is total, with no `default`, so a new comparison state must be answered here rather
      than silently falling to one side.
      Total, no `default` — asserted.
- [x] 3.3 `legacyReportSurface`, `ReportView`, `ComparisonView` and `comparisonPresentation(for:)` are
      **unchanged**, and the comment on the `.overview` branch says why the page survives and what
      removes it.

      Unchanged; the comment says why the page survives and what removes it.
## 4. Tests

- [x] 4.1 **Content** — the five blocks are present; the technical facts are the formatter's groups; each
      measurement contributes its own first row; the identity carries no location.
      `InspectionOverviewTests` — the five blocks, the formatter's six, one row per measurement, no location.
- [x] 4.2 **No drift** — the same fact carries the same name, value, unit and certainty on the overview
      as in the section that owns it, for a report exercising every property state.
      Each core fact is the very row `displays(for:)` produced, asserted by equality for a clean and a hostile report.
- [x] 4.3 **Absence and failure** — a fact with no value is words; a failed reading is distinguishable
      from an absent one and from one still being produced; an absent envelope is words, not a flat line.
      Bit depth absent keeps its row and its words; *not defined by this format* stays distinguishable from *read, but not reliable*; loading, absence and failure of the envelope are all words.
- [x] 4.4 **Vocabulary sweep** over every string this surface can render *and* over the new file's own
      string literals: no score, grade, rating, percentage, total, similarity; no judgement word; no
      origin, master, remaster, transcode, upsample or bitrate claim; **and no digit standing for a count
      of notes.**
      Rendered strings plus the file's own literals, > 40 strings. Judgement, quality, provenance, aggregate **and any digit in a literal** — the last because a count reaches a reader as a digit before it reaches a word.
- [x] 4.5 **Stillness** — a source assertion that the new file contains no `Button`, no gesture, no
      `onTapGesture`, no `NavigationLink`, and that the drawing keeps `allowsHitTesting(false)`.
      No `Button`, gesture, `NavigationLink`, `onHover`, `DisclosureGroup` or `focusable`; the drawing keeps `allowsHitTesting(false)`.
- [x] 4.6 **No property named by hand** — a source sweep over the new file for the property accessor
      names, so the surface cannot drift from Details by reaching past the formatter.
      A source sweep for the six property names and for `properties.<name>` accessors.
- [x] 4.7 **The comparison survives** — all four comparison states driven through the `.overview` branch;
      the comparison surface is reached in three of them and the new surface in the fourth.
      `OverviewRoutingTests` — all four comparison states through the branch's own mapping: three reach the comparison, one reaches the overview.
- [x] 4.8 **Nothing beneath changed** — the export and `schemaVersion` 1 unchanged after the overview has
      been presented; the decode counters unchanged; R1's navigation, R2's pre-inspection surface, R3's
      Details, R4's Measurements, R5's Waveform and R6's Spectrum asserted unchanged.

      The transitional page, the export, `schemaVersion` 1, R1's five sections and their order, and R2–R6's surfaces all asserted unchanged. The full suite is 1871 tests green, up from 1848.
## 5. Negative controls — each seen to fail, then reverted and verified

- [x] 5.1 **A count of notes would be caught.** Add the cardinality of `report.warnings` to the overview;
      demonstrate 4.4 fails; revert and verify by checksum.
      A `Notes` row carrying `report.warnings.count`. **Seen to fail with 4 issues across 2 tests**: `warnings.count`, `report.warnings` and the term *Notes* by structure, and *warnings* by vocabulary. Reverted; checksum verified.
- [x] 5.2 **A judgement would be caught.** Add a word the sweep forbids beside a measured value;
      demonstrate 4.4 fails; revert and verify by checksum.
      An *Assessment: Good quality for its format* row. **Seen to fail with 2 issues**: *good* and *quality*. Reverted; checksum verified.
- [x] 5.3 **Deleting the comparison would be caught.** Make the `.overview` branch unconditional;
      demonstrate 4.7 fails; revert and verify by checksum.
      The `.overview` branch made unconditional. **Seen to fail with 8 issues across 4 tests in 3 suites** — this change's two routing tests, and R3's and R6's own, which is what makes the control a defence rather than a private assertion. Reverted; checksum verified.
- [x] 5.4 **A second envelope would be caught.** Have the overview build its own reduced envelope;
      demonstrate the decode/recomputation assertions fail; revert and verify by checksum.

      The overview building a 64-bucket envelope of its own. **Seen to fail with 2 issues**: the drawing is no longer handed the envelope, and `WaveformEnvelope(` appears in the file. Reverted; checksum verified.
## 6. Visual validation

- [x] 6.1 Render the overview at the window's 720 × 480 minimum and at a large size, for a clean report,
      a report with every property state, and a report whose envelope is absent — and look at it.
      Rendered at 720 × 334 and 1400 × 820, for a clean report, a report in every property state, an absent envelope, and a wholly unsettled inspection — and looked at. **Both defects above were found this way and only this way**; every test passed before them.
- [ ] 6.2 Render the `.overview` branch with a settled comparison and confirm the transitional page is
      exactly what it was.
      **Open: not done, and marking it done would have claimed a look that never happened.** Reaching a
      settled comparison needs a second real file through the picker, which no harness here can drive.
      What exists instead is a structural assertion — the page is built exactly once, from this branch,
      with the same comparison and export arguments — and that is evidence, not a rendering. It stays
      open until someone drives two real files through the app, which is a natural part of R9's human
      pass.
- [x] 6.3 Record what could **not** be seen, and why, rather than implying it was.

      **What could not be seen, and why.** SwiftUI draws no `ScrollView` content in a headless test process — proven with a two-line control, `ScrollView { Text(…) }`, which came out blank — so the surface was hosted in a real app window instead. The same limitation applies to R3's Details, which is built the same way; it is inherited, not introduced. The **comparison** state was not rendered: reaching it needs a second real file through the picker, which no harness here can drive.
## 7. Gates

- [x] 7.1 `./Scripts/check-boundaries.sh`
      `✅ architecture boundaries respected`
- [x] 7.2 A zero-warnings build.
      `swift build` clean, and `xcodebuild … -destination platform=macOS` → `** BUILD SUCCEEDED **`, no warnings.
- [x] 7.3 The full test suite.
      1871 tests in 202 suites passed.
- [x] 7.4 `openspec validate add-inspection-overview --strict`, and `git diff --check`.

      `Change 'add-inspection-overview' is valid`; `git diff --check` clean.
## 8. Closing

- [x] 8.1 Post-review of the diff against `design.md`'s decisions and this change's own boundaries.
      Walked against `design.md`'s six decisions and this change's boundaries. Three production files changed by 71 lines; `AudioInspectorDomain`, `AudioInspectorAnalysis`, `AudioInspectorMedia` and `FeatureImport` have zero files changed.
- [x] 8.2 Update `CURRENT.md`.
      Overwritten as an R7 snapshot: what landed, the two findings, what could not be seen and why, the
      next step, and the two open questions.
- [ ] 8.3 **Post-merge only.** Record in the umbrella's task 3.6 what R7 landed, and carry the
      **ADR-0026 §7 is unreachable** finding to the umbrella's closure task 5.3.
      This was done pre-merge and **reverted**: §3.6 closes on merge, not on implementation, and 5.3 is
      another change's task — appending an R7 finding to it before R7 exists on `main` rewrites someone
      else's scope. The umbrella is back at **16/29**, byte-identical to `origin/main`. Until then the
      finding lives where it belongs: `proposal.md`'s first finding, `design.md` §2 and its Open
      Questions, and `CURRENT.md`.

- [ ] 8.4 **Post-merge only.** The administrative close: the PR, the merge, and
      `openspec archive add-inspection-overview`. R7 is not administratively closed before any of them
      exist.

**No push, no PR, no merge, no archive. R8 is not implemented here.**
