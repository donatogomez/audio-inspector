## Context

The MVP proved the vertical slice select → inspect → report → export. This change adds a second way to
perform the *select* step without touching anything downstream of it. Two project rules dominate the
design:

- **`URL`, AppKit and the sandbox live only in `AudioInspectorApp`** (OVERVIEW §2, ADR-0010). The naive
  implementation — putting `.dropDestination` inside `ImportFlowView` — would pull a filesystem location
  into a feature module, and `Scripts/check-boundaries.sh` would **not** catch it, because `URL` comes
  from Foundation, which features are allowed to use.
- **No significant behaviour may be duplicated.** The panel flow already owns a state machine
  (re-entrancy guard, neutral cancellation, error mapping). A parallel drop implementation would drift.

The API was chosen against the installed SDK (MacOSX26.5 / Xcode 26.6 / Swift 6.3.3), not from memory,
and verified by compiling for a macOS 15 deployment target under `-warnings-as-errors`. Rationale,
alternatives and consequences live in **ADR-0014**; this document fixes the architecture.

## Goals / Non-Goals

**Goals:** one more entry point into the *existing* pipeline; identical results whichever entry point is
used; features that never see a location; a rejection path that cannot destroy work already on screen.

**Non-Goals:** batch/multi-file import, dragging out of the app, file promises, persistence or
bookmarks, any DSP, any redesign of the report surface, any change to the JSON contract or the exporter.

## Decisions

### Where the drop lives

- **`.dropDestination(for: URL.self, action:isTargeted:)` is applied in `RootView`**, inside
  `AudioInspectorApp` — the same layer that already owns `SourceSelection` (`NSOpenPanel`) and
  `ReportExportDestination` (`NSSavePanel`).
- **The whole window is the drop target.** The modifier is attached to `RootView`'s outer container, so
  it is active both in the initial state and while a report is displayed.
- **`RootView` receives `[URL]` and validates it** before anything else runs: exactly one element, the
  element is a file URL, and it is not a directory. This restores by code the guarantees `NSOpenPanel`
  provided by configuration (`allowsMultipleSelection = false`, `canChooseDirectories = false`,
  `allowedContentTypes = [.audio]`).
- **A multi-item drop is rejected in full.** The first element is never taken silently.
- **URL normalisation, if required, happens in `AudioInspectorApp`**, at the drop boundary, before the
  domain reference is built. Whether it is required at all depends on the manual observation in task 2:
  file-reference URLs (`file:///.file/id=…`) are documented for the `NSItemProvider` path, **not** for
  `dropDestination(for: URL.self)`, and this design asserts nothing about Finder's behaviour until that
  task reports. If only the drop can produce them, the drop adapter owns the normalisation and
  `AudioFileReferenceMapper` stays untouched; if the panel could produce them too, the mapper would be
  the correct owner — a decision to be taken on evidence, not on convenience.
- **The feature receives an opaque action, never the URL.** `AudioInspectorApp` builds a
  `SourceInspectionAction` closure that captures the validated URL; `FeatureImport` only invokes it.

### Reuse of the existing pipeline

`SourceInspectionCoordinator` takes `chooseSource: @MainActor () async -> URL?`. A drop is a provider
that already knows the answer:

```
SourceInspectionCoordinator(chooseSource: { validatedURL })
```

Everything downstream is reused unchanged — the `isFileURL` guard, the balanced
`start`/`stopAccessingSecurityScopedResource()`, `AudioFileReferenceMapper`, the real
`AVFoundationAudioFilePropertyReader`, `InspectAudioFileUseCase`, and the `SourceInspectionOutcome`
vocabulary. **Not one line of the coordinator, the mapper, the reader or the use case changes.** There
is no second pipeline.

The security-scope handling needs no adjustment: Apple DTS documents that drag & drop URLs carry an
auto-started extension, so `startAccessingSecurityScopedResource()` may return `false` while the file
stays readable — and the existing code already calls it unconditionally and balances only a `true`.

### Shared state machine

`ImportFlowModel` keeps exactly one implementation of the transitions. The extraction is minimal:

```
public func selectAndInspect() async          // panel — signature and semantics unchanged
    → await inspect(using: action)

public func inspect(using action: SourceInspectionAction) async
    guard state != .working else { return }   // re-entrancy: unchanged, now shared
    clear any pending rejection
    let previous = state
    state = .working
    switch await action() {
        .inspected(report) → state = .report(report)
        .cancelled         → state = previous        // neutral cancellation: unchanged
        .preparationFailed → state = .failed(message:)
    }
```

Consequences, all by construction rather than by convention:

- panel and drop share **the same** transitions — it is literally the same body;
- panel cancellation still restores the previous state, and a drop never produces `.cancelled`;
- a valid drop starts the inspection immediately;
- re-entrancy stays impossible: a drop while `.working` is ignored;
- from a report, a valid drop moves the flow to `.working` — **the report stops being displayed while
  the inspection runs, and the new report appears when it completes.** This is exactly what
  `Choose another file…` already does; the panel's behaviour is deliberately not altered, and no
  progress overlay is introduced over the report.

### Rejection as an orthogonal channel

A rejected drop must **not** become `.failed`: that would discard a report already on screen because the
user dropped two files by accident. Rejection therefore never enters `ImportFlowState`.

- `ImportFlowModel` gains `DropRejection?`, exposed read-only and set through a small method.
- `DropRejection` is a **small enum owned by `FeatureImport`**, carrying no `URL`, no AppKit type and no
  filesystem type — a semantic reason (multiple items, not a local file, busy), rendered as text by the
  view.
- It is **not part of the state**: it participates in no transition, and a valid selection or drop —
  from either entry point — clears it.
- A rejection leaves `state` untouched, so any previous report survives intact.
- The feedback is brief, neutral, recoverable and accessible: real text, never colour alone, never a
  path or URL.

The state belongs to `FeatureImport`, not to `RootView`, so all import feedback stays in one observable
place instead of being split across two layers.

### UX

- Highlight while the window is targeted, driven by the `isTargeted` closure held in a `RootView`
  `@State`.
- **The feedback is instructive, not confirmatory: "Drop one audio file".** The chosen overload reports
  targeting as a bare `Bool` and does not expose the items until the drop is performed, so the app
  cannot claim the content is valid beforehand. The highlight means only that the window is the target
  of a drop operation.
- The initial copy mentions both mechanisms and keeps the read-only promise visible.
- During `.working` the drop is declined and no highlight is shown, so the window does not invite a
  gesture it will ignore. (The chosen overload has no `isEnabled:` parameter — that belongs to the
  macOS 26 form — so this is handled in the action.)
- **The `Choose audio file…` button remains the primary, visible path.** Dragging is inherently
  mouse-dependent and never replaces it.
- The report surface is not redesigned.

### Boundaries

A new rule in `Scripts/check-boundaries.sh` rejects, in `Sources/Feature*`, `import AppKit` and real use
of the `URL` type. It must inspect only feature sources, filter comment lines so prose such as *"this
model never learns about `URL`s"* does not trip it, match `URL` as a whole word so `fileURL` and
`URLSession` do not false-positive, and leave `import Foundation` permitted. It ships with a controlled
negative check, so a broken pattern cannot silently become a rule that never fires.

Verified in a dry run before being specified: without comment filtering the rule matches **6 existing
lines, all of them comments**; with it, the current tree is clean, and a simulated
`let u = URL(fileURLWithPath: p)` is still caught.

## Risks / Trade-offs

- **Security-scope survival across the async boundary.** The drop handler is synchronous; the inspection
  is `async`. Only observable in a signed, sandboxed `.app` — `swift test` runs unsandboxed. Escalation
  if it fails: acquire the scope inside the handler; and only if that is insufficient, an **in-memory,
  never persisted** bookmark round-trip. This is the change's primary risk.
- **The shape of the URL Finder delivers is unverified.** It decides whether normalisation is needed and
  who owns it; task 2 settles it before the implementation is fixed.
- **Pre-drop type filtering is lost** with `URL.self`: the cursor accepts folders, bundles and browser
  links that are then rejected. Accepted price of not using `NSItemProvider` (ADR-0014); mitigated by
  immediate, specific rejection feedback.
- **A soft-deprecated overload is adopted deliberately.** Verified to compile for macOS 15 under
  `-warnings-as-errors` with no deprecation diagnostic; migration to the `DropSession` form is inevitable
  when the deployment target rises.
- **Silent no-op drops.** SwiftUI drag & drop does not support file promises, so dragging from Mail or
  Photos may deliver nothing. Any drop that yields no usable file must produce visible feedback.
- **Regression risk on the panel path** from extracting `inspect(using:)`. Mitigated by requiring the
  existing `ImportFlowModelTests` to stay green **without being modified**.
- **Multiple-window ownership (future, non-blocking).** The current design assumes one independent flow
  model per `RootView`. If the app later supports multiple windows or document-style sessions, each drop
  must be routed only to the receiving window and no inspection state may be shared across windows.
  Nothing in this change decides that question — it is recorded here so a later windowing slice does not
  inherit the single-window assumption silently.

## Migration Plan

Additive only. No stored data, no schema, no public API of the package changes; the JSON contract and the
exporter are untouched, so no report produced before this change becomes invalid.

## Open Questions

- Does `dropDestination(for: URL.self)` ever deliver a file-reference URL from Finder, and does the
  auto-started sandbox extension survive the asynchronous hop? Both are settled by task 2 (manual,
  sandboxed observation) before the routing implementation is finalised.
