# Implementation Tasks

**R2 of the redesign.** Its whole subject is the surface a person sees before a report exists. It moves
no report content, adds no feature, and changes nothing about how a file is chosen, accessed or read.

Boundaries this slice inherits and may not touch: `ImportFlowModel`'s states, guards and transitions;
`DroppedSource`'s acceptance rules; `DropRejection`'s three sentences; `DropFeedbackOverlay`;
`SourceSelection`'s panel configuration; `SourceInspectionCoordinator`'s security-scoped access; the
entitlements; the export and `schemaVersion` 1; and everything R1 added. The production scope is
`ImportFlowView` and the copy it renders.

**Nothing below is started.** The design is settled before the first line so the order is decided rather
than discovered.

## 1. The words, before the layout

- [x] 1.1 A copy type for this surface, in `FeatureImport`, holding **every string it can render** — the
      purpose, the action labels, the drag-and-drop line, the read-only statement and the running status
      — in the shape `WorkspaceCopy` and `PairedVisualsCopy` already use, so the surface can be swept as
      values rather than by reading a view.
      `ImportFlowCopy` — a caseless `enum` of `static let`s, `internal`, the shape every copy owner in
      the repository already uses. Six sentences and an `everyRenderableString` the sweeps read, with a
      test proving each declared value is in that list: a value that is not swept is not protected.
      **`chooseAnotherFile` is written out rather than shared with `WorkspaceCopy`, and that is the
      boundary's doing, not a preference**: `FeatureImport` depends on `AudioInspectorDomain` alone and
      cannot see `AudioInspectorApp` (ADR-0005, enforced by `Scripts/check-boundaries.sh`). Sharing six
      words would mean lifting a presentation string into the domain.
      **Declared, not yet read.** `ImportFlowView` still renders its own literals; group 3 moves the
      rendering onto these values. The shape `ImportFlowModel.comparedVisuals` used when its container
      arrived before its consumer, and the copy type says so in its own words.
- [x] 1.2 The read-only statement is carried **verbatim**: *"The file is only read, never modified, moved
      or copied."* A test pins the exact sentence, so rewriting it is a decision rather than an edit.
      Pinned as the **whole sentence**, deliberately not by substring, plus a source assertion that it
      lives in presentation and in no layer below: not the domain, not the flow that owns states rather
      than sentences about them, not the composition root and not the export.
      **Early evidence, and the victim now exists.** Task 8.3's control was run against it twice.
      *Weakened* to `"The file is only read."` — the form a `contains("read")` check would have waved
      through — **1 issue**, naming the missing half. *Deleted* to `""` — **4 issues across 3 tests**:
      the verbatim pin, the non-empty vocabulary check, and both halves of the ownership assertion.
      Reverted, verified by SHA-256 and by grep. **8.3 stays open**: its full form needs the surface to
      render the sentence, which group 3 builds.
- [x] 1.3 The flow's own failure sentence is **presented, never restated**: no copy value duplicates
      *"That file could not be opened for inspection."*, asserted over this module's sources.
      One home, asserted over all of `Sources/`: the sentence occurs exactly once, in `ImportFlowModel`,
      and no value of the copy owner contains it.
- [x] 1.4 The three `DropRejection` sentences and the overlay's *"Drop one audio file"* are **not**
      redeclared here — they keep their single home, asserted.
      Each of the four asserted to its own file — three to `DropRejection`, one to `DropFeedbackOverlay`
      — with the copy owner declaring none of them.
- [x] 1.5 No string this surface can render states a percentage, a fraction, a count, a step or a time.
      The sweep runs over the copy values **and** over the string literals of this surface's own sources,
      because a figure added straight into the view would never reach the copy type.
      Both halves run: over the six values, and over the string literals of `ImportFlowCopy.swift` and
      `ImportFlowView.swift`. Any digit and `%` are refused outright — a progress figure is a number
      before it is anything else — alongside fifteen words a claimed quantity would arrive in.
      `ImportFlowView` stays in scope after group 3 moves its literals onto the copy owner.

## 2. The shell, and the two things that must not move

- [x] 2.1 One surface with a stable frame and one state region (`design.md` §4b, option B): the purpose,
      the primary action and the read-only line are rendered by **one** code path shared by every
      pre-report state, not by three.
      `ImportFlowView` is now a frame plus `statusRegion`, and the three states differ in that one place:
      one `switch presentation`, asserted, and one read of the flow, asserted. The surface used to insert
      the failure *above* the action and the progress indicator *below* it — two states moving different
      things at two heights, which is the defect option B exists to remove.
      **One visible difference, and it is the one the design specifies**: the failure message now sits
      below the action instead of above it, because the region is one region and §4b places it beneath.
      Idle and working render exactly as before — `EmptyView` contributes no height and no spacing, so
      the idle frame is the frame it was, and the indicator stays where it was.
      **The frame still says what it said.** Group 1's copy is not read here: the four rendered strings
      are byte-identical to the previous commit's, verified against `git show`. Groups 3–5 are where the
      words change.
- [x] 2.2 A presentation value maps the flow's three pre-report states onto what the region shows —
      total, with no default, so a state added to the flow is a compile error here rather than a silently
      empty region. Asserted without rendering anything.
      `PreInspectionPresentation` — `idle`, `working`, `failed(message:)` — projected by a **failable**
      initialiser, so a report is refused rather than degraded: it has no pre-report presentation and says
      so with `nil`. The failure's message is an associated value carried through unaltered, never a
      constant of `ImportFlowCopy`'s.
      **The claim was demonstrated, not asserted.** Adding a fourth state to `ImportFlowModel.State`
      temporarily stopped the build at `PreInspectionPresentation.swift:47` — *"switch must be
      exhaustive"* — which is this task's sentence, compiled. Reverted, checksum verified.
      **And the other half, which the compiler cannot see.** `case .report: self = .idle` compiles
      cleanly and would render a starting screen over a finished inspection: **4 issues across 3 tests**,
      including both report tests and the totality count. Reverted, checksum verified.
      **No parallel lifecycle.** `@State private var lastSeen` added to the surface — a second place this
      window's state could live — **1 issue**, naming the file and line. Reverted, checksum verified.
- [x] 2.3 `RootView`'s switch is unchanged: the surface is chosen for `.idle`, `.working` and `.failed`,
      and `.report` still renders the workspace.
      Zero lines of diff in `RootView.swift`, and the boundary is now stated twice rather than once: the
      composition root chooses the surface, and the surface's own projection refuses a report even if it
      were handed one.

## 3. Idle

- [ ] 3.1 The purpose, the primary action, the drag-and-drop alternative and the read-only line, in that
      order, each rendered once.
- [ ] 3.2 Exactly **one** action on the surface, asserted — no second call to action, no secondary
      button, no link.
- [ ] 3.3 Nothing that the system cannot do: no history, no recents, no library, no sample file, no
      feature list, no settings, asserted over the surface's renderable strings.

## 4. Working

- [ ] 4.1 An indeterminate indicator plus the status line, and the primary action **present and
      unavailable** rather than removed.
- [ ] 4.2 **The running state names no file**, because it also covers the moment before one has been
      chosen (`design.md` §1, §11). Asserted from the presentation value, which has no file to name.
- [ ] 4.3 No cancellation is offered, and the reason is recorded rather than assumed: `ImportFlowModel`
      exposes none, and dismissing the panel is already neutral.
- [ ] 4.4 **Negative control — a claimed quantity would be caught.** Add a percentage to the running
      state temporarily and demonstrate 1.5 fails; revert.

## 5. Failed

- [ ] 5.1 The flow's message, presented unaltered, with a non-colour marker beside it so the failure does
      not depend on red.
- [ ] 5.2 The way forward: the primary action, named for choosing a file rather than for retrying one,
      and the drop still accepted.
- [ ] 5.3 No action on this surface is named *try again*, *retry*, *repeat* or *run again* — asserted
      over the renderable strings, with the reason in the assertion: nothing about the failed selection
      is retained (ADR-0010, ADR-0013).
- [ ] 5.4 The failure is not presented as a report, and a globally failed **report** still reaches the
      workspace rather than this surface — the distinction `ImportFlowModel` already draws, asserted here
      so this slice cannot blur it.
- [ ] 5.5 **Negative control — a dead end would be caught.** Remove the way forward from the failed state
      temporarily and demonstrate 5.2 fails; revert.

## 6. Drag and drop — preserved, and proved preserved

- [ ] 6.1 The drop destination is still the **whole window**, in every state, and the overlay is
      unchanged. Asserted at the composition root rather than argued from the diff.
- [ ] 6.2 The existing drop suites — `DroppedSourceTests`, `ImportFlowDropTests`,
      `DroppedSourceInspectionTests` — pass unmodified. **None is edited by this slice**; if one becomes
      impossible to write in the same words, that is a finding about the slice.
- [ ] 6.3 **Negative control — losing the alternative would be caught.** Remove the drag-and-drop line
      from the surface temporarily and demonstrate 3.1 fails; revert.

## 7. Accessibility and the keyboard

- [ ] 7.1 Focus follows reading order, and the primary action is reachable and invocable from the
      keyboard alone.
- [ ] 7.2 The running state and the failure are **announced**, not conveyed by an animation or a colour.
- [ ] 7.3 Every element that carries meaning carries it in words; nothing on this surface means anything
      by colour alone.
- [ ] 7.4 The full traversal audit is **R9's** and is not attempted here — recorded so its absence is a
      decision.

## 8. What must still be true afterwards

- [ ] 8.1 **The surface is not a section.** `WorkspaceSection` still has exactly its five cases, the
      section navigation is still built only inside the report surface, and no case exists for an empty,
      idle, working or failed state. R1's own suites pass unmodified.
- [ ] 8.2 **Negative control — a sixth section would be caught.** Add an empty-state case to
      `WorkspaceSection` temporarily and demonstrate 8.1 and R1's contract suite fail; revert.
- [ ] 8.3 **Negative control — losing the trust statement would be caught.** Delete the read-only
      sentence temporarily and demonstrate 1.2 fails; revert. It is the control this slice exists to make
      possible: nothing protects that sentence today.
- [ ] 8.4 The file-access guarantees are untouched, asserted rather than asserted-by-diff: the panel's
      configuration, the drop's acceptance rules, the entitlements, the absence of a bookmark and the
      absence of any retained URL.
- [ ] 8.5 The export and `schemaVersion` 1 are unreachable from this surface and unchanged.
- [ ] 8.6 One PCM read per inspection, unchanged — this slice causes no read and no recomputation.

## 9. Gates

- [ ] 9.1 Four gates green — `./Scripts/check-boundaries.sh`, `swift build -Xswiftc -warnings-as-errors`,
      `swift test` twice, `openspec validate --all --strict` — plus the Xcode macOS build and
      `git diff --check`.
- [ ] 9.2 A focused run over this slice's own suites, and the full suite with **no existing test
      modified**.

## 10. Closure

- [ ] 10.1 Merged on its own small PR, `main` green.
- [ ] 10.2 `CURRENT.md` refreshed, and `restructure-inspection-workspace` §3.1 marked — **by the umbrella,
      after this change merges**, not here.
- [ ] 10.3 Archive through `openspec archive` **after merge**.

## 11. Deferred, and named so it is not quietly dropped

- [ ] 11.1 **Splitting the running state**, so a status line could name the file. It needs a change to
      `ImportFlowModel`'s lifecycle and belongs to whichever slice legitimately opens that file
      (`design.md` §11).
- [ ] 11.2 **Progress reporting.** It would require the read path to publish a quantity it does not
      produce, and it is not proposed.
- [ ] 11.3 **Cancelling a running inspection.** It needs a flow change and a decision about what a
      half-read file leaves behind.
- [ ] 11.4 **The full accessibility and responsive passes** — R9.
- [ ] 11.5 **History, recents, a library, a sidebar** — out by ADR-0004, ADR-0010 and ADR-0026 §12.
