# Tasks — R5, the Waveform workspace

Large tasks. This slice is one coherent unit of work and closes in one pass.

## 1. The plot, made sizeable

- [x] 1.1 The drawing gains an explicit sizing value — fixed, or flexible between a minimum and a
      maximum — instead of a literal height baked into it. The report page keeps the fixed size it has
      today; the workspace uses the flexible one, budgeted in `design.md` §4 from the window's own
      minimum rather than chosen by taste.
- [x] 1.2 `WaveformGeometry`, `PairedWaveformAxis`, `WaveformEnvelope` and every copy owner are **not
      edited**: the bucket arithmetic, the amplitude scale, the shared time axis and every sentence stay
      exactly as they are.

## 2. The paired lane, rebuilt around the defect

- [x] 2.1 The lane stops embedding the composite single-file section and renders the **drawing alone**
      inside the measured width, with its attribution, its state sentence and its out-of-range sentence
      as ordinary siblings — the shape `PairedSpectrogramSection` in the same file already has
      (`design.md` §2).
- [x] 2.2 The lane's prose comes from `PairedVisualsCopy`, which already produces it, so one sentence has
      one owner. No string is added, reworded or removed.
- [x] 2.3 A shorter file still ends at its own extent, its remainder still carries no drawn value, and
      the sentence saying so is now laid out where it can be read.

## 3. The workspace

- [x] 3.1 `ReportWaveformView`: the drawing filling the section's height above the line naming it, for a
      single file; two lanes and the shared-extent line for a pair. Which of the two is shown is
      `ReportVisuals`' existing answer, read once, so the workspace and the report page cannot disagree.
- [x] 3.2 Loading, absent and failed each say which they are, in the drawing's place, in the copy
      owner's own words — never an empty area, a flat line or a baseline.
- [x] 3.3 One accessibility element per drawing, labelled with the artefact and — when paired — the file
      it belongs to. No element per bucket, no hover semantics.

## 4. Routing and the transitional page

- [x] 4.1 `WorkspaceSection.waveform` gets its own branch of the existing switch. Overview and Spectrum
      keep the transitional report page unchanged, and the branches stay alternatives, so the drawing
      and this section can never be on screen together.
- [x] 4.2 No section is added or removed, the selection stays where R1 owns it, and no navigation
      machinery is introduced.

## 5. Tests

- [x] 5.1 **The overlap's structural guard**: the paired lane builds no composite section, declares no
      fixed-height frame around a measured area holding text, and renders its prose from its own copy
      owner. It is the property the old code violated and no test could see.
- [x] 5.2 **Semantics preserved**: the envelope, the bucket arithmetic, the amplitude scale and the
      shared time axis are the ones production already had; a shorter file ends early; the remainder is
      never silence, a baseline or a zero; the two lanes are never overlaid.
- [x] 5.3 **Scope**: no zoom, pan, cursor, playhead, scrubbing, selection, playback, alignment, overlay,
      difference, correlation, similarity or normalisation reaches the new sources, and neither does a
      decoder, an accumulator or a read.
- [x] 5.4 **States and accessibility**: loading, absent and failed are three distinguishable sentences;
      no drawing is ever silent; one element per drawing, naming its file when paired.
- [x] 5.5 **Routing and isolation**: Waveform shows the workspace; Details and Measurements still show
      theirs; the transitional page still carries the comparison; the sections are still five; the
      export, the JSON contract, the one-read invariant and the bounded retention are untouched.

## 6. Negative controls

- [x] 6.1 Six mutations, one at a time, each reverted by checksum: the overlap's structure reintroduced;
      a short lane's remainder drawn as silence; the two lanes overlaid; an interaction affordance added;
      the workspace reaching for an analysis; the workspace and the transitional page shown together.
      Each must fail a protection that already exists.

## 7. Gates

- [x] 7.1 Boundaries, warnings-as-errors, the full suite twice, the Xcode build, OpenSpec strict, and
      `git diff --check` — plus a style comparison of the touched files against `main`.
      Green before the PR and green again on `main` after the merge: boundaries, a zero-warning build,
      **1816 tests in 198 suites, twice**, the Xcode build, `openspec validate --all --strict` and
      `git diff --check`. The style comparison found **no regression**: the new production file carries
      zero swiftformat and zero swiftlint violations; the three pre-existing files this slice touches
      carry the **same** violation counts as on `main`; the new test files introduce no violation class
      absent from `main/Tests`, and the `type_body_length` and `file_length` totals are unchanged. One
      blank line this slice did introduce was corrected rather than accepted.

## 8. Closure — after merge

- [x] 8.1 Merged on its own small PR, `main` green.
      PR [#56](https://github.com/donatogomez/audio-inspector/pull/56), merged 2026-08-28 as the
      **two-parent merge commit `c78c309`** — 5 commits, 14 files, +1258/−20, CI green in 6m38s.
      Integration proved six ways rather than taken from the label: the PR reports `MERGED` with a
      non-null `mergedAt`; the commit has exactly two parents, `09bcf60` and `37341bf`; the second parent
      **is** the feature head; the merge's tree is byte-identical to the feature head's (`7aa7d20e…`), so
      the merge resolved nothing and added nothing of its own; `origin/main` **is** the merge commit; and
      the feature has **0** commits outside it. `main` green after, with the baseline recorded in 7.1.
- [x] 8.2 `CURRENT.md` refreshed and `restructure-inspection-workspace` §3.4 marked — after merge.
      Both done after the merge, in that order. §3.4 is the umbrella task that names this slice **and**
      the overlap, and it now records what landed and what it did not cost; the counter moves
      **14/29 → 15/29**, and §3.5–§3.8 — R6 through R9 — are untouched, asserted. `CURRENT.md` names the
      PR, the merge commit, the archive path, the final task count with its deferrals, the umbrella
      count, both ADR states and the next slice. It also retires the standing defect note: the paired
      waveform's text overlap is no longer carried as debt, because it is closed.
- [x] 8.3 Archive through `openspec archive` **after merge**.
      Archived as `openspec/changes/archive/2026-08-28-restructure-waveform-workspace/`, after the merge,
      after `main` was fast-forwarded to it, and after the post-merge baseline was green.
      **Both canonical deltas were computed from the state rather than taken from a figure.**
      `audio-file-inspection` went from **22 requirements / 79 scenarios to 25 / 89** (+3 / +10) and
      `audio-two-file-visual-presentation` from **11 / 38 to 12 / 41** (+1 / +3) — each exactly its own
      archived delta spec, checked against it. Both updates are purely additive: 92 and 31 lines added,
      **0 removed**, so every existing requirement survives byte-identical and there is no duplicate
      heading. **`waveform-visualization` is byte-identical**, as this slice's design said it must be —
      it was deliberately not a delta owner, because its refusal of playback, zoom, scrubbing, selection
      and a cursor is unconditional and already binds a bigger drawing. The **other seven capabilities
      are byte-identical** too, compared by SHA-1 before and after.

      **A correction on the record.** The pre-merge report projected *"+4 req / +13 scen → 26/92 and
      12/41"*. The `+4 / +13` was the total across **both** capabilities, and applying it to
      `audio-file-inspection` alone double-counted the second capability's delta. The real figures are
      the ones above: **25 / 89** and **12 / 41**. The `12/41` in that report was right; the `26/92` was
      not, and no such state ever existed.

## 9. Deferred, and named so it is not quietly dropped

- [ ] 9.1 **The spectrum workspace** — R6. Its paired lane needs no overlap fix (`design.md` §2 shows it
      already lays its prose outside the plot) but still draws into a fixed strip and will want the same
      flexible sizing. R6 owns that surface.
- [ ] 9.2 **A comparison surface** — R8. This slice reads the comparison only to choose between one
      drawing and two.
- [ ] 9.3 **The full accessibility and responsive passes** — R9, including the largest accessibility text
      sizes, where a lane's prose can still out-grow the budget in `design.md` §4.
- [ ] 9.4 **Splitting `PropertyDisplay.detail`** — inherited from R3 and restated by R4; untouched here
      and owned by whichever slice next reworks Details or the comparison.
