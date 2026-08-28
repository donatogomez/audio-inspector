# Implementation Tasks

**R3 of the redesign.** It gives the Details section its content — the technical properties, the file's
identity, the notes and the result — and changes none of it.

Boundaries this slice inherits: `ReportPropertyFormatter` and `PropertyDisplay` decide what each fact
says and which group it belongs to, and are not edited; `ImportFlowModel`, the drop, the picker, the
export, `schemaVersion` 1 and the one PCM read are untouched; R1's sections and selection are untouched;
R2's pre-inspection surface is untouched; the comparison keeps its place and its words.

## 1. The section

- [x] 1.1 A Details surface in `FeatureAnalysis` presenting the four bodies of content in one place:
      the technical properties in the report's own two groups, the file's identity, the notes, and the
      result — laid out per `design.md` §3's option C, with one label column and the result set apart.
      `ReportDetailsView` in `FeatureAnalysis`: one technical area with the report's two groups named
      inside it, the file's identity, the notes when there are any, and the result outside the card rhythm.
      One label column runs the length of the section, and a reading measure keeps a wide window adding
      space rather than line length.
- [x] 1.2 The composition root shows it when Details is selected and the existing report page otherwise.
      No stack, no split view, no sidebar, no second selection, and no change to R1's lifecycle.
      One branch in `RootView`, total and with **no default**, so a section added later must be routed
      rather than inheriting the page that stands in for the unfinished ones. The root chooses because it
      is the only place that can — `WorkspaceSection` lives there and `FeatureAnalysis` cannot see it. No
      stack, no split view, no sidebar, no second selection; `navigation.section` is read in exactly two
      places, the picker and this routing.
- [x] 1.3 **One visible owner.** While Details is selected the five blocks it presents appear nowhere
      else on screen; asserted, not argued.
      Details and the legacy page are the two arms of one `switch`, so they are alternatives and never
      both. Each is *built* exactly once in the whole root, asserted with declarations excluded.

## 2. Nothing lost in the move

- [x] 2.1 Every property the report produces appears exactly once, with its value, its unit, its
      certainty state and its detail — asserted against `ReportPropertyFormatter`, so the section cannot
      drift from the report.
      Asserted against `ReportPropertyFormatter` rather than retyped: for a report exercising every
      state, the grouped rows are exactly `displays(for:)`'s rows, none dropped, none duplicated, and
      each **equal** to the row the formatter produced.
- [x] 2.2 The report's own grouping is rendered, not re-decided: every property lands in the group
      `groups(for:)` assigns it, and no property is dropped or moved.
      The section calls `groups(for:)` and never reaches for a property by name — asserted over six of
      them — so it cannot pick, reorder or omit one.
- [x] 2.3 **Absence is not zero and a failure is not an absence** — the five presentation states keep
      their own words, and the two that carry a symbol keep their label beside it.
      The five states keep their own distinct words; a symbol never appears without its label; only a
      failure of the *reading* is coloured. The section's substitute for a missing value is a dash, and
      five ways of substituting a figure are refused.
- [x] 2.4 The file's identity is presented, and **no path, URL, parent directory or bookmark** appears —
      asserted over everything the section can render.
      The four identity facts are presented and the source keeps its existing sentence. Seven location
      symbols are refused **and** every string literal is swept for the shape of a path — see 3.1, which
      is why the second half exists.
- [x] 2.5 Notes keep their words and states, are absent entirely when there are none, and are neither
      counted, scored nor ranked.
      Notes keep their words and states, the area exists only when there is something in it, and seven
      ways of counting, scoring or ranking them are refused.
- [x] 2.6 The result is the report's own sentence, set apart from the properties, and states no verdict,
      score, grade, quality or provenance.
      The result is `outcome(for:properties:)`'s own sentence, rendered outside any `ReportSection` —
      asserted by reading the block — and twenty-four verdict, score and provenance terms are swept over
      every string the section can produce, for two reports.
- [x] 2.7 **No progressive disclosure**, and the reason recorded rather than the disclosure added for
      its own sake (`design.md` §4).
      Nothing is collapsed, and six ways of hiding content are refused. The reason is `design.md` §4:
      the only candidate is `PropertyDisplay.detail`, which conflates the exact figure with the reason an
      unreliable reading carries, and splitting it touches a type R4's surfaces will share.

## 3. Negative controls

Each: clean state, checksum, one mutation, the named victim, revert, checksum again.

- [x] 3.1 **A path would be caught.** Render a location on the section temporarily and demonstrate 2.4
      fails; revert.
      **Seen to fail — and the first run is the useful one.** A literal path rendered beside the source
      **passed**: the guard refused location *symbols* and not a location *written out*. The guard was
      widened to sweep every string literal for the shape of a path, and the same mutation then failed
      with 2 issues naming `/` and `Users`. Reverted, checksum verified.
- [x] 3.2 **An absence shown as zero would be caught.** Substitute a figure for an absent value
      temporarily and demonstrate 2.3 fails; revert.
      **Seen to fail with 2 issues**: the dash the section substitutes was gone, and `?? "0"` was named
      by the refusal list. Reverted, checksum verified.
- [x] 3.3 **A strengthened result would be caught.** Add a quality claim to the result temporarily and
      demonstrate 2.6 fails; revert.
      `Text("Result — good quality")`. **Seen to fail with 4 issues across 3 tests**: the area's heading,
      the result's own block, and the verdict sweep twice — on `good` and on `quality`, independently.
      Reverted, checksum verified.
- [x] 3.4 **Duplication would be caught.** Present the legacy blocks beside Details temporarily and
      demonstrate 1.3 fails; revert.
      The legacy page rendered beside Details in the same branch. **Seen to fail with 1 issue** naming
      the second build site. Reverted, checksum verified.

## 4. What must still be true afterwards

- [x] 4.1 R1 is untouched: five sections, the selection moved only by what already moves it, and its
      suites pass unmodified.
      Five sections, in order; the selection rule applied in exactly one place and still moved only by
      `PrimaryInspection`; R1's suites pass unmodified.
- [x] 4.2 R2 is untouched: the pre-inspection surface and its suites pass unmodified.
      R2's suites pass unmodified; the pre-inspection surface is not touched by this slice.
- [x] 4.3 The comparison is untouched — same place, same words, same semantics — and does not move into
      Details.
      The comparison stays in the legacy page, in the same call, with the same presentation and the same
      export action beside it — asserted. It does not move into Details, and R8 is where it becomes a mode.
- [x] 4.4 The export, its DTOs, its mapper and `schemaVersion` 1 are unchanged.
      **0 files** of the export, its DTOs, its mapper, `ExportableMeasurements`, `ReportMeasurements` or
      the JSON schema documentation are touched, and the section names none of them.
- [x] 4.5 No analysis is added and no PCM read or recomputation is caused: this slice presents what the
      report already holds.
      **0 files** in the domain, the analysis target, the media adapter or `FeatureImport`. The section
      names no decoding, no sample type and no analysis: it renders what the report already holds.
- [x] 4.6 R4–R9 are not started: no measurement, waveform, spectrum, overview or comparison-mode surface.
      The section names no measurement, waveform, spectrum, overview or comparison type — asserted — and
      the other four sections still show the page they showed before.

## 5. Gates

- [x] 5.1 Four gates green — boundaries, `swift build -Xswiftc -warnings-as-errors`, `swift test` twice,
      `openspec validate --all --strict` — plus the Xcode macOS build and `git diff --check`.
      All green; the figures are in the final report.
- [x] 5.2 A focused run over this slice's suites, and the full suite with no existing test weakened.
      Two suites of this slice's own, 18 tests, and the full suite green twice. **No existing test is
      modified**: `git diff --name-only main..HEAD -- Tests` lists only files this slice created.

## 6. Closure

- [x] 6.1 Merged on its own small PR, `main` green.
      PR [#54](https://github.com/donatogomez/audio-inspector/pull/54), merged 2026-08-28 as the
      **two-parent merge commit `8d5d01f`** — 4 commits, 11 files, +1227/−13. Integration proved six ways
      rather than taken from the label: the PR reports `MERGED` with a non-null `mergedAt`; the commit has
      exactly two parents, `04ea212` and `f73218c`; the second parent **is** the feature head; the merge's
      tree is byte-identical to the feature head's (`e72ca7be…`), so the merge resolved nothing and added
      nothing of its own; `origin/main` **is** the merge commit; and the feature has **0** commits outside
      it. `main` green after: 1757 tests in 193 suites, twice, plus boundaries, warnings-as-errors, the
      Xcode build, `openspec validate --all --strict` and `git diff --check`.
- [x] 6.2 `CURRENT.md` refreshed and `restructure-inspection-workspace` §3.2 marked — after merge.
      Both done after the merge, in that order. The umbrella's §3.2 records what landed and what it did
      not cost, and its counter moves **12/29 → 13/29**; §3.3–§3.8 — R4 through R9 — are untouched,
      asserted. `CURRENT.md` names the PR, the merge commit, the archive path, the umbrella count and the
      next slice, and claims no validation that was not performed.
- [x] 6.3 Archive through `openspec archive` **after merge**.
      Archived as `openspec/changes/archive/2026-08-28-restructure-report-details/`, after the merge,
      after `main` was fast-forwarded to it, and after the post-merge baseline was green.
      **The canonical capability was audited rather than assumed.** `audio-file-inspection` went from
      **12 requirements / 49 scenarios to 17 / 62** — exactly this change's delta of five requirements and
      thirteen scenarios, no more — and the update is a **single appending hunk**: 127 lines added, **0
      removed**, so all twelve existing requirements and all 452 preceding lines survive byte-identical,
      and there is no duplicate heading. The **other eight capabilities are byte-identical**, compared by
      SHA-1 before and after.

## 7. Deferred, and named so it is not quietly dropped

- [ ] 7.1 **Splitting `PropertyDisplay.detail`** into the exact figure and the reason, so the first could
      be collapsed. It touches a type R4's surfaces will share.
- [ ] 7.2 **Moving the export action into Details** (ADR-0026 §10), once the sections it would leave are
      real.
- [ ] 7.3 **The full accessibility and responsive passes** — R9.
