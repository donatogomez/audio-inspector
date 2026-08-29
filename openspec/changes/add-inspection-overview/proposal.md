## Why

**Overview is the last section still showing the transitional report page.** R1 created five sections;
R3, R4, R5 and R6 gave four of them content of their own. Selecting **Overview** still shows the whole
scrolling page the redesign exists to replace — so the section that ADR-0026 §1 makes the *entry point*
is the only one that is still the *old page*, and a reader who arrives at a fresh inspection lands
exactly where the redesign started.

This is R7 of `restructure-inspection-workspace` (task 3.6). It is late by design: `design.md` §2 states
that an Overview can only reuse what the other sections already have a home for, and all four of those
homes now exist.

## What Changes

- **A new Inspection Overview**, shown when `.overview` is selected and the window is inspecting **one**
  file. Its content is ADR-0026 §6's permitted list and nothing else: the file's identity, the core
  technical facts, the inspection's own result state, the key measurements in the words already fixed,
  and a **compact waveform** reusing the envelope the inspection already produced.
- **The warning count is refused**, and it is the one element of §6 this change does not build — see
  *Two findings* below. §6 marks it *"yes, under §7"*, and §7 ends *"if any of the three cannot be held,
  the count goes and the section title carries the reader instead."* That is what happens here, on a
  ground §7 did not anticipate.
- **The transitional report page survives in exactly one place**: `.overview` while a comparison is
  settled. `ComparisonView` renders only inside `ReportView`, and `legacyReportSurface` has exactly one
  caller — `case .overview`. Replacing that branch unconditionally would delete the comparison from the
  application until R8. It is kept, unchanged, in comparison mode only.
- **After this change, all five sections are real in inspection mode.** The only surviving dependency on
  the legacy `ReportView` is the comparison transition, which R8 removes.

**No BREAKING change.** No exported document, no schema, no domain type, no measurement and no drawing
changes. Nothing is read, decoded, measured or recomputed to draw this section.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `audio-file-inspection`: new presentation requirements for the inspection overview — what it may
  contain, that it re-states facts without changing or deriving from them, that it introduces no
  judgement, no aggregate and no inference, and that giving it content computes nothing and moves no
  reader.

**Not `inspection-workspace-navigation`.** `design.md` §2 left R7's delta target open between that
capability and one of its own. It is neither: `openspec/specs/` has no
`inspection-workspace-navigation` — the capability exists only as a delta inside
`restructure-inspection-workspace`, which is not archived. R2, R3, R4, R5 and R6 each wrote against
`audio-file-inspection`, and R7 follows that precedent rather than writing against a spec that is not
yet canonical.

## Impact

**Production**

- `Sources/AudioInspectorApp/RootView.swift` — the `.overview` branch stops being unconditional:
  the new section in inspection mode, `legacyReportSurface` retained for comparison mode.
- `Sources/FeatureAnalysis/` — one new view for the overview, built from the presentations `RootView`
  already constructs in the same body.

**Untouched, and asserted rather than intended**

`AudioInspectorDomain`, `AudioInspectorAnalysis`, `AudioInspectorMedia` and `FeatureImport`; the export
and `schemaVersion` 1; `ComparisonView`, `ComparisonPresentation` and every comparison semantic; the four
measurement presentations; `WaveformEnvelope`, `WaveformGeometry` and the drawing's absolute amplitude;
the one PCM read per inspection; `WorkspaceSection`, `WorkspaceNavigation` and every navigation rule R1
pinned; and R2's pre-inspection surface, R3's Details, R4's Measurements, R5's Waveform and R6's
Spectrum.

## Two findings, on the record

**1. The warning count collides with a shipped requirement, not with §7's three conditions.** §7's three
conditions all survive on their own terms: `InspectionReport.warnings` is a list the report already
carries, Details opens it, it would be stated about one file only, and it can be rendered without colour,
threshold or comparative wording. What it does not survive is R3's own ADDED requirement, now canonical
in `audio-file-inspection` — *"Keep notes and the result apart from the facts"* — whose second sentence is
unqualified:

> A note MUST NOT be counted, scored, ranked by severity, or summarised into a total.

A cardinality is a total, the surface calls warnings **Notes**, and that requirement shipped on
2026-08-28, *after* ADR-0026 was written on 2026-08-27 — so it is the later word, it is canonical, and
ADR-0026 is still `Proposed`. `design.md` §3 forbids retiring a semantic assertion by calling it legacy,
and ADR-0026's own header inherits refusals it *must not weaken*. Specialising the requirement by a
delta — the manoeuvre §8 used against `audio-two-file-comparison` — was available and is declined: §8
specialised a rule it was *strengthening*, and this would specialise one in order to be allowed an
exception to it. **The count goes**, exactly as §7's own last line provides, and the section title
carries the reader to Details instead.

**2. Overview is load-bearing for the comparison.** `legacyReportSurface` has one caller and
`ComparisonView` has one host. This is not a discovery about the comparison; it is a discovery about the
order the slices were sequenced in — R7 is the last transitional branch, so it is the slice where the
comparison would silently fall out of the application. Keeping the transitional page in comparison mode
is the precedent R3, R4, R5 and R6 each set: *the comparison stays whole, where it is, until R8.*
