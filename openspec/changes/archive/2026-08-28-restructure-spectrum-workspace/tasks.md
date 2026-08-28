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

- [x] 7.1 Boundaries, warnings-as-errors, the full suite twice, the Xcode build, OpenSpec strict, and
      `git diff --check` — plus a style comparison of the touched files against `main`.
      Green before the PR and green again on `main` after the merge: boundaries, a zero-warning build,
      **1848 tests in 200 suites, twice**, the Xcode build, `openspec validate --all --strict` and
      `git diff --check`. The style comparison found **no regression**: the new production file carries
      zero swiftformat and zero swiftlint violations, the three pre-existing files touched carry the
      **same** counts as on `main`, and the new test files introduce no violation class absent from
      `main/Tests`. Three violations this slice did introduce were corrected rather than accepted.

## 8. Closure — after merge

- [x] 8.1 Merged on its own small PR, `main` green.
      PR [#57](https://github.com/donatogomez/audio-inspector/pull/57), merged 2026-08-28 as the
      **two-parent merge commit `3f75900`** — 6 commits, 14 files, +1268/−26, CI green in 8m57s.
      Integration proved six ways rather than taken from the label: the PR reports `MERGED` with a
      non-null `mergedAt`; the commit has exactly two parents, `72dd0d9` and `4657858`; the second parent
      **is** the feature head; the merge's tree is byte-identical to the feature head's (`b4dd86d5…`), so
      the merge resolved nothing and added nothing of its own; `origin/main` **is** the merge commit; and
      the feature has **0** commits outside it. `main` green after, with the baseline recorded in 7.1.
- [x] 8.2 `CURRENT.md` refreshed and `restructure-inspection-workspace` §3.5 marked — after merge.
      Both done after the merge, in that order. §3.5 records what landed and what it did not cost, and
      the counter moves **15/29 → 16/29**; §3.6–§3.8 — R7 through R9 — are untouched, asserted.
      `CURRENT.md` names the PR, the merge commit, the archive path, the final task count with its
      deferrals, the umbrella count, all four ADR states and the next slice. It also keeps two facts
      live rather than tidy: `add-static-spectrogram-visualization` is still open at 73/89, and the
      single-file raster cells were the one thing this slice could not check by eye.
- [x] 8.3 Archive through `openspec archive` **after merge**.
      Archived as `openspec/changes/archive/2026-08-28-restructure-spectrum-workspace/`, after the merge,
      after `main` was fast-forwarded to it, and after the post-merge baseline was green.
      **The canonical delta was computed from the state and checked against the archived delta spec.**
      `audio-file-inspection` went from **25 requirements / 89 scenarios to 29 / 101** — exactly +4 / +12
      — purely additive: 119 lines added, **0 removed**, so every existing requirement survives
      byte-identical and there is no duplicate heading. **The other eight capabilities are
      byte-identical**, including `audio-two-file-visual-presentation`: this slice implemented a legend
      that capability **already required** and wrote no delta for it, because conformance is not a
      contract change.
      **The open spectrogram change was left alone, and that was checked rather than assumed.**
      `add-static-spectrogram-visualization` is **byte-identical across all seven of its files** before
      and after this archive, still active at **73/89**, and `spectrogram-visualization` was **not**
      materialised as a canonical capability — it remains a delta inside that change, where it belongs
      until its own archive. `add-two-file-technical-comparison` is byte-identical too.

      **A correction on the record.** The pre-merge report gave this slice's delta as +4 requirements /
      **+13** scenarios. The four requirements carry 3 + 4 + 2 + 3 = **12**, and the archive applied 12.
      The expected total was therefore 29 / **101**, not 29 / 102. Caught in this turn's pre-review,
      before publishing, and confirmed against the archive.

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
