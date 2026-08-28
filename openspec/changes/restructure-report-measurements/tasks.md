# Tasks — R4, the Measurements section

Large tasks on purpose. This slice is one coherent unit of work and closes in one pass; the earlier
slices' habit of forty micro-groups bought nothing but bookkeeping.

## 1. The presentation seam

- [ ] 1.1 A pure `MeasurementsDisplay` derivation from the four presentations to groups → measurements →
      rows, with **every string taken from `SignalLevelMetricsCopy`, `TruePeakCopy`, `LoudnessCopy` and
      `ProgrammeBandwidthCopy`**. No domain value read, no value formatted, no state held, no copy
      re-written. The only new strings are the two group names and the disclosure label, and none of
      them names a magnitude.
- [ ] 1.2 The bandwidth's "measurement carrying no reading" resolves to the absence sentence its copy
      owner already produces, so the surface can never render an empty measurement.

## 2. The surface

- [ ] 2.1 `ReportMeasurementsView`: two named groups, one label column running the length of the
      section, the four measurements in the report's existing order, a single scroll and a reading
      measure — the shape `ReportDetailsView` established.
- [ ] 2.2 Values, units, per-channel details, absence and failure sentences, and the analysis resolution
      are **always visible**. Only a failure of the reading is read at full weight, and nothing is
      coloured by what a value contains.
- [ ] 2.3 Each method sentence sits behind a per-measurement disclosure labelled with the phrase the
      existing accessibility labels already use, and remains reachable by an assistive reader.
- [ ] 2.4 Each row is one coherent accessible element carrying its name, value, unit and detail; the
      group and measurement names are headings.

## 3. Routing and the transitional page

- [ ] 3.1 `WorkspaceSection.measurements` gets its own branch of the existing switch. Overview, Waveform
      and Spectrum keep the transitional report page unchanged — including the comparison it carries and
      the export in its toolbar — and the branches stay alternatives, so the four measurement blocks and
      this section can never be on screen together.
- [ ] 3.2 No section is added or removed, the selection stays where R1 owns it, and no navigation
      machinery is introduced.

## 4. Tests

- [ ] 4.1 **Facts preserved, asserted against the copy owners rather than retyped**: the four families
      are all present and each exactly once; every value, unit, per-channel breakdown and rounding is
      the one the copy owner produces; the analysis resolution is present as its own row.
- [ ] 4.2 **States**: loading, value, absent, failed and the bandwidth's no-reading case are each
      distinguishable; absence is never zero, a failure is never a silent absence, and the clipped-sample
      count stays a defined number beside values that are not computable.
- [ ] 4.3 **Method disclosure**: every recorded method reaches the surface, and no value, unit, detail,
      absence, failure or resolution is behind the disclosure.
- [ ] 4.4 **Vocabulary sweep** over every string the section can render in every state: no judgement, no
      threshold, no target, no provenance, no aggregate, and no difference.
- [ ] 4.5 **Routing and isolation**: selecting Measurements shows this surface; Details still shows
      Details; the legacy page still carries the comparison unchanged; the sections are still five; the
      one rule that moves the reader is unchanged; the export, the JSON contract and the one-read
      invariant are untouched.

## 5. Negative controls

- [ ] 5.1 Six mutations, one at a time, each committed against and reverted by checksum: absence
      rendered as zero; a unit corrupted; a judgement word added; an illegal difference published; an
      aggregate rendered; the new section and the legacy measurement blocks shown together. Each must
      fail a test that already exists.

## 6. Gates

- [ ] 6.1 Boundaries, warnings-as-errors, the full suite twice, the Xcode build, OpenSpec strict, and
      `git diff --check` — plus a style comparison of the touched files against `main`.

## 7. Closure — after merge

- [ ] 7.1 Merged on its own small PR, `main` green.
- [ ] 7.2 `CURRENT.md` refreshed and `restructure-inspection-workspace` §3.3 marked — after merge.
- [ ] 7.3 Archive through `openspec archive` **after merge**.

## 8. Deferred, and named so it is not quietly dropped

- [ ] 8.1 **A comparison surface for the measurements** — R8. This slice presents the primary file's
      measurements only, exactly as R3's Details presents the primary file's properties only.
- [ ] 8.2 **Splitting `PropertyDisplay.detail`** — R3's 7.1, and **not R4's**: the measurements have
      their own row types and touch that type nowhere (`design.md` §5). Its owner is whichever slice next
      reworks Details or the comparison.
- [ ] 8.3 **The full accessibility and responsive passes** — R9.
