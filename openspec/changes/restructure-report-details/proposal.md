# Give Details its content, and a hierarchy the old page could not have

## Why

R1 created five sections and a selection that moves between them. Four of them still show the whole
scrolling report, because the slices that fill them have not run. **Details is the first to be filled**,
and it is first for a reason: it is the only section whose content already exists as a coherent group —
ADR-0026 §10 defines it as *"what the other four do not"* — so it can be assembled without inventing a
single value.

What it assembles is today the tail of one long page: **Format**, **Encoding**, **File**, **Notes** and
**Result**, five stacked cards a reader reaches after scrolling past a waveform, a spectrogram and four
measurements. Three things are wrong with that, and none of them is a matter of taste:

1. **The grouping is invisible.** Format and Encoding are two halves of one idea — what the file *is*
   and how it is *encoded* — presented as two identical boxes among five, so the split reads as
   arbitrary rather than as meaning.
2. **Result looks like more data.** The one statement that is *about the reading rather than about the
   file* is styled exactly like the nine property rows above it, so it reads as a tenth fact.
3. **Nothing aligns.** Each card lays its labels out independently, so nine values in two groups sit at
   two different columns and the eye re-anchors at every box.

## What Changes

- **Details becomes a real section.** Selecting it in the workspace shows a surface of its own instead
  of the whole report page.
- **Format and Encoding become one technical area** with two named groups inside it, so the split is
  legible as a distinction rather than as two boxes.
- **File keeps its identity facts** — name, extension, size, modified date and the safe description of
  where it came from.
- **Notes keep their words and their states**, and stay absent when there are none.
- **Result is set apart** from the facts, because it is a statement about the reading and not another
  property of the file.
- **Labels and values align across the whole section**, so the reader's eye anchors once.

## What This Deliberately Does Not Do

- **No fact is added, removed, reworded or recomputed.** Every value, unit, absence, certainty state,
  note and outcome sentence is the one `ReportPropertyFormatter` already produces.
- **No progressive disclosure.** ADR-0026 §11 permits collapsing an explanation, and the only material
  here that could qualify is `PropertyDisplay.detail` — which conflates the exact figure behind a
  rounded value with the reason an unreliable reading carries. The type does not distinguish them, and
  splitting it is a change to the presentation model this slice's remit does not authorise. Named as a
  follow-up rather than done badly.
- **No path, URL, bookmark or parent directory.** The domain carries none, and the source keeps its
  existing sentence.
- **No verdict.** No score, no grade, no quality claim, no severity, no count of problems, and no
  statement about origin, master, remaster, transcode or upsample.
- **No other section is filled.** Overview (R7), Measurements (R4), Waveform (R5) and Spectrum (R6) keep
  showing the existing report page, unchanged.
- **No comparison change.** The comparison stays exactly where and what it is.
- **No export, `schemaVersion` or analysis change.** This slice reads nothing and computes nothing.

## Impact

- **Capability** — `audio-file-inspection` gains requirements about **where** the report's secondary
  content is presented and what that presentation may not lose. Its existing requirements are untouched:
  *Present the report in human terms* keeps every clause, and this change adds nothing that could weaken
  it.
- **Production** — a new `ReportDetailsView` in `FeatureAnalysis`, and one branch in `RootView` that
  shows it when Details is selected. **No change to** `ReportView`'s own content, `PropertyDisplay`,
  `ReportPropertyFormatter`, `ImportFlowModel`, the export, the domain, or anything R1 and R2 added.
- **No ADR.** ADR-0026 §10 already decides what Details holds and §11 already decides what may be
  collapsed. Layout is not an ADR's business.

## Dependencies

- **R1** for the section and the selection, and **R2** for the surface before a report. Both merged.
- Nothing else. R4–R9 are independent of this slice and are not started.
