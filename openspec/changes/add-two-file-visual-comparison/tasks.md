# Implementation Tasks

**Nothing is implemented.** Groups run in order: 1–3 build the contract and the lifecycle, 4–5 the
geometry, 6–7 the surface, 8–9 the evidence, 10 the two human checks ADR-0025's promotion depends on,
11 closure.

Boundaries no task may cross: no new PCM read and no recomputation of either artefact; `WaveformEnvelope`,
`Spectrogram`, `PCMStreamDescription`, `ReportMeasurements`, `MeasurementComparison`, `FileComparison`,
`InspectionReport`, the property reader and the JSON exporter are **not touched**; no visual artefact
enters `ReportMeasurements` or the export; `AVFoundation`/`AudioToolbox`/`Process` stay in
`AudioInspectorMedia` and Accelerate in `AudioInspectorAnalysis`; no `@unchecked Sendable`, no
`DispatchQueue`, no lock. The original files are never modified.

**Every task marked as a negative control must be demonstrated to fail** when the property it guards is
removed, and the removal reverted in full. A control that has never been seen to fail is a comment.

## 1. Contracts — the settled shapes, before any behaviour

- [ ] 1.1 A **per-file visual container** in `FeatureImport`: what became of the envelope, what became of
      the spectral model, and the `PCMStreamDescription` the read produced. A sibling of
      `ReportMeasurements`, **never a field of it** (ADR-0025 §3). `Sendable`, `Equatable`, not `Codable`.
- [ ] 1.2 A **settled pair** value carrying both files' containers, constructible only from two settled
      sides. `loading` and `cancelled` MUST be unrepresentable in it (ADR-0025 §5 and design §3).
- [ ] 1.3 Collapse lifecycle to settled **once, in `FeatureImport`**, for both sides, in the seam
      `SettledMeasurements.swift` already established: the first file's `…State` and the compared file's
      `…Outcome`. `cancelled` collapses to *not settled*; `unavailable` and `failed` stay **distinct**.
- [ ] 1.4 Assert the type refuses what the spec refuses: no pair from an unsettled side, absence and
      failure not interchangeable, and a zero-column model carried as its own answer rather than as an
      absence.
- [ ] 1.5 Confirm nothing in group 1 adds a field, a case or a conformance to any domain type.

## 2. Retention — stop discarding what the second file already produced

- [ ] 2.1 Retain the compared file's visual container where `analyses.settledMeasurements` is already
      taken, in `ImportFlowModel.settle(…)`. Nothing else about that method changes.
- [ ] 2.2 Take the primary file's side from the state it already holds in `InspectionPresentation`. **It
      is not re-retained** and not copied into the comparison's own storage (ADR-0025 §4).
- [ ] 2.3 Confirm the retained value is released by the same three events that already release
      `comparedMeasurements`: a comparison starting, a comparison dismissed, and a new primary inspection
      ending the comparison.
- [ ] 2.4 **Negative control — a second read would be caught.** Extend the counting harness
      `ComparisonMeasurementsReachTheComparisonTests` already uses so that a second `decode` call, or a
      second decoder, fails the suite. Demonstrate the failure by adding one temporarily, then revert.

## 3. The pair's lifecycle — atomic publication, staleness, cancellation

- [ ] 3.1 Publish the pair **only when both sides have settled**, in the shape
      `publishMeasurementComparisonIfBothSettled` already has, and in **one assignment** carrying both
      sides.
- [ ] 3.2 Structure the retained per-comparison payload so a visuals bundle **cannot** be paired with
      another operation's measurements or technical comparison — one merged value, or sibling fields
      cleared in lockstep. Whichever is chosen, prove the other combination is unrepresentable rather
      than merely untested.
- [ ] 3.3 **Superseded second file.** B in flight, user chooses C, B lands late: no pair containing B is
      ever published. Reuse `MeasurementComparisonAtomicityTests`'s handshake — a scripted action released
      step by step, **no sleep, no polling, no `Task.yield()`** — and give B and C **deliberately
      distinguishable** drawings so *"entirely C"* is observed rather than inferred from empty fields.
- [ ] 3.4 **Cancelled second inspection** publishes no pair, and no side is shown as absent, failed or
      empty because of it.
- [ ] 3.5 **Dismiss** and **new primary inspection** each clear the pair, and a result already in flight
      cannot land afterwards.
- [ ] 3.6 **A second file that could not be opened** leaves the comparison's failure exactly as it is
      today and publishes no pair.
- [ ] 3.7 **Negative control — stale would be caught.** Remove the operation guard and demonstrate that
      3.3 fails; revert.
- [ ] 3.8 **Negative control — two sources would be caught.** Build the pair from two independently read
      values in a temporary variant and demonstrate that 3.3 fails; revert.

## 4. Waveform — shared axes, computed as arithmetic and asserted without rendering

- [ ] 4.1 Shared time extent = `max` of the two files' `frameCount / sampleRate`, each from **that file's
      own** stream description. One function, outside the view, in the shape `WaveformGeometry` already
      has — *"every property worth guaranteeing here … is arithmetic that needs no rendering at all."*
- [ ] 4.2 Each side's drawn fraction = `its extent / the shared extent`; the longer file's is exactly `1`.
      Assert the equal-duration case, the second-shorter case and the first-shorter case.
- [ ] 4.3 The existing bucket→band arithmetic is reused **unchanged** inside each side's fraction. A
      resize re-runs geometry and nothing else.
- [ ] 4.4 Beyond a file's own extent: **no bar, no baseline, no substituted silent bucket**. Assert that
      the remainder yields no drawn value at all, and that `WaveformBucket.silent` is never introduced
      there.
- [ ] 4.5 Amplitude uses the existing fixed range for **both** lanes, with the clamp applied when drawing
      and only then. Assert both lanes are driven by the same range **as values**.
- [ ] 4.6 **Negative control — per-file normalisation would be caught.** Re-range one lane to its own peak
      temporarily and demonstrate 4.5 fails; revert.
- [ ] 4.7 **Negative control — a stretched lane would be caught.** Make the shorter file fill the axis
      temporarily and demonstrate 4.2 fails; revert.

## 5. Spectrogram — shared time, shared frequency, and the range that is not the floor

- [ ] 5.1 Time reuses group 4's shared extent, from the same source, so a waveform lane and a spectrogram
      lane cannot disagree about how long a file is. Assert it.
- [ ] 5.2 Shared frequency extent = `max` of the two Nyquists; each side's vertical fraction =
      `its nyquist / the shared nyquist`. Assert equal rates, 44.1 against 96, and **96 against 44.1** so
      the rule is not order-dependent.
- [ ] 5.3 Above a file's own Nyquist: **no cell**. Assert the region yields no drawn value, and that the
      axis is labelled to the **shared** Nyquist rather than to the lower one.
- [ ] 5.4 The out-of-range region is rendered **distinguishably from the ramp's floor colour**. Assert it
      as a value — the treatment used there is not the colour `SpectrogramColourRamp` produces at the
      floor — rather than by looking at a rendering. `SpectrogramColourRamp` itself is **not modified**.
- [ ] 5.5 Both lanes use the same ramp, the same floor and **one** legend describing both. Assert as
      values.
- [ ] 5.6 **Negative control — floor and out-of-range colliding would be caught.** Paint the out-of-range
      region with the floor colour temporarily and demonstrate 5.4 fails; revert.
- [ ] 5.7 **Negative control — cropping to the lower Nyquist would be caught.** Set the shared extent to
      `min` temporarily and demonstrate 5.2 and 5.3 fail; revert.
- [ ] 5.8 Confirm no raster is built at anything other than the model's own size, and that
      `SpectrogramRaster`'s no-interpolation rule still holds for both lanes.

## 6. Replacement — the paired drawings stand in for the single ones

- [ ] 6.1 With **no settled pair**, the report surface presents the first file's own envelope and spectral
      model exactly as it does today. This is the default, and it covers *not yet*, cancelled, dismissed,
      superseded and *second file failed* without a case for each.
- [ ] 6.2 With a **settled pair**, the paired sections are presented and the two single-file sections are
      not.
- [ ] 6.3 Assert the first file's envelope appears **exactly once** on the surface, and its spectral model
      exactly once — the property the product decision exists for (design §8).
- [ ] 6.4 Returning to the single drawings reads the values already held: **no file is read and no
      artefact is produced again**. Assert with the decode counter.
- [ ] 6.5 Assert the property rows, the technical comparison and the measurement comparison are all still
      presented, unchanged, while a pair is on screen.
- [ ] 6.6 The choice between the two presentations is a **total** mapping with no default case, in the
      shape `RootView`'s existing state mappings have.

## 7. Copy — absence, failure, out-of-range, and the words that are not allowed

- [ ] 7.1 Per side and per artefact: **absent**, **failed** and — for the spectral model — **too short to
      analyse** are three distinct statements. Reuse the sentences the single-file surfaces already use
      where they fit; do not invent a second vocabulary for the same fact.
- [ ] 7.2 A neutral failure sentence naming no path and no framework, as today.
- [ ] 7.3 Words for the two out-of-range regions: *this file has no audio beyond here* and *this file
      cannot represent this range*. They must be **different sentences**, because they are different
      facts, and a person has to be able to tell them apart in group 10.
- [ ] 7.4 One side's absence or failure never withholds the other side's drawing and never removes the
      shared axis.
- [ ] 7.5 Attribution is **first** and **second**, by position, reusing `ComparisonCopy`'s existing
      wording — never *original*, *copy*, *source* or *derived*.
- [ ] 7.6 **Negative control — forbidden vocabulary fails the suite.** A sweep over **every** string this
      surface can render, in every state, for the terms ADR-0025 §12 forbids. Demonstrate it fails by
      adding one temporarily; revert.
- [ ] 7.7 Accessibility: each drawing is one element labelled with the artefact and its file; the shared
      extents are available as text; nothing depends on colour alone.
- [ ] 7.8 **Differing channel counts produce no statement here.** Two files with different channel counts
      are drawn as they are, and nothing on this surface compares, reconciles or remarks on the counts —
      ADR-0024 §7 already compares them where a per-channel measurement exists.

## 8. Production reach — the pair really is what the inspection produced

- [ ] 8.1 Drive the **real** pipeline for two real files: real coordinator, real decoder, real
      accumulators. Assert **one decoder and one decode call per file**, with the pair retained.
- [ ] 8.2 Assert each side's envelope and spectral model in the pair are **equal** to the values that
      file's own inspection produced — reuse, not a lookalike.
- [ ] 8.3 **Negative control — recomputation would be caught.** Rebuild one artefact from a second pass
      temporarily and demonstrate 8.1 or 8.2 fails; revert.
- [ ] 8.4 The pair, the technical comparison and the measurement comparison on screen together all
      describe the same two inspections, over real files.
- [ ] 8.5 Confirm the report is still emitted before any sample is read, unchanged — the ordering the
      existing suites already pin.

## 9. Cost, boundaries and the export

- [ ] 9.1 Measure retained memory with and without a pair. Expected: **≈ 2.02 MiB more** while a pair is
      held (2 MiB model + 16 KiB envelope). Record what was measured rather than what was predicted, and
      state the machine and configuration.
- [ ] 9.2 Confirm **no PCM is retained** and no accumulator outlives its read.
- [ ] 9.3 Confirm at most **one** pair is retained, and that a new comparison releases the previous one.
- [ ] 9.4 Confirm at most **two** spectrogram rasters exist at once — the consequence of group 6's
      replacement, asserted rather than assumed.
- [ ] 9.5 **The export is byte-identical** with a pairing on screen and without one, for the same report.
      **Negative control:** make a visual reachable from the export path temporarily and demonstrate the
      suite fails; revert.
- [ ] 9.6 `./Scripts/check-boundaries.sh` green; no AVFoundation, no Accelerate and no `URL` in
      `FeatureImport` or `FeatureAnalysis`; no framework type in any port.
- [ ] 9.7 **A missing drawing never damages a report.** With either file's artefact absent or failed,
      both reports keep the same properties, warnings and global status they would have otherwise, and no
      inspection warning is emitted for the drawing.
- [ ] 9.8 Confirm the diff touches none of: `WaveformEnvelope`, `Spectrogram`, `PCMStreamDescription`,
      `ReportMeasurements`, `MeasurementComparison`, `FileComparison`, `InspectionReport`,
      `SpectrogramColourRamp`, the property reader, the exporter, `schemaVersion` 1.

## 10. Manual validation — the two properties ADR-0025's promotion turns on

**Only two, and each is binary.** Both are written before the application is opened and are left
unedited afterwards. Neither may be answered with *looks good*, *clear enough* or *easy to understand*;
each asks two questions with a literal yes or no. Record the result in
`docs/manual-validation-mvp.md` as a durable statement, including anything that failed, unsoftened.

- [ ] 10.1 **M1 — different durations.** Inspect a file of about 3:30, compare it against one of about
      3:00 (either order), and wait for the paired drawings.
      **Q1.** Does the shorter file's drawing end **before** the right-hand edge of the shared axis, at a
      position consistent with the two durations shown in the property rows above? **yes / no**
      **Q2.** Does the remainder of that lane read as **"this file has no audio here"** rather than as
      silence? **yes / no**
      **PASS** = yes to both. **FAIL** = no to either. A remainder that reads as a quiet passage, a flat
      line or an unfinished drawing is a **no** to Q2.
- [ ] 10.2 **M2 — different Nyquists.** Compare a 44.1 kHz file against a 96 kHz one (either order) and
      wait for the paired spectral models.
      **Q1.** Does the 44.1 kHz model stop **below** the top of the shared frequency axis? **yes / no**
      **Q2.** Is the region above it distinguishable **by eye** from the floor colour used **inside** the
      drawing? **yes / no**
      **PASS** = yes to both. **FAIL** = no to either. Q2 is the one this check exists for: if the two
      look the same, the surface is saying *measured and very quiet* where it means *cannot represent
      this range*, which is a defect and not a gap.
- [ ] 10.3 Process identity, before either check: terminate every running instance, rebuild, and launch
      the new binary **by its executable path — never `open`** — confirming a fresh window first. The
      precedent for why is in `docs/manual-validation-mvp.md`.

## 11. Gates and closure

- [ ] 11.1 Four gates green — `./Scripts/check-boundaries.sh`,
      `swift build -Xswiftc -warnings-as-errors`, `swift test`,
      `OPENSPEC_TELEMETRY=0 openspec validate --all --strict` — plus the Xcode app build and
      `git diff --check`.
- [ ] 11.2 Confirm every negative control in groups 2–9 was **seen to fail** and reverted in full, with
      no residue in the diff.
- [ ] 11.3 Decide **ADR-0025**'s status from what was actually demonstrated, against its own three
      promotion conditions and nothing else. Partial evidence does not promote it, and group 10's two
      checks are not optional.
- [ ] 11.4 Update `CURRENT.md`, and archive through `openspec archive` **after merge**, without editing
      the promoted specs by hand.
- [ ] 11.5 Record in `add-two-file-technical-comparison` that its group 4 decision — *the second file's
      visualisations are discarded* — is superseded by this change, without editing its historical text.

## 12. Deferred, and named so it is not quietly dropped

- [ ] 12.1 **Evidence comparison** — alignment, gain matching, residual, correlation, spectral difference,
      matching regions. ADR-0017 §9's, and every step is a heuristic with a threshold. What it will need
      is retained by this change; **nothing here authorises it.**
- [ ] 12.2 **Findings** — same master, remaster, transcode, upsample, lossy source, quality, provenance.
      This change is a producer of pictures for a reader, never a small version of that capability.
- [ ] 12.3 **Comparison export** — a document kind of its own. `schemaVersion` 1 describes one file and
      gains nothing here (ADR-0017 §9).
- [ ] 12.4 **Synchronised inspection** — cursors, zoom, scrubbing, linked scrolling. Out by ADR-0025 §11,
      and a synchronised cursor needs an alignment decision that belongs to 12.1.
- [ ] 12.5 **More than two files.** Everything here is stated for a pair, and a third would reopen the
      lifetime decision and the memory figures first.
