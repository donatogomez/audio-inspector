# Tasks — R6, the Spectrum workspace

Large tasks. This slice is one coherent unit of work and closes in one pass.

## 1. The plot, made sizeable

- [x] 1.1 The spectral plot gains an explicit sizing value — fixed, or flexible between a minimum and a
      maximum — instead of the literal heights baked into the single section (220 pt) and the paired lane
      (140 pt). The maximum is derived from the model's own band count rather than chosen
      (`design.md` §4); the report page keeps the fixed sizes it has today.
- [x] 1.2 `SpectrogramAccumulator`, `Spectrogram`, `SpectrogramGridMapping`, `SpectrogramRaster`,
      `SpectrogramAxes`, `SpectrogramGeometry`, `SpectrogramColourRamp`, `PairedSpectrogramAxes` and
      every copy owner are **not edited**: the transform, the resolution, the absolute dBFS scale, the
      floor, the ramp, the axes and the shared frequency geometry stay exactly as they are.
- [x] 1.3 The raster stays a function of the model alone, so a resize redraws and never rebuilds.

## 2. The legend the pairing never had

- [x] 2.1 `PairedSpectrogramSection` presents **one** legend describing both lanes — the existing
      `SpectrogramLegend`, unchanged, not a second set of numbers. It goes in the paired section rather
      than only in the workspace, so the contract is met everywhere the pairing appears.

## 3. The workspace

- [x] 3.1 `ReportSpectrumView`: for one file, the plot with its frequency axis, its time axis, its
      legend and its sentence; for a pair, two lanes above the shared-extent sentences and the one
      legend. Which of the two is shown is `ReportVisuals`' existing answer, read once, so the workspace
      and the report page cannot disagree.
- [x] 3.2 Loading, absent and failed each say which they are, in the drawing's place, in the copy
      owner's own words — never an empty grid and never a region of the floor colour.
- [x] 3.3 One accessibility element per drawing, labelled with the artefact and — when paired — the file
      it belongs to. No element per cell or per band, no hover semantics.
- [x] 3.4 Free space is shared rather than pooled below, the behaviour R5 arrived at by rendering.

## 4. Routing and the transitional page

- [x] 4.1 `WorkspaceSection.spectrum` gets its own branch of the existing switch. Overview keeps the
      transitional report page unchanged, and the branches stay alternatives, so the drawing and this
      section can never be on screen together.
- [x] 4.2 No section is added or removed, the selection stays where R1 owns it, and no navigation
      machinery is introduced.

## 5. Tests

- [x] 5.1 **The absolute scale**: the ramp, its floor and the legend's ticks are one fixed set, shared by
      both lanes of a pair and by a single drawing; no per-file, per-pair or per-window scaling exists.
- [x] 5.2 **Frequency geometry**: a single file's axis reaches its own Nyquist; a pair's reaches the
      greater of the two; a 44.1 kHz lane beside a 96 kHz one occupies its own Nyquist as a fraction and
      stops there, in either order.
- [x] 5.3 **Out-of-range is not the floor**: the two are produced by different render paths, and the
      treatment is achromatic where no ramp value is — asserted structurally, not by hoping two colours
      differ.
- [x] 5.4 **Sizing**: the flexible bounds replace the rigid strips, the maximum follows the band count,
      and both the single and the paired worst case fit the window's smallest supported content height.
- [x] 5.5 **Scope**: no zoom, pan, cursor, readout, scrubbing, selection, playback, overlay, difference,
      alignment, normalisation or channel selector reaches the new sources, and neither does a decoder,
      an accumulator, a transform or a read.
- [x] 5.6 **States, legend and accessibility**: loading, absent and failed are three distinguishable
      sentences; a model with no columns is a statement rather than an absence; a legend accompanies
      every drawing and exactly one describes a pair; one element per drawing.
- [x] 5.7 **Routing and isolation**: Spectrum shows the workspace; Details, Measurements and Waveform
      still show theirs; the transitional page still carries the comparison; the sections are still five;
      the export, the JSON contract, the one-read invariant and the bounded retention are untouched.

## 6. Negative controls

- [x] 6.1 Seven mutations, one at a time, each reverted by checksum: a per-file colour scale; the
      out-of-range region rendered through the floor's path; a 44.1 kHz lane given the shared top as if
      valid; the two lanes overlaid; an interaction affordance; the workspace reaching for the analysis
      module; and the workspace beside the transitional page. Each must fail a protection that already
      exists.

## 7. Gates

- [ ] 7.1 Boundaries, warnings-as-errors, the full suite twice, the Xcode build, OpenSpec strict, and
      `git diff --check` — plus a style comparison of the touched files against `main`.

## 8. Closure — after merge

- [ ] 8.1 Merged on its own small PR, `main` green.
- [ ] 8.2 `CURRENT.md` refreshed and `restructure-inspection-workspace` §3.5 marked — after merge.
- [ ] 8.3 Archive through `openspec archive` **after merge**.

## 9. Deferred, and named so it is not quietly dropped

- [ ] 9.1 **The Inspection Overview** — R7. Overview keeps the transitional report page; this slice does
      not touch it.
- [ ] 9.2 **A comparison surface** — R8. This slice reads the comparison only to choose between one
      drawing and two.
- [ ] 9.3 **The full accessibility and responsive passes** — R9, including the largest accessibility text
      sizes, where a paired lane's prose can out-grow the budget in `design.md` §4.
- [ ] 9.4 **`add-static-spectrogram-visualization`'s own closure and ADR-0016's promotion.** That change
      is still open with its manual battery deferred by product decision, which is why
      `spectrogram-visualization` is not yet a canonical capability (`design.md` §9). Nothing here closes
      or promotes either.
- [ ] 9.5 **Splitting `PropertyDisplay.detail`** — inherited from R3, restated by R4 and R5.
