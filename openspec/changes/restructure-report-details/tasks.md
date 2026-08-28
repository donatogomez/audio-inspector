# Implementation Tasks

**R3 of the redesign.** It gives the Details section its content — the technical properties, the file's
identity, the notes and the result — and changes none of it.

Boundaries this slice inherits: `ReportPropertyFormatter` and `PropertyDisplay` decide what each fact
says and which group it belongs to, and are not edited; `ImportFlowModel`, the drop, the picker, the
export, `schemaVersion` 1 and the one PCM read are untouched; R1's sections and selection are untouched;
R2's pre-inspection surface is untouched; the comparison keeps its place and its words.

## 1. The section

- [ ] 1.1 A Details surface in `FeatureAnalysis` presenting the four bodies of content in one place:
      the technical properties in the report's own two groups, the file's identity, the notes, and the
      result — laid out per `design.md` §3's option C, with one label column and the result set apart.
- [ ] 1.2 The composition root shows it when Details is selected and the existing report page otherwise.
      No stack, no split view, no sidebar, no second selection, and no change to R1's lifecycle.
- [ ] 1.3 **One visible owner.** While Details is selected the five blocks it presents appear nowhere
      else on screen; asserted, not argued.

## 2. Nothing lost in the move

- [ ] 2.1 Every property the report produces appears exactly once, with its value, its unit, its
      certainty state and its detail — asserted against `ReportPropertyFormatter`, so the section cannot
      drift from the report.
- [ ] 2.2 The report's own grouping is rendered, not re-decided: every property lands in the group
      `groups(for:)` assigns it, and no property is dropped or moved.
- [ ] 2.3 **Absence is not zero and a failure is not an absence** — the five presentation states keep
      their own words, and the two that carry a symbol keep their label beside it.
- [ ] 2.4 The file's identity is presented, and **no path, URL, parent directory or bookmark** appears —
      asserted over everything the section can render.
- [ ] 2.5 Notes keep their words and states, are absent entirely when there are none, and are neither
      counted, scored nor ranked.
- [ ] 2.6 The result is the report's own sentence, set apart from the properties, and states no verdict,
      score, grade, quality or provenance.
- [ ] 2.7 **No progressive disclosure**, and the reason recorded rather than the disclosure added for
      its own sake (`design.md` §4).

## 3. Negative controls

Each: clean state, checksum, one mutation, the named victim, revert, checksum again.

- [ ] 3.1 **A path would be caught.** Render a location on the section temporarily and demonstrate 2.4
      fails; revert.
- [ ] 3.2 **An absence shown as zero would be caught.** Substitute a figure for an absent value
      temporarily and demonstrate 2.3 fails; revert.
- [ ] 3.3 **A strengthened result would be caught.** Add a quality claim to the result temporarily and
      demonstrate 2.6 fails; revert.
- [ ] 3.4 **Duplication would be caught.** Present the legacy blocks beside Details temporarily and
      demonstrate 1.3 fails; revert.

## 4. What must still be true afterwards

- [ ] 4.1 R1 is untouched: five sections, the selection moved only by what already moves it, and its
      suites pass unmodified.
- [ ] 4.2 R2 is untouched: the pre-inspection surface and its suites pass unmodified.
- [ ] 4.3 The comparison is untouched — same place, same words, same semantics — and does not move into
      Details.
- [ ] 4.4 The export, its DTOs, its mapper and `schemaVersion` 1 are unchanged.
- [ ] 4.5 No analysis is added and no PCM read or recomputation is caused: this slice presents what the
      report already holds.
- [ ] 4.6 R4–R9 are not started: no measurement, waveform, spectrum, overview or comparison-mode surface.

## 5. Gates

- [ ] 5.1 Four gates green — boundaries, `swift build -Xswiftc -warnings-as-errors`, `swift test` twice,
      `openspec validate --all --strict` — plus the Xcode macOS build and `git diff --check`.
- [ ] 5.2 A focused run over this slice's suites, and the full suite with no existing test weakened.

## 6. Closure

- [ ] 6.1 Merged on its own small PR, `main` green.
- [ ] 6.2 `CURRENT.md` refreshed and `restructure-inspection-workspace` §3.2 marked — after merge.
- [ ] 6.3 Archive through `openspec archive` **after merge**.

## 7. Deferred, and named so it is not quietly dropped

- [ ] 7.1 **Splitting `PropertyDisplay.detail`** into the exact figure and the reason, so the first could
      be collapsed. It touches a type R4's surfaces will share.
- [ ] 7.2 **Moving the export action into Details** (ADR-0026 §10), once the sections it would leave are
      real.
- [ ] 7.3 **The full accessibility and responsive passes** — R9.
