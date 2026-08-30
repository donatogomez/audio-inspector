# Design — comparison as a mode, and the page that finally goes

## Context

R8 of `restructure-inspection-workspace` (task 3.7). ADR-0026 §2 and §3 already decided the shape; this
slice implements it and removes the last of the page it replaces.

**Everything R8 presents already exists.** The comparison's semantics were built by
`add-two-file-technical-comparison` and `add-two-file-measurement-comparison`, its paired drawings by
`add-two-file-visual-comparison`. Three formatters own the whole of it:

| Value | Owner | What it produces |
| --- | --- | --- |
| technical rows | `ComparisonFormatter.rows(for:)` | 9 `ComparisonRowDisplay` — name, both `PropertyDisplay`s, outcome |
| measurement blocks | `MeasurementComparisonFormatter.blocks(for:)` | 4 `MeasurementBlockDisplay` — rows, outcomes, the one LU difference, precision and channel notes |
| paired drawings | `RootView.reportVisuals(for:in:)` | `ReportVisuals.paired` — shared axes, absolute scales, one legend |

**So R8 is a re-composition, not a redesign.** Its whole risk is in *where* those values are read and in
what a surface might say around them.

**The lifecycle is R1's and does not change.** `ImportFlowModel.ComparisonState` has four cases;
`comparisonPresentation(for:)` maps them; `WorkspaceNavigation` moves the reader only for a new
successful primary. R8 adds no state, no mode enum, no persistence.

## Goals / Non-Goals

**Goals**

- The same five sections work in comparison mode, each presenting the comparison its own content is
  about.
- A Comparison Overview that is ADR-0026 §8 exactly, and that cannot publish an aggregate by presence or
  by absence.
- `legacyReportSurface`, `ReportView` and `ComparisonSection` gone, on proof rather than assumption.
- `warningSummary` deleted rather than migrated.

**Non-Goals**

- No new section, no `Comparison` section, no second navigation, no mode persisted anywhere.
- No change to any comparison or measurement semantic: what is comparable, what a difference may be
  published for, and how bandwidth is compared are the domain's, untouched.
- No change to the paired drawings.
- No comparison export, no `schemaVersion` 2, no `Codable` on any paired value.
- No toolbar redesign and no new control. R9 owns polish.

## Decisions

### 1. Each section reads the comparison; the root decides nothing about content

`RootView` already binds `flow.comparison` once per body and derives both the comparison presentation and
the visuals from that one read. R8 keeps exactly that and hands each section what it needs:

```
.overview      → comparison == .none ? InspectionOverviewView : ComparisonOverviewView
.details       → ReportDetailsView(report:comparison:)          — nil in inspection mode
.measurements  → ReportMeasurementsView(…, comparison:)         — nil in inspection mode
.waveform      → ReportWaveformView(visuals:)                   — unchanged, already paired
.spectrum      → ReportSpectrumView(visuals:)                   — unchanged, already paired
```

*Alternative considered:* a `WorkspaceMode` value beside `WorkspaceSection`. Declined — ADR-0026 §4 says
the selected section is the only presentation state the composition root owns, and a mode enum would be a
second one that could disagree with the flow it is derived from. The comparison state **is** the mode;
deriving it twice is what creates drift.

### 2. Overview is a different view, not a mode of the same one

`InspectionOverviewView` and `ComparisonOverviewView` are separate types. §8's list is short and its
prohibitions are absolute, and a single view with a comparison branch would put the two lists one `if`
apart — where a later slice adds a measurement to "the overview" and reaches the comparison one by
accident. **Two types make §8's list a property of a type rather than of a branch.**

### 3. What the Comparison Overview contains, exhaustively

| Element | Source | Present |
| --- | --- | --- |
| the first file's identity — name, extension, size, modified date, source | `comparison.first.file` | **yes** |
| the second file's identity — the same five | `comparison.second.file` | **yes** |
| the existing factual framing | `ComparisonCopy.subtitle`, `.contextTitle`, `.contextDetail` | **yes** |
| anything else | — | **no** |

**No Notes, no warning count, no Result, no technical facts, no measurements, no outcome of any kind.**
The two identities are presented as two peers under `ComparisonCopy.firstFile` / `.secondFile`, and the
framing says the sections carry both files. A reader who wants the comparison selects the section that
holds it — which is the navigation ADR-0026 §8 permits, and the only one this surface offers.

**Why the technical context block does not come along.** The legacy page carried extension, size,
inspection status and a warning count "for context, not compared". The first two are already in each
identity; the third is a Result, which §8 forbids comparing and which R8 does not compare; the fourth is
the count this project has already refused twice. So the block's *content* is either redundant or
prohibited, while its *framing sentence* — the one that says why some facts are shown and not compared —
survives, because it is what stops the identities reading as a comparison.

### 4. The all-agree case decides the shape, not the wording

The prohibition is not a word list. `audio-two-file-comparison` refuses *"no single value, flag or phrase
meaning the two files match"*, and ADR-0026 §8 extended that to an **absence** carrying the same
statement. The design answer is structural: **the Comparison Overview renders the same elements, in the
same order, for every pair.** Nothing on it is conditional on any outcome, so there is no element whose
appearance or disappearance could mean anything, and the all-agree render is byte-identical in structure
to a render of two entirely different files.

That is testable directly, and it is R8's gate: the surface's rendered strings for an all-agree pair and
for a maximally-different pair differ **only** where the two files' own facts differ.

### 5. Measurements and Details present comparisons in place

**Not a block appended at the end** — that is the shape being removed. Each section presents the
comparison of the thing it is already about:

- **Measurements** renders `MeasurementComparisonFormatter.blocks(for:)` in the section's own two named
  groups, so the four measurements sit where they sit in inspection mode. The one LU difference stays on
  the loudness row; no other row gains a difference column it could never use.
- **Details** renders `ComparisonFormatter.rows(for:)` for the technical properties, each file's identity,
  and each file's Notes **as words, per file, never counted**. The Result of each reading is presented per
  file where the section already presents it, and **the two are never compared** — there is no outcome for
  a Result, and inventing one would be a verdict about the reading rather than about the audio.

**Composition, of three considered.** *(A)* side-by-side columns with an outcome column — what the legacy
page does; *(B)* stacked First/Second per row; *(C)* adaptive. **A is chosen**, because the outcome it
shows is a fact the domain already decided per row, its shapes are exactly the ones
`MeasurementComparisonPresentationTests` and `ComparisonPropertyCoverageTests` already pin, and B would
re-lay-out values whose row identity those suites assert. A four-column table is only a scoreboard if
something totals it; nothing does, and the sweep proves it. At the minimum window the compared grid
scrolls horizontally inside its section — the product decision this change was given — rather than
shrinking values to illegibility.

### 6. `warningSummary` is deleted

Two callers, both inside `ComparisonSection.contextBlock`; no test; and its output — *"1 warning on this
file"* — is a cardinality over notes, which `audio-file-inspection` forbids without qualification. It
dies with the view. **The information is not lost**: Details presents each file's notes in the words the
report gives them, which is strictly more than a count ever said.

### 7. Loading and failure are contextual, and stated once

A comparison that is loading or failed is a fact about **the second file**, not about the section a reader
happens to be in. Each section states it where its own content would be: Overview beneath the second
identity, Measurements and Details in place of the second column's values, Waveform and Spectrum by
continuing to draw the first file alone — which is what `reportVisuals(for:in:)` already does, since a
pair that has not settled is not a pair.

**No section invents a second value.** No zero, no placeholder, no dash standing for a number.

## Risks / Trade-offs

- **An aggregate arrives by absence** → §4's structural answer plus an explicit all-agree/all-differ
  differential test, and a negative control for each of the five shapes an aggregate takes.
- **A count of notes comes back** → `warningSummary` deleted, and a sweep over every R8 surface for a
  cardinality of notes, with a negative control.
- **Removing `ReportView` takes something still used** → a call-site audit before deletion, and the
  export is already out of it (PR #59), which is what makes the deletion possible at all.
- **The comparison's semantics drift while being re-homed** → nothing is re-derived; the three formatters
  are called and their outputs rendered, asserted by the suites that already pin their shapes.
- **A section navigates or the reader moves** → R1's lifecycle suites run unchanged over all five
  sections and all comparison states.

## Open Questions

None. The Comparison Overview's content was settled by ADR-0026 §8 and restated as a closed decision for
this slice; `warningSummary`'s resolution was settled by the canonical requirement that post-dates it.
