# Design — the Inspection Overview, and the one branch it may not delete

## Context

R7 of `restructure-inspection-workspace` (task 3.6). ADR-0026 §1 makes **Overview** the entry point of a
window whose subject is one file; §6 fixes exactly what it may contain and §7 argues the one derived
element on that list. Everything the Overview presents already has an owner: `ReportPropertyFormatter`
for the properties, the identity and the outcome; the four measurement copy owners for the figures;
`WaveformEnvelope` for the drawing. This slice arranges them. It decides nothing about a file.

**Current state, verified rather than assumed.** `RootView`'s `.overview` branch calls
`legacyReportSurface`, which is that function's **only** caller; `ComparisonView` is constructed **only**
inside `ReportView`. So the transitional page is not merely still visible under Overview — it is the
sole host of the comparison.

**The four sections that precede it are unchanged**, and this slice reads their seams rather than their
views: `MeasurementsDisplay.display(for:)` for the measurement figures, `ReportPropertyFormatter` for the
facts, and `RootView.waveformPresentation(for:)` for the drawing.

## Goals / Non-Goals

**Goals**

- Overview shows the file's own entry surface when the window is inspecting **one** file: identity, core
  technical facts, key measurements, a compact waveform, and what became of the reading.
- Every fact on it is a value some other owner already produced, taken through the same function the
  other surfaces take it through, so two surfaces cannot disagree.
- The comparison keeps working, unchanged, until R8 owns it.
- After this slice, the five sections are all real in inspection mode.

**Non-Goals**

- **The Comparison Overview (ADR-0026 §8) is not built here.** It is R8's, gated by a vocabulary sweep
  R7 does not run. No comparison value is redistributed, re-worded, re-placed or re-derived.
- No plain-language summary, no score, grade, rating or quality claim, no statement about origin, master,
  remaster, transcode, upsample or bitrate, no judgement of any figure, and no aggregate.
- No second PCM read, no re-decode, no recomputation, no alternative reduced source for the drawing.
- No new navigation affordance out of content. The section control R1 built is still the only way between
  sections.
- No change to the export, `schemaVersion` 1, the domain, the media adapter or the analyses.

## Decisions

### 1. The delta is written against `audio-file-inspection`

`design.md` §2 of the umbrella left R7's target open between `inspection-workspace-navigation` and a
capability of its own. **It is neither.** `openspec/specs/` contains no
`inspection-workspace-navigation`: that capability exists only as a delta inside the umbrella change,
which is open and unarchived, so there is nothing canonical to modify. R2–R6 each wrote against
`audio-file-inspection` for the same reason. *Alternative considered:* creating
`inspection-overview` as a capability of its own — declined, because it would split one surface's
presentation rules across two capabilities on no boundary anyone could state later.

### 2. The warning count is refused, and the ground is R3's shipped requirement — not §7

§7's three conditions each hold on their own terms. `audio-file-inspection`'s **Keep notes and the result
apart from the facts** does not permit them to matter:

> A note MUST NOT be counted, scored, ranked by severity, or summarised into a total.

That sentence carries no section qualifier, the surface calls warnings **Notes**, a cardinality is a
total, and it became canonical on 2026-08-28 — *after* ADR-0026 was written on 2026-08-27. A `Proposed`
record does not overrule a shipped capability, and the umbrella's own `design.md` §3 forbids retiring a
semantic assertion by calling it legacy.

*Alternative considered and declined:* a **MODIFIED** delta specialising that requirement, the manoeuvre
ADR-0026 §8 used against `audio-two-file-comparison`. §8 specialised a rule in the direction of
**refusing more**; this would specialise one in order to be allowed an exception to it, which is the
shape of weakening whatever it is called.

ADR-0026 §7 provides for this outcome itself — *"if any of the three cannot be held, the count goes and
the section title carries the reader instead"* — so the Overview states no count, and **Details** remains
the place notes are read, reached by its own section control.

**Consequence for the ADR.** §7 is not wrong; it is unreachable. That belongs in the umbrella's closure
task 5.3, where ADR-0026's status is decided, and this change records it rather than editing the ADR.

### 3. Overview is two surfaces behind one branch, split on the comparison alone

```
case .overview:
    switch ComparisonPresentation.for(comparison)
      .none                         → InspectionOverviewView   (new, this slice)
      .loading | .ready | .failed   → legacyReportSurface(…)   (unchanged, until R8)
```

The split is on `ComparisonPresentation`, not on `ReportVisuals`, and that distinction is the point:
`ReportVisuals` is `.paired` only once **both** files have settled both drawings, while the comparison
surface renders for `loading` and `failed` too. Splitting on the visuals would have deleted the
comparison's loading and failure states from the application. It is derived from the **same single read**
of `flow.comparison` the body already binds, so the two branches cannot straddle a change.

*Alternative considered:* hosting `ComparisonView` directly from the `.overview` branch and dropping
`ReportView`. Declined — it decides where the comparison lives, which is exactly R8's question, and it
would move the comparison twice.

### 4. What the Overview presents, and where each part comes from

| Block | Source, unchanged | ADR-0026 §6 |
| --- | --- | --- |
| the file's identity — name, extension, size, modified date, source | `report.file`, `HumanFormat`, the same sentence Details uses | permitted |
| core technical facts — container, codec, rate, depth, channels, duration | `ReportPropertyFormatter.coreFacts(for:)`, new, selecting §6's six from the formatter's own rows | permitted |
| key measurements | `MeasurementsDisplay.display(for:)`, one per measurement | permitted |
| a compact waveform | `RootView.waveformPresentation(for:)` → the existing `WaveformEnvelope` | permitted |
| what became of the reading | `ReportPropertyFormatter.outcome(for:properties:)` | permitted |
| the number of warnings | — | **refused, §2 above** |

**"Key" is not an editorial choice.** Each measurement contributes the **first** row its own copy owner
produces, and its state sentence when it produces no rows. The order is the copy owner's, the words are
the copy owner's, and this slice takes a prefix rather than picking a favourite. Per-channel breakdowns
and method sentences stay in Measurements, where R4 put them.

**The selection lives with the formatter, not with the view.** §6's six facts are not a group boundary:
`groups(for:)` puts Container, Codec and Duration in *Format* and six more in *Encoding*, of which §6
wants three. Rendering both groups whole would make the Overview a second Details; picking three out of
*Encoding* inside the view would put property meaning in a view. So the selection becomes
`ReportPropertyFormatter.coreFacts(for:)`, beside `groups(for:)` and `summary(for:)`, which already name
properties because naming them is what that type is for. The view names none, and every row keeps the
`PropertyDisplay` state — so a fact the file does not carry is **words on the Overview**, not an omission.

*Alternative considered:* reusing the existing `summary(for:)`. Declined — it is the transitional report
page's header, in use and pinned by tests; it drops a fact that was not read rather than stating it, and
it omits bit depth, which §6 names. Widening it would change a shipped surface this slice does not own.

### 5. The compact waveform is a sizing, and nothing else

A new `WaveformPlotSizing.overviewCompact` — a **fixed** strip, like `reportPage`, because the Overview is
a reading surface where the drawing is one block among five rather than the subject. It is smaller than
`reportPage`'s 96 pt, which is what makes it *compact*; the workspace sizings stay untouched.

It is handed the **same** `WaveformPresentation` the Waveform section is handed, so the same four states
— loading, envelope, absent, failed — are the same four here, in `WaveformCopy`'s own words. No
normalisation, no alternative reduced envelope, no re-bucketing, no second read, and
`allowsHitTesting(false)` as everywhere else: **it is informative, and it is not a control.**

### 6. Nothing on the Overview navigates

ADR-0026 §6 gives exactly one element a navigational role — the warning count, *"as a way in to
Details"* — and §2 above refuses that element. With it gone, no content on this surface is a control, and
the section navigation R1 built is the only way between sections. This is asserted, not merely intended:
no block carries a gesture, a button, or a hit-testable drawing.

## Risks / Trade-offs

- **The comparison quietly falls out of the app** → the split in §3 is driven by a total `switch` over
  `ComparisonPresentation` with no `default`, and a test drives all four comparison states through the
  `.overview` branch and asserts the comparison surface is still reached in three of them.
- **Two surfaces drift apart on the same fact** → nothing on the Overview reads a domain value directly;
  every block goes through the owner Details or Measurements goes through, asserted by a source sweep
  that refuses a property named by hand in the new file.
- **The Overview grows a verdict later** → the vocabulary sweep over every string this surface can render
  refuses judgement words, quality words, provenance words and aggregates, and a negative control proves
  the sweep bites.
- **The compact drawing invites interaction** → it is the same `WaveformDrawing` with a fixed sizing;
  a structural test asserts no gesture, no `Button` and no hit-testing reaches it.
- **A slice this late reintroduces a second read** → the existing decode counters cover it, and this
  change adds no decoding call site at all.

## Open Questions

None blocking. One recorded for the umbrella's closure task 5.3: **ADR-0026 §7 is unreachable as
written**, because the count it argues for is refused on a ground §7 does not consider. Whether §7 is
struck, narrowed to a hypothetical, or the shipped requirement is revisited, is a decision about the
ADR's status and belongs where that status is decided.
