# Implementation Tasks

**This change implements the shell and nothing else.** It creates the five sections and the selection
that moves between them — the plan's R1 — because that behaviour is architecture rather than any slice's
content, and because OpenSpec requires a change to carry a delta. Everything a section *contains* is
re-laid-out by R2–R9, each its own change, its own branch and its own small PR.

**Nothing below is started.** The tasks are written so the order is decided before the first line of the
shell exists.

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

- [ ] 2.1 The five sections and the selected one, owned by the composition root. No target below it
      names the selection — asserted over all of `Sources/`.
- [ ] 2.2 The lifetime, one test per rule: a new primary file returns to the overview; a comparison
      starting, becoming ready, being dismissed or superseded leaves it alone; an analysis settling,
      failing or arriving absent leaves it alone; nothing is persisted.
- [ ] 2.3 The ten navigation scenarios of `design.md` §4, including the failed-new-primary case §4 leaves
      for this change to pin.
- [ ] 2.4 An absent or failed artefact leaves its section reachable, stating the absence in words.
- [ ] 2.5 **Negative control — a moving section would be caught.** Make an analysis settling change the
      selection temporarily and demonstrate 2.2 fails; revert.
- [ ] 2.6 **Negative control — persistence would be caught.** Write the selection somewhere that survives
      a launch temporarily and demonstrate 2.2 fails; revert.
- [ ] 2.7 The vocabulary sweep for the fourth requirement, over the two-file surface this shell creates,
      **including the case where every comparable measurement agrees**. Demonstrate it fails by adding a
      count temporarily; revert.
- [ ] 2.8 Four gates green plus the Xcode build and `git diff --check`.

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
