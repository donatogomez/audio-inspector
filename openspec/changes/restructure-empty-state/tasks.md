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

- [x] 3.1 The purpose, the primary action, the drag-and-drop alternative and the read-only line, in that
      order, each rendered once.
      All four now come from `ImportFlowCopy`, and they are the **frame** rather than the idle state's own
      content — which is what both requirements say: the purpose, the action and the alternative are
      *"present in every one of them"*, and the guarantee is required *"in every one of its states"* and
      *"SHALL NOT be conditional on any state"*. Task 2.1 had already fixed that shape. A person who has
      just been told an inspection failed still needs to know their file was not touched.
      They replace one sentence that carried three of these claims at once, so none could be given its own
      weight, and the heading that repeated the window's own title bar. **Nothing dropped, nothing added.**
      The order is asserted **relatively** — the four symbols' positions in the surface's source, strictly
      increasing, with no line number written down — plus one test that the guarantee is last, and one
      that it is rendered outright rather than behind a hover, a disclosure or a condition.
      **The varying region moved one position**, from after the guarantee to before it, so the guarantee
      is last as `design.md` §4b and §5 require. That is the group's only change to what the running and
      failed states look like; their own content is untouched, asserted.
- [x] 3.2 Exactly **one** action on the surface, asserted — no second call to action, no secondary
      button, no link.
      One `Button`, asserted by count, plus the absence of `Link`, `Menu`, `NavigationLink`, `Toggle`,
      `DisclosureGroup`, `onTapGesture` and `help(`. The drag-and-drop alternative is asserted to be a
      `Text` and to carry no control: a person using the keyboard alone must be able to do everything this
      surface offers, which a drop target cannot give them.
      **Seen to fail.** A second `Button` on the surface — 1 issue, naming the count. Reverted, checksum
      verified.
- [x] 3.3 Nothing that the system cannot do: no history, no recents, no library, no sample file, no
      feature list, no settings, asserted over the surface's renderable strings.
      Twenty terms swept over `ImportFlowCopy`'s values **and** the surface's own remaining literals —
      scoped to what this surface can render, never the repository, and never its documentation.
      **Seen to fail.** *"Or open a recent file from the library."* — 2 issues, naming `recent` and
      `library` separately. Reverted, checksum verified.
      **And the control this slice exists for, now that the victim is rendered.** The surface stopped
      delivering the guarantee while `ImportFlowCopy` kept the value: group 1's value tests stayed
      **green, 12/12** — the string still existed — and this group's surface contract failed with **5
      issues across 4 tests**. That is the whole distinction: it is not enough for the sentence to exist,
      the surface has to say it. Reverted, checksum verified. **Task 8.3 stays open**: its literal victim
      is 1.2 and it belongs to group 8.

## 4. Working

- [x] 4.1 An indeterminate indicator plus the status line, and the primary action **present and
      unavailable** rather than removed.
      Both inside the region group 2 built — `ProgressView()` and `Text(ImportFlowCopy.inspecting)` in one
      row — because a spinner alone leaves the reader to infer what is happening from an animation. The
      indicator is asserted indeterminate, and `ProgressView(value:` is refused across the whole surface.
      The action stays in the **frame**, so it neither moves nor disappears, and is unavailable through
      the running state itself rather than a second reading of the flow. A control that vanishes reads as
      a bug and takes everything below it with it. That a second selection starts nothing is already
      pinned by `ImportFlowModelTests.aSecondSelectionIsIgnoredWhileOneIsInFlight`, and a drop by
      `ImportFlowDropTests.aDropIsIgnoredWhileAnInspectionIsInFlight`; neither is restated here.
- [x] 4.2 **The running state names no file**, because it also covers the moment before one has been
      chosen (`design.md` §1, §11). Asserted from the presentation value, which has no file to name.
      Structural on both sides. `PreInspectionPresentation.working` carries no associated value — asserted
      against the declaration — so there is nothing for the surface to name; and the running branch is
      asserted to render **no string literal of its own**, so a name, a stage or a figure cannot be
      slipped in beside the value. Thirteen stage words are swept as well: the flow distinguishes no
      stage, so naming one would be a claim about something nothing observes.
      **Seen to fail.** `Text("Inspecting example.wav…")` in the running branch — **4 issues across 3
      tests**, including the literal the branch may not have. Reverted, checksum verified.
- [x] 4.3 No cancellation is offered, and the reason is recorded rather than assumed: `ImportFlowModel`
      exposes none, and dismissing the panel is already neutral.
      Asserted at the source of the absence rather than at the surface: the flow declares no
      `cancel`/`stop`/`abort`, and its task stays private, so **there is no capability for a control to
      call**. The distinction is written into the surface itself — dismissing the open panel ends the
      *selection*, which the flow already treats as neutral, and is not cancelling an inspection. Six
      stopping words are swept over everything the surface can render.
      **Seen to fail.** `Button("Cancel")` in the running branch — **5 issues across 3 tests** in two
      suites: the action count from both this group and group 3, the branch's literal, the region holding
      a button, and the stopping-word sweep naming `cancel`. Reverted, checksum verified.
- [x] 4.4 **Negative control — a claimed quantity would be caught.** Add a percentage to the running
      state temporarily and demonstrate 1.5 fails; revert.
      The mutation was chosen to attack the guard where it is weakest: `Text("\(ImportFlowCopy.inspecting)
      50%")` — an interpolation in the view that a value-only sweep cannot see, which is how a figure
      would realistically arrive. **1.5's value half stayed green and its source half failed**, which is
      exactly the division of labour it was written with: **4 issues across 4 tests**, one of them 1.5's
      own, naming the file, the line and the literal. Reverted, checksum verified before the next control
      was applied.

## 5. Failed

- [x] 5.1 The flow's message, presented unaltered, with a non-colour marker beside it so the failure does
      not depend on red.
      The message is still the associated value: `Text(message)`, with no prefix, no interpolation, no
      `String(format:)` and no constant of this surface's standing in for it — asserted, and the copy
      owner is asserted not to restate it either.
      **The marker is a symbol, not a word**, and that is deliberate: `design.md` §6's copy table fixes
      exactly two things for this state — the flow's sentence and the recovery label — so a failure
      heading would be visible copy outside the agreed contract. `exclamationmark.triangle.fill` carries
      the distinction by **shape**, and is **hidden from assistive readers**, because the sentence beside
      it already says what happened in words and announcing a warning triangle first would repeat the
      meaning rather than add to it. Red stays as reinforcement rather than as the carrier.
- [x] 5.2 The way forward: the primary action, named for choosing a file rather than for retrying one,
      and the drop still accepted.
      `ImportFlowCopy.chooseAnotherFile`, rendered once, chosen by a **total switch** over the three
      states — so the word varies and the action does not: one `Button`, one `model.selectAndInspect()`,
      the same call idle's makes. Available while the failure is shown, and disabled from exactly one
      place. The drop is untouched: `RootView` passes `isInspecting: flow.state == .working`, so a failed
      surface accepts a valid drop exactly as an idle one does.
      **The guard was widened after the first control exposed a hole in it.** Disabling is not the only
      way to build a dead end — *hiding* the action would have left every assertion true — so the frame
      is now required to carry no branch at all: only the region varies, and nothing in the frame can
      vanish.
- [x] 5.3 No action on this surface is named *try again*, *retry*, *repeat* or *run again* — asserted
      over the renderable strings, with the reason in the assertion: nothing about the failed selection
      is retained (ADR-0010, ADR-0013).
      Nine terms swept over the copy owner's values and the surface's own literals. The reason is
      asserted at its source as well: the flow declares no `retry`, no `rerun`, no `lastURL`, no
      `lastSource`, no `bookmarkData` and no `retainedURL`, so there is nothing a repeat could act on.
- [x] 5.4 The failure is not presented as a report, and a globally failed **report** still reaches the
      workspace rather than this surface — the distinction `ImportFlowModel` already draws, asserted here
      so this slice cannot blur it.
      Two boundaries. The projection still refuses a report outright, and the surface is asserted to name
      no report or workspace type — matched on **word boundaries**, because this surface's own
      `PreInspectionPresentation` contains one of those names as a substring. The failure is also
      asserted not to be dressed as an outcome: no status, verdict, conclusion, code, export or detail.
      **A conflation with the report's own vocabulary is structurally impossible**, not merely untested:
      `FeatureImport` depends on `AudioInspectorDomain` alone and cannot see `FeatureAnalysis`.
      **Seen to fail** on the conflation that *is* reachable — `case let .report(p): self = .failed(…)` —
      **5 issues across 4 tests** in two suites. Reverted, checksum verified.
- [x] 5.5 **Negative control — a dead end would be caught.** Remove the way forward from the failed state
      temporarily and demonstrate 5.2 fails; revert.
      Run twice, and the first run is the more useful of the two. **Disabling** the action failed 2 tests
      — but it also revealed that *hiding* it would not have been caught, so the guard was widened before
      the control was repeated. **Hiding** it then failed the widened assertion by name, quoting the
      branch it added. Reverted and checksum-verified between the two.
      **And the wording control beside it.** Restoring `"Try again"` failed **5 issues across 3 tests**,
      and — this is the part that matters — the vocabulary guard fired **independently** of the
      exact-copy contract, on `try again` and on `again`. The misleading word is refused on its own
      terms, not merely as a side effect of the right one going missing. Reverted, checksum verified.

## 6. Drag and drop — preserved, and proved preserved

- [x] 6.1 The drop destination is still the **whole window**, in every state, and the overlay is
      unchanged. Asserted at the composition root rather than argued from the diff.
      Asserted in `RootView` where it is wired: one destination, attached to the root **after** the branch
      that chooses between the pre-report surface and the workspace closes — so it applies to every state
      rather than to whichever is on screen — with the overlay on the same root. And from the other side:
      the surface installs no destination of its own and swallows nothing the window is listening for
      (`.dropDestination`, `.onDrop`, `.contentShape`, `.allowsHitTesting`, `.onTapGesture`, `.gesture`
      are all absent from it). The three refusals keep their exact words and their single home, and the
      alternative is asserted to be a `Text` that names *this window* — no box, no zone, no second target.
      `RootView` is **untouched by this slice**: 0 lines of diff against `main`.
- [x] 6.2 The existing drop suites — `DroppedSourceTests`, `ImportFlowDropTests`,
      `DroppedSourceInspectionTests` — pass unmodified. **None is edited by this slice**; if one becomes
      impossible to write in the same words, that is a finding about the slice.
      All three pass, and `git diff main..HEAD` over the three files is **empty**. The stronger claim
      holds too: **no pre-existing test anywhere is edited by this slice** — every test file it touches is
      one it created.
- [x] 6.3 **Negative control — losing the alternative would be caught.** Remove the drag-and-drop line
      from the surface temporarily and demonstrate 3.1 fails; revert.
      **Seen to fail with 6 issues across 5 tests** in two suites: 3.1's own render-order and
      rendered-once assertions, the one that requires it to be a sentence rather than a control, and this
      group's own. Reverted, checksum verified.

## 7. Accessibility and the keyboard

- [x] 7.1 Focus follows reading order, and the primary action is reachable and invocable from the
      keyboard alone.
      The one action is the window's **default**, so Return begins an inspection (`design.md` §7). Focus
      order is reading order because nothing rearranges it: no `FocusState`, no `.focused`, no
      `.prefersDefaultFocus`, no `.focusable` and no decorative control to sit in the way — asserted.
- [x] 7.2 The running state and the failure are **announced**, not conveyed by an animation or a colour.
      Each is a coherent element whose words carry the meaning: the running indicator and its sentence are
      combined into **one** element, so it is heard as one thing rather than an indicator to be joined to
      a sentence; the failure's symbol is hidden and the flow's sentence is the element.
      **Announcement here means *reachable and readable*, not a live interruption**, and that reading is
      the documents': the capability requires the state to be *"stated in words"*, and `design.md` §7
      defers the traversal audit to R9. It is also the only safe reading — the running state begins while
      the system's open panel is key, so an unprompted announcement would interrupt a person mid-selection
      to tell them what they had just asked for. Nothing takes focus, asserted.
- [x] 7.3 Every element that carries meaning carries it in words; nothing on this surface means anything
      by colour alone.
      Colour appears in **exactly one** place on the whole surface — asserted by count — and that place is
      the failure, which also carries a symbol and the flow's sentence. Nothing is behind a pointer
      either: no `.help`, no `DisclosureGroup`, no `.popover`, no `.onHover`.
- [x] 7.4 The full traversal audit is **R9's** and is not attempted here — recorded so its absence is a
      decision.
      What is *not* done: VoiceOver rotor behaviour across the app, the reading order of the report
      surface, Dynamic Type at accessibility sizes, and the human pass. This slice covers its own surface
      and states the boundary rather than implying the rest was checked.

## 8. What must still be true afterwards

- [x] 8.1 **The surface is not a section.** `WorkspaceSection` still has exactly its five cases, the
      section navigation is still built only inside the report surface, and no case exists for an empty,
      idle, working or failed state. R1's own suites pass unmodified.
      Five cases in order, no section named for a pre-report state, the pre-report surface naming no
      navigation type, and the navigation built further down `RootView` than the surface it is not part
      of. R1's three suites pass, unedited.
- [x] 8.2 **Negative control — a sixth section would be caught.** Add an empty-state case to
      `WorkspaceSection` temporarily and demonstrate 8.1 and R1's contract suite fail; revert.
      **Seen to fail with 8 issues across 5 tests in 4 suites** — 8.1's own, **R1's**
      `WorkspaceSectionContractTests`, `WorkspaceNavigationLifecycleTests` and `WorkspaceOwnershipTests`.
      R1's guards bite on R2's mistake, which is the point of asserting the boundary from both sides.
      Reverted, checksum verified.
- [x] 8.3 **Negative control — losing the trust statement would be caught.** Delete the read-only
      sentence temporarily and demonstrate 1.2 fails; revert. It is the control this slice exists to make
      possible: nothing protects that sentence today.
      Run against the finished surface, in **both** of its forms. Deleting the value failed **5 issues
      across 4 tests**, 1.2's own among them. Then the half that only exists now the surface renders it:
      keeping the value and dropping the render failed **7 issues across 5 tests in 4 suites** — the
      sentence still existed and the product had stopped making the promise. Reverted between the two and
      verified by checksum.
- [x] 8.4 The file-access guarantees are untouched, asserted rather than asserted-by-diff: the panel's
      configuration, the drop's acceptance rules, the entitlements, the absence of a bookmark and the
      absence of any retained URL.
      Read at the three places they live: the panel's `allowedContentTypes = [.audio]`,
      `allowsMultipleSelection = false` and `canChooseDirectories = false`; the drop's whole-payload
      refusal, its `conforms(to: .audio)` and its directory check; and the coordinator's paired
      start/stop of security-scoped access. Nothing retains a location — `bookmarkData`, `lastURL`,
      `retainedURL`, `storedURL` and `UserDefaults` are absent from the flow, the surface and the
      coordinator alike. `OfflineConfigurationTests` covers the entitlements and is unedited.
- [x] 8.5 The export and `schemaVersion` 1 are unreachable from this surface and unchanged.
      The surface names no export type, no exporter, no coordinator and no `schemaVersion` — and could
      not: it has no report to export, and `FeatureImport` cannot see the export at all. The JSON suites
      pass, unedited.
- [x] 8.6 One PCM read per inspection, unchanged — this slice causes no read and no recomputation.
      The surface names no decoding, no analysis and no sample type: it renders what the flow already
      holds, so it can cause neither a read nor a recomputation. `SharedPCMDecodeCountTests` — the suite
      that counts reads at the port — passes, unedited.

## 9. Gates

- [x] 9.1 Four gates green — `./Scripts/check-boundaries.sh`, `swift build -Xswiftc -warnings-as-errors`,
      `swift test` twice, `openspec validate --all --strict` — plus the Xcode macOS build and
      `git diff --check`. All green; the figures are in the final report.
- [x] 9.2 A focused run over this slice's own suites, and the full suite with **no existing test
      modified**.
      Six suites of this slice's own, and the full suite green twice. **No pre-existing test is modified**
      — `git diff --name-only main..HEAD -- Tests` lists only files this slice created. Three assertions
      *inside those files* were adjusted as later groups landed, each recorded where it happened: two were
      *"not yet"* markers for the group that followed, and one counted switches as a proxy for *one
      region*. Every semantic assertion they carried survives, in the suite that now owns it.

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
