# Implementation Tasks

**This change implements the shell and nothing else.** It creates the five sections and the selection
that moves between them — the plan's R1 — because that behaviour is architecture rather than any slice's
content, and because OpenSpec requires a change to carry a delta. Everything a section *contains* is
re-laid-out by R2–R9, each its own change, its own branch and its own small PR.

**R1 is implemented; nothing after it is started.** The tasks below were written before a line of the
shell existed, so the order was decided rather than discovered. §2 is now closed against real production
code; §3 onward is untouched, and each slice becomes its own change when its turn comes.

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
      with no SwiftUI, no panel and no sleeps. The rule is also **structurally** unable to see a
      comparison: no input carries one, asserted over the two files that carry the rule.
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
      republication of the same report reset the reader. **Seen to fail with 12 issues across 8 tests**:
      a settling analysis moved the reader, so did each of comparison *loading*, *ready*, *dismissed*,
      *failed*, *cancelled* and *superseded*, and so did dismissing the picker. The two tests that did
      **not** fail are the ones that do not depend on this guard — a globally failed report and a
      preparation failure — which is what makes the control a defence and not a blanket. Reverted;
      verified by SHA-256 against the pre-mutation copy and by grep.
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

- [ ] 3.1 **R2** `restructure-empty-state`.
- [ ] 3.2 **R3** `restructure-report-details`.
- [ ] 3.3 **R4** `restructure-report-measurements`.
- [ ] 3.4 **R5** `restructure-waveform-workspace` — and the paired-waveform text overlap closes here.
- [ ] 3.5 **R6** `restructure-spectrum-workspace`.
- [ ] 3.6 **R7** `add-inspection-overview` — ADR-0026 §6 exactly, including §7's three conditions on the
      warning count.
- [ ] 3.7 **R8** `add-comparison-mode-surface` — the reduced Comparison Overview, gated by a vocabulary
      sweep that includes the all-agree case.
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
