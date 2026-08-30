# Implementation Tasks

**This change implements the shell and nothing else.** It creates the five sections and the selection
that moves between them — the plan's R1 — because that behaviour is architecture rather than any slice's
content, and because OpenSpec requires a change to carry a delta. Everything a section *contains* is
re-laid-out by R2–R9, each its own change, its own branch and its own small PR.

**R1 is merged; nothing after it is implemented.** The tasks below were written before a line of the
shell existed, so the order was decided rather than discovered. §2 is closed against real production
code, and §3 onward is untouched. Each slice becomes its own change when its turn comes — the first of
them, R2, now exists and is specified.

Boundaries every slice inherits: the domain, the media adapter and the analysis target are not touched;
`ImportFlowModel` and `ComparisonState` remain the only sources of the data lifecycle; the selected
section is named by no target below the composition root; the export and `schemaVersion` 1 are
untouched; no slice causes a second PCM read or a recomputation; and no semantic test is retired by
calling it legacy.

## 1. The architecture

- [x] 1.1 **ADR-0026** decides the information architecture, the ownership of the selected section, its
      lifetime, the limits of both Overviews, and the divergence from `docs/vision.md` §7.
      `docs/adr/0026-inspection-workspace-information-architecture.md`, `Proposed`.
- [x] 1.2 The Comparison Overview's content is settled **against the accepted capability** rather than by
      preference: identities, each side's own facts, the existing framing, and a way through. The
      filtered differences list is refused on its **empty state**, which is the prohibited phrase
      (ADR-0026 §8).
- [x] 1.3 The slice map, the contract matrix and the navigation contract are written (`design.md`).

## 2. R1 — the shell, which is this change's own work

- [x] 2.1 The five sections and the selected one, owned by the composition root. No target below it
      names the selection — asserted over all of `Sources/`.
      `WorkspaceSection` is a closed enumeration of five, and `WorkspaceNavigation` a value in
      `RootView`'s own `@State` — both `internal` to `AudioInspectorApp`. `WorkspaceOwnershipTests`
      reads every production file under `Sources/` **and `App/`** in the shape
      `SharedPCMDecodeCountTests`' source assertion uses: nothing outside the composition root names
      either, each of the five modules is asserted by name so a failure says which boundary broke, and a
      third test asserts the composition root *does* name them so the search cannot pass by being empty.
- [x] 2.2 The lifetime, one test per rule: a new primary file returns to the overview; a comparison
      starting, becoming ready, being dismissed or superseded leaves it alone; an analysis settling,
      failing or arriving absent leaves it alone; nothing is persisted.
      `WorkspaceNavigationLifecycleTests`, one test per rule, driven against the real `ImportFlowModel`
      with no SwiftUI, no panel and no sleeps. ADR-0026's promotion conditions 3, 4 and 5 say *from every
      section* and *nothing else moves it*, so those three loop over all five rather than proving the
      rule for one; and *settling* is exercised as all three of its kinds — a value arriving, an absence,
      and a failure. The rule is also **structurally** unable to see a comparison: no input carries one,
      asserted over the two files that carry the rule.
- [x] 2.3 The ten navigation scenarios of `design.md` §4, including the failed-new-primary case §4 leaves
      for this change to pin.
      All ten, plus four the flow makes reachable and §4 does not enumerate: a **dismissed picker**
      (`.report(A)` → `.working` → `.report(A)`, which must not read as a new file), a **partial** report
      (a new primary like any other), a **re-inspection of the same file** (a new primary, because
      `AudioFileReference.id` is minted per inspection), and the primary being **replaced underneath a
      settled comparison** (ADR-0026 §5's third row and its exception). Scenario 7 is pinned as §4 asks:
      a globally failed report leaves the section alone, and the next report that is not failed moves it.
- [x] 2.4 An absent or failed artefact leaves its section reachable, stating the absence in words.
      Reachability is structural — the five come from `WorkspaceSection.allCases` and no artefact state
      is an input to that list — and is driven anyway across absent, failed and cancelled envelopes and
      spectral models, selecting all five under each. The absence is stated in words by the existing
      report surface, which R1 does not move: `WaveformCopy`, `SpectrogramCopy` and their suites are
      untouched.
- [x] 2.5 **Negative control — a moving section would be caught.** Make an analysis settling change the
      selection temporarily and demonstrate 2.2 fails; revert.
      The guard that makes `observe` idempotent — `guard id != acknowledged` — was removed, so every
      republication of the same report reset the reader. **Seen to fail with 39 issues across 8 tests**:
      a settling analysis moved the reader from every section, so did each of comparison *loading*,
      *ready*, *dismissed*, *failed*, *cancelled* and *superseded* from every section, and so did
      dismissing the picker. The tests that did **not** fail are the ones that do not depend on this
      guard — a globally failed report, a preparation failure, a partial report, a re-inspection — which
      is what makes the control a defence and not a blanket. Reverted; verified by SHA-256 against the
      pre-mutation copy and by grep.
- [x] 2.6 **Negative control — persistence would be caught.** Write the selection somewhere that survives
      a launch temporarily and demonstrate 2.2 fails; revert.
      `WorkspaceNavigation` was given a `UserDefaults` round trip — written in `select(_:)`, restored in
      a new `init()`. **Seen to fail with 4 issues**: the three launch tests (*a workspace begins at the
      overview*, *a second workspace learns nothing from the first*, *a new workspace begins at the
      overview*) each restored the previous section, and the source sweep named both offending lines by
      file and line number. Reverted, checksums verified, and the key removed from the defaults domain.
- [x] 2.7 The vocabulary sweep for the fourth requirement, over the two-file surface this shell creates,
      **including the case where every comparable measurement agrees**. Demonstrate it fails by adding a
      count temporarily; revert.
      The sweep runs three ways over the surface: every string `WorkspaceCopy` can render, the same
      strings against **any digit** (a count is a number), and the string literals of the shell's own
      four source files — because a count added straight into the view would never reach the copy type.
      The all-agree case is covered by construction rather than by fixture: the shell's words do not vary
      with the two files, so sweeping the whole surface sweeps every state including that one.
      **Seen to fail with 4 issues** on `"3 differences"` added to the copy type and rendered beside
      *Close comparison*: the surface count went from 9 to 10, the term `differences` was named, the
      digit was named, and the source sweep reported the file and line. Reverted, checksums verified.
- [x] 2.8 Four gates green plus the Xcode build and `git diff --check`.

## 3. The slices that follow

Each is a separate change, created when its turn comes. None is started here.

- [x] 3.1 **R2** `restructure-empty-state` — **merged.** PR
      [#53](https://github.com/donatogomez/audio-inspector/pull/53) landed on `main` as the two-parent
      merge commit `eb81ae8` on 2026-08-28. The surface before a report is now one shell with three
      states: it says what the application does, offers one way to begin, states that a file may be
      dragged onto the window, and — last, and in **every** state — that the file is only read. The
      running state is indeterminate and names no file, no stage and no figure, because the flow reports
      none; a failure keeps the flow's own message beside a non-colour marker and one action named for
      choosing a file, because nothing about the failed selection is retained.
      **Nothing the redesign inherited was spent**: the whole window still takes the drop in every state,
      the picker, the security-scoped access, the stale guards, the export and the one PCM read are
      untouched, and no pre-existing test was modified. R1's five sections are still five.
- [x] 3.2 **R3** `restructure-report-details` — **merged.** PR
      [#54](https://github.com/donatogomez/audio-inspector/pull/54) landed on `main` as the two-parent
      merge commit `8d5d01f` on 2026-08-28. **Details is the first of the five sections whose content is
      its own**: selecting it shows the technical properties in the report's two named groups, the file's
      identity, the notes when there are any, and the result of the reading set apart from the facts.
      **It moves content and decides none of it** — every value, unit, absence, certainty state, note and
      outcome sentence is the one `ReportPropertyFormatter` already produces, and the grouping is
      `groups(for:)`'s; the view reaches for no property by name. Nothing is collapsed, because the only
      candidate conflates the exact figure with the reason an unreliable reading carries.
      **Nothing the redesign inherited was spent**: the other four sections still show the report page
      that has stood in for them since R1 — as alternatives, so every block Details presents has exactly
      one visible owner — and the comparison, the export, `schemaVersion` 1 and the one PCM read are
      untouched. No aggregate, no quality verdict, no provenance inference and no path. R1's navigation
      and R2's pre-inspection surface are unchanged, asserted.
- [x] 3.3 **R4** `restructure-report-measurements` — **merged.** PR
      [#55](https://github.com/donatogomez/audio-inspector/pull/55) landed on `main` as the two-parent
      merge commit `d5e07ad` on 2026-08-28. **Measurements is the second of the five sections whose
      content is its own**: the signal levels, the true peak, the integrated loudness and the programme
      bandwidth now sit in one reading surface — two named groups, *Level* and *Frequency*, one label
      column, and each method sentence behind a disclosure that never removes it. The grouping is the
      report's own distinction rather than an invention: `ReportView` already ordered these four by it.
      **It arranges measurements and takes none**: every value, unit, per-channel breakdown, absence,
      failure sentence and resolution is the one the four copy owners already produce, and nothing is
      read, decoded, measured, formatted or rounded to draw it. Only a method line is collapsed
      (ADR-0026 §11); every fact — including the programme bandwidth's *Analysis resolution* — stays
      visible.
      **Nothing the redesign inherited was spent**: no comparison reaches the section in any comparison
      state, so the comparison stays whole and unchanged on the transitional report page until R8 — the
      precedent R3 set for Details. The export, `schemaVersion` 1 and the one PCM read are untouched;
      `AudioInspectorDomain`, `AudioInspectorAnalysis`, `AudioInspectorMedia` and `FeatureImport` have
      zero files changed. No threshold, no target, no aggregate, no quality verdict and no provenance
      inference. R1's navigation, R2's pre-inspection surface and R3's Details are unchanged, asserted.
- [x] 3.4 **R5** `restructure-waveform-workspace` — **merged, and the paired-waveform text overlap
      closed here.** PR [#56](https://github.com/donatogomez/audio-inspector/pull/56) landed on `main`
      as the two-parent merge commit `c78c309` on 2026-08-28. **Waveform is the first section whose
      content is a drawing**, so the first that needed room rather than order: it takes the height the
      section can offer instead of the 96 pt strip it had, and how much height is a value budgeted from
      the window's own 720 × 480 minimum rather than a literal in a view. ADR-0026 §9's other half
      holds — **room bought no powers**: no playback, playhead, zoom, pan, scrubbing, cursor, selection,
      transport, hover readout, alignment, overlay, difference drawing, correlation, similarity,
      normalisation or export, and the drawing still takes no hit.
      **The overlap's cause was proven, not guessed.** The lane put a composite of drawing-plus-prose
      inside a `GeometryReader` frozen at the drawing's own height, and a `GeometryReader` does not
      clip. The correct shape already sat twenty lines below in the same file — the spectral lane puts a
      drawing, and only a drawing, in its measured area — so the waveform lane converged on it rather
      than inventing a fix, and a structural test now refuses the old shape. A magic height, an offset,
      a truncation and a smaller font were each refused as fixes that expire.
      **Nothing the redesign inherited was spent**: `WaveformGeometry`, `PairedWaveformAxis`,
      `WaveformEnvelope` and every copy owner have zero files changed; a shorter file still ends at its
      own extent and its remainder is still stated in words rather than drawn as silence; no comparison
      surface was built, so the comparison stays whole until R8. The export, `schemaVersion` 1 and the
      one PCM read are untouched, and `AudioInspectorDomain`, `AudioInspectorAnalysis`,
      `AudioInspectorMedia` and `FeatureImport` have zero files changed. R1–R4 are unchanged, asserted.
- [x] 3.5 **R6** `restructure-spectrum-workspace` — **merged.** PR
      [#57](https://github.com/donatogomez/audio-inspector/pull/57) landed on `main` as the two-parent
      merge commit `3f75900` on 2026-08-28. **Four of the five sections have their own surface now**;
      only Overview still shows the report page, until R7. The spectral drawing takes the height the
      section can offer, with its frequency axis, its time axis and its legend, instead of a fixed
      220 pt plot or two fixed 140 pt lanes — and **the bound on that height is the data**: a model
      carries at most 512 bands and is drawn with interpolation off, so past one pixel per band a taller
      image is upscaled rather than more detailed.
      **The pairing gained the legend the contract already required.**
      `audio-two-file-visual-presentation` asks that two models be drawn with one ramp, one floor and
      *one legend describing both*; the paired surface drew the ramp and explained it nowhere. The
      single-file section's own legend now sits once beneath both lanes — **implementation catching up
      to a canonical contract, with no delta written for it**, because restating a requirement that
      already exists is not a change.
      **Nothing the redesign inherited was spent**: the accumulator, the model, the grid mapping, the
      raster, the axes, the geometry, the colour ramp and the paired axes have zero files changed; the
      absolute dBFS scale, its −120 floor and the shared Nyquist geometry are untouched; above a file's
      own Nyquist keeps its achromatic treatment **and** its sentence, so it still cannot be mistaken
      for the floor — confirmed by rendering 44.1 kHz beside 96 kHz. No normalisation, no per-file
      scale, no overlay, no difference, no alignment and no interaction. The export, `schemaVersion` 1
      and the one PCM read are untouched, and `AudioInspectorDomain`, `AudioInspectorAnalysis`,
      `AudioInspectorMedia` and `FeatureImport` have zero files changed. R1–R5 are unchanged, asserted.
- [x] 3.6 **R7** `add-inspection-overview` — **merged.** PR
      [#58](https://github.com/donatogomez/audio-inspector/pull/58) landed on `main` as the two-parent
      merge commit `607f901` on 2026-08-29. **All five sections are real in inspection mode now**:
      selecting Overview shows the file's identity, the six core technical facts, one figure per
      measurement, a compact drawing of the envelope the inspection already produced, and what became of
      the reading. **It arranges facts and derives none** — `ReportPropertyFormatter`,
      `MeasurementsDisplay` and `WaveformCopy` produce every name, value, unit, absence, failure and
      outcome sentence, and the view names no property of its own: §6's six facts are selected by
      `ReportPropertyFormatter.coreFacts(for:)`, beside `groups(for:)` and `summary(for:)`, because
      §6's six are not a group boundary and a view is not where property meaning belongs.
      **§6 is built except for the warning count, and the count is refused on a ground §7 does not
      consider.** §7's three conditions each hold; what they do not survive is R3's own shipped
      requirement in `audio-file-inspection` — *"A note MUST NOT be counted, scored, ranked by severity,
      or summarised into a total"* — which is unqualified, which calls warnings **Notes**, and which
      became canonical on 2026-08-28 (`f9aa9b7`), *after* this record was written on 2026-08-27. A
      `Proposed` record does not overrule a shipped capability, so §7's own last line is taken: *the
      count goes and the section title carries the reader instead.* Specialising the requirement by a
      delta was available and declined — §8 specialised a rule in the direction of refusing **more**,
      and this would specialise one to be allowed an exception to it. **The finding that ADR-0026 §7 is
      unreachable as written is recorded in R7's archived `proposal.md` and `design.md`**, which task
      5.3 reads when it decides this record's status; 5.3's own text is left as it was.
      **The transitional page survives in exactly one place, deliberately.** `legacyReportSurface` is
      `ReportView`'s only composition caller, and `ReportView` is the only host of `ComparisonSection`
      (declared in `ComparisonView.swift`) — the comparison surface itself — so replacing the
      `.overview` branch outright would have **deleted the comparison from the application** until R8.
      The branch splits on `ComparisonPresentation` — not on `ReportVisuals`, which becomes a pair only
      once both files have settled both drawings and would have silently dropped the comparison's
      *loading* and *failed* states. **R8 removes this fallback**; it is the only surviving dependency
      on the legacy `ReportView`.
      **Two defects were found by rendering the surface and looking at it, and by nothing else**: a
      measurement's figure carried the *measurement's* title rather than the fact's, so *Signal levels:
      −3.00 dBFS* did not say which level it was; and only the drawing's `headline` was rendered, which
      an envelope does not have, leaving the one state with a drawing as the one state with no words.
      Every test passed before both.
      **Nothing the redesign inherited was spent**: no second PCM read, no recomputation, no
      normalisation and no alternative reduced envelope; the absolute amplitude scale, the export,
      `schemaVersion` 1, R1's five sections and their order, and R2–R6's surfaces are asserted
      unchanged; and `AudioInspectorDomain`, `AudioInspectorAnalysis`, `AudioInspectorMedia`,
      `FeatureImport` and `AudioInspectorTesting` have **zero files changed**. Four production files,
      379 lines. Four negative controls seen to fail and reverted by checksum — the one that made the
      `.overview` branch unconditional was caught by R3's and R6's own suites as well as R7's.
      **The change archives with one task open, deliberately**: 6.2, rendering the branch with a
      *settled* comparison, needs two real files driven through the picker, which no harness could do.
      It is **manual validation deferred to R9**, and closing it on evidence that does not exist would
      have been the only dishonest way to reach a full count.
- [x] 3.7 **R8** `add-comparison-mode-surface` — **merged.** PR
      [#60](https://github.com/donatogomez/audio-inspector/pull/60) landed on `main` as the two-parent
      merge commit `2765bae` on 2026-08-30. **A comparison is a mode of this workspace now**, which is
      what ADR-0026 §2 and §3 decided and what no slice before this could make true: the same five
      sections exist in both modes, in the same order, and what a comparison changes is what each one
      *contains*. Details renders the technical comparison, both identities, each file's notes and each
      file's result; Measurements renders the comparison of the same four measurements in place rather
      than appended; **Waveform and Spectrum needed nothing at all** — R5 and R6 built them against
      `ReportVisuals`, which has paired the two files since it shipped, so they have zero lines changed.
      **The Comparison Overview is §8 exactly**, and its safety is structural rather than lexical. §8
      refused a filtered *properties that differ* list on the narrow ground that it fails on its **empty
      state**, where the absence of rows is itself the prohibited phrase; R8 generalises that answer —
      **no outcome reaches the surface at all.** It reads each file's own `AudioFileReference` and the
      copy, never a property, a measurement, a warning, a status or any comparison type, so no element
      can appear or disappear for a reason that means the files are alike. An all-agree pair and a pair
      agreeing about nothing render the same elements, confirmed by test and by rendering both.
      **The vocabulary sweep this task named as R8's gate ran**: 22 terms over the three new surfaces,
      20 with zero occurrences, two audited and allowed with their reasons recorded. It found a real
      defect rather than confirming a hunch — `ComparisonCopy.subtitle` described the page being removed
      and carried three outcome words, so the overview was given its own framing.
      **The transitional page is gone.** `legacyReportSurface`, `ReportView` and `ComparisonSection` had
      no callers left and were deleted, but `ReportSection` was **extracted first**: it was declared
      inside `ReportView.swift` and four live sections use it. That is the distinction the deletion
      turned on — dead UI goes, reusable containers, formatters and copy stay.
      **`ComparisonSection.warningSummary` was deleted rather than migrated.** It rendered *"1 warning on
      this file"* per side — a cardinality over notes, written before `audio-file-inspection` made *"A
      note MUST NOT be counted, scored, ranked by severity, or summarised into a total"* canonical.
      Nothing stands in for it, and Details presents each file's notes in the report's own words, which
      is more than a count ever said.
      **Nothing the redesign inherited was spent**: no second PCM read, no DSP, no recomputation; every
      measurement and comparison semantic, the paired axes and ramps, the export, `ReportExportToolbar`,
      `schemaVersion` 1 and R1's navigation lifetime are untouched, and `AudioInspectorDomain`,
      `AudioInspectorAnalysis`, `AudioInspectorMedia` and `FeatureImport` have **zero files changed**.
      Twelve negative controls seen to fail and reverted by checksum. **1897 tests in 205 suites**,
      twice.
      **It archives with three visual validations open** — the settled measurement comparison, the paired
      waveform and the paired spectrum — deferred to R9's human pass rather than closed on evidence that
      does not exist.
- [ ] 3.8 **R9** `polish-inspection-workspace` — narrow windows, keyboard, VoiceOver, and the human pass.

## 4. Closure

- [ ] 5.1 Every slice merged, each on its own small PR, `main` green between them.
- [ ] 5.2 The contract matrix walked once more against the merged result: every row still protected by
      the capability or test named beside it, and no semantic assertion retired.
- [ ] 5.3 Decide **ADR-0026**'s status from what R1 actually demonstrated, and no earlier.
- [ ] 5.4 Update `CURRENT.md`, and archive through `openspec archive` **after merge**.

## 5. Deferred, and named so it is not quietly dropped

- [ ] 4.1 **History, recents, a library.** Nothing persists (ADR-0004, ADR-0010), so there is nothing to
      browse. Not started here.
- [ ] 4.2 **A sidebar.** ADR-0026 §12 records the divergence from `docs/vision.md` §7 and the condition
      that would reopen it — a collection existing.
- [ ] 4.3 **Interaction on the drawings** — zoom, cursor, scrubbing, synchronised navigation. Each needs
      an alignment decision that belongs to evidence comparison.
- [ ] 4.4 **Evidence comparison and Findings.** Nothing here authorises either.
- [ ] 5.5 **The comparison export.** A document kind of its own (ADR-0017 §9).
- [ ] 5.6 **The VoiceOver traversal gap**, inherited from ADR-0015 and ADR-0017. R9 is where it would
      most naturally be attempted; this change does not require it.
