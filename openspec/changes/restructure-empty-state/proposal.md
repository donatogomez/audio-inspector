# Make the surface before a report one shell, and let it say what the app does

## Why

R1 gave the report a workspace. **What a person sees before there is a report was never designed** — it
was written once, early, and has not been revisited since.

Read from production (`ImportFlowView`), the pre-inspection surface today is a centred stack that shows
the same two lines in all three of its states, plus whichever extras apply:

- a title, `Audio Inspector`, which the window's own title bar already says;
- one sentence carrying **three** different jobs at once — what the app does, that a file can be
  dragged, and that the file is not modified;
- a failure message in red, inserted between the sentence and the button;
- a button whose label changes to `Try again` after a failure;
- an indeterminate `ProgressView` while an inspection is running.

Four problems follow from that, and each is a fact about the code rather than a matter of taste:

1. **The three jobs share one sentence, so none of them can be given its own weight.** The read-only
   promise — the app's single trust claim — is the tail of a sentence about drag and drop.
2. **`Try again` names something the app cannot do.** Nothing retains the file that failed: no URL is
   kept and no bookmark is created (ADR-0010, ADR-0013). The button calls `selectAndInspect()`, which
   opens the panel — it is *choose another file*, and it says *try again*.
3. **The running state says nothing.** A bare spinner appears and the surface is otherwise identical to
   the idle one, so the window reads as unchanged rather than as busy.
4. **Nothing protects the read-only sentence.** No test and no requirement mentions it, so the one
   sentence that carries the product's trust promise can be deleted by an ordinary layout edit and
   nothing fails.

This slice fixes the four, and stops there.

## What Changes

- **One shell, three states.** The pre-inspection surface keeps a stable frame — what the app does, and
  the way to begin — and changes only the region beneath it as the flow moves between idle, working and
  failed. A person does not watch the window rebuild itself.
- **The sentence is split into the three claims it was carrying**, so each can sit where it belongs: the
  purpose above the action, the drag-and-drop alternative beside it, and the read-only promise as its
  own quiet line. **No claim is dropped and none is added.**
- **The read-only promise becomes a requirement**, so removing it fails a test rather than passing
  review.
- **The working state states that an inspection is running** and claims no progress it does not have —
  production has no quantitative progress anywhere, so there is no percentage to show and none is
  invented.
- **The failure keeps its own message and gains an honest way out.** The flow's sentence is presented
  unchanged, in words rather than by colour alone, and the action beside it is named for what it
  actually does.

## What This Deliberately Does Not Do

- **No history, no recents, no library, no sidebar.** Nothing persists (ADR-0004, ADR-0010), so there is
  nothing to browse, and ADR-0026 §12 already refused the sidebar.
- **No onboarding, no tutorial, no tips, no sample files, no feature list, no marketing.** The primary
  act is inspecting a file; the surface offers that and gets out of the way.
- **No second call to action.** One primary action, and the drag-and-drop alternative stated once.
- **No `Cancel` button.** Production cannot cancel an inspection that is under way: `ImportFlowModel`
  exposes no cancellation, and the only thing a person can dismiss is the open panel, which the flow
  already treats as neutral. A control that cannot do what it says is worse than none.
- **No retry of the failed file.** The file is not retained, by decision (ADR-0010).
- **No progress figure, no percentage, no phase count, no estimate.**
- **No change to how a file is chosen, accessed or read.** The panel's configuration, the drop's
  acceptance rules, the security-scoped access, the entitlements and the stale guards are untouched.
- **No report content is moved.** Details, Measurements, Waveform and Spectrum are R3–R6; the Inspection
  Overview is R7; comparison mode is R8; the responsive and accessibility passes are R9.
- **No change to R1.** The section navigation stays inside the report surface, and the pre-inspection
  shell does not become a sixth section.

## Impact

- **Capability** — `audio-file-inspection` gains requirements about the surface *before* a report. Its
  existing requirements are untouched: *Select a single local audio file* keeps every clause about the
  two mechanisms, the single file, the targeting wording, the entitlements and the absence of
  bookmarks, and this change adds nothing that could weaken them.
- **Production** — `ImportFlowView` and the copy it renders. `RootView` chooses the surface and is
  otherwise unaffected. **No change to** `ImportFlowModel`, `DroppedSource`, `DropFeedbackOverlay`,
  `DropRejection`, `SourceSelection`, `SourceInspectionCoordinator`, the domain, the export, or
  anything R1 added.
- **Export and `schemaVersion` 1** — untouched, and not reachable from this surface at all.
- **No ADR.** ADR-0026 §1 and §12 already decide that there is one subject, no collection and no
  sidebar; nothing here is a durable architectural choice that a future contributor would otherwise
  have to reverse-engineer. Layout is not an ADR's business.

## Dependencies

- **R1 is merged** (`restructure-inspection-workspace`, PR #52), and this slice depends on it only for
  the guarantee it must not break: the section navigation belongs to the report surface, and the
  pre-inspection shell is not a section.
- Nothing else. R3–R9 are independent of this slice and are not started.
