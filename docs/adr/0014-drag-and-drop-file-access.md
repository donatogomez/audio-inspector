# ADR-0014: Drag & drop as a second explicit user-selection mechanism

- **Status**: Proposed
- **Date**: 2026-08-04
- **Deciders**: Project maintainer
- **Related**: ADR-0010 (sandboxed temporary access — extended, not modified), ADR-0013 (user-selected
  read-write — extended, not modified), ADR-0002 (deployment target macOS 15), ADR-0011, SECURITY.md,
  docs/privacy.md, change `add-drag-and-drop-file-import`

## Context

Today the only way to start an inspection is the native open panel (`NSOpenPanel`, wrapped by
`SourceSelection`). Dragging a file onto the window is the idiomatic macOS gesture for "inspect this",
and its absence is the most obvious friction in the shipped MVP.

Adding it touches the two areas this project treats as load-bearing:

- **Sandboxing and access.** ADR-0010 fixed *how* access is obtained and released; ADR-0013 fixed
  *which* entitlement covers it. Both are phrased in terms of **panels**: ADR-0013 states the scope
  is "items chosen through a panel". A drop is an equally explicit user choice, but it is not a panel,
  so the recorded scope does not literally cover it.
- **Architecture.** `URL`, AppKit and the sandbox are confined to `AudioInspectorApp` (OVERVIEW §2,
  ADR-0010). A drop modifier naively placed in a feature module would drag a filesystem location into
  `FeatureImport`, and `Scripts/check-boundaries.sh` would not catch it because `URL` comes from
  Foundation, which features may use.

The API landscape is also constrained. Against the installed SDK (MacOSX26.5, Xcode 26.6, Swift 6.3.3)
with a macOS 15 deployment target, three generations coexist:

1. `onDrop(of:isTargeted:perform:)` + `NSItemProvider` (macOS 11);
2. `dropDestination(for:action:isTargeted:)` + `Transferable` (macOS 13);
3. `dropDestination(for:isEnabled:action:)` + `DropSession` (macOS **26**).

Generation 3 is the successor Apple points to, and is unreachable from a macOS 15 target. Generation 2
carries a *soft-deprecation* marker (`deprecated: 100000.0`) that names generation 3 as its
replacement. Generation 1 carries **no** deprecation annotation at all for its `UTType` overload.

## Decision

- **Panel and drag & drop are two mechanisms of the same thing: an explicit, per-item user selection.**
  Both grant access through the powerbox; neither widens what the app can reach. This record extends
  the scope phrasing of ADR-0010 and ADR-0013 to cover the drop, and nothing else about them changes.
- **The existing entitlement is unchanged.** `com.apple.security.app-sandbox` plus
  `com.apple.security.files.user-selected.read-write` already cover a dropped item. **No entitlement is
  added, and no folder-wide or system-wide access is introduced.**
- **Access stays temporary.** `startAccessingSecurityScopedResource()` is called on the dropped URL and
  balanced in a `defer`, held only for the duration of one inspection — the ADR-0010 rule, reused
  verbatim. Apple DTS documents that panels and drag & drop have "auto start" behaviour, so the call
  may return `false` while the file remains readable; the existing code already treats `false` as a
  non-error and only balances a `true`.
- **No bookmarks, no persistence.** Nothing is retained after the inspection. ADR-0004's deferral and
  ADR-0010's "no bookmark persistence in this phase" stand unchanged.
- **The same `SourceInspectionCoordinator` runs both paths.** Its `chooseSource` seam already abstracts
  *where the URL comes from*; a drop is a provider that already knows the answer. **No second pipeline,
  no second coordinator, and no change to the coordinator, the mapper, the reader, or the use case.**
- **`URL` and AppKit remain confined to `AudioInspectorApp`.** The drop modifier lives in `RootView`;
  `FeatureImport` receives an opaque action plus safe visual state, never a location. A boundary rule
  will enforce this statically, because the compiler cannot.
- **Selected API: `View.dropDestination(for: URL.self, action:isTargeted:)`** (macOS 13+), with
  `URL.self` as the payload type.
- **A drop carrying more than one item is rejected in full.** The first item is never chosen silently:
  picking one of several would be a selection the user did not make, which contradicts "explicit
  choice". Rejection preserves whatever was on screen and starts no inspection.
- **Targeting feedback is instructive, not confirmatory.** The chosen overload reports targeting as a
  bare `Bool`; the items are unavailable until the drop is performed, so the app cannot know whether
  the content is acceptable beforehand. The highlight therefore states what is expected ("Drop one
  audio file"), never that the current payload is valid.
- **No URL normalisation is performed.** A sandboxed observation (below) found conventional path URLs in
  every case tested, so no normalisation is introduced, `filePathURL` is not consulted, no
  file-reference adapter exists, and `AudioFileReferenceMapper` is untouched. Preventive normalisation
  would be code defending against a condition never observed.

## Alternatives considered

- **`dropDestination(for:isEnabled:action:)` with `DropSession` (generation 3).** The API Apple points
  to, and the only one that could inspect a payload before the drop completes (which would make the
  targeting highlight confirmatory rather than instructive). It is `@available(macOS 26.0)`; a macOS 15
  target cannot call it without an `if #available` branch and a second implementation of the same
  behaviour. **Rejected as unreachable**, to be adopted when the deployment target rises.
- **`onDrop(of: [UTType], isTargeted:perform:)` with `NSItemProvider` (generation 1).** Its real
  advantage is genuine `UTType` filtering at drag-session level, so the cursor would reject a non-audio
  item before the drop. Note honestly that **this overload carries no deprecation annotation** — it is
  not being rejected for being obsolete. It is rejected because it rests on `NSItemProvider`, the
  mechanism `Transferable` replaced; because of a completion-callback defect reported specifically on
  macOS 15, where `loadObject`'s completion does not fire until the drag exits; and because its
  file-representation path is documented to deliver obscured temporary files. **Rejected on technical
  grounds, accepting the loss of pre-drop type filtering.**
- **`onDrop(of: [String], …)` and the `DropDelegate` variants.** The `[String]` overload is itself
  soft-deprecated in favour of the `UTType` one, and `DropDelegate` adds substantial surface over the
  same `NSItemProvider` substrate. **Rejected.**
- **A custom `Transferable` using `FileRepresentation(importedContentType: .audio)`.** This would
  restore `UTType` filtering within the modern API. It is rejected because **it can hand back a copy of
  the file rather than the original**, and the SDK says so in its own signatures:
  `FileRepresentation.init(importedContentType:shouldAttemptToOpenInPlace:importing:)` defaults
  `shouldAttemptToOpenInPlace` to `false`, the parameter name concedes it is only an *attempt*, and
  `ReceivedTransferredFile` exposes `isOriginalFile: Bool`, making file identity a runtime question.
  Audio Inspector derives `displayName`, `sizeBytes` and `modifiedAt` from the received URL, and
  `displayName` travels into the exported JSON's `source` object — the very field ADR-0010 defines as
  the safe representation of the origin. Reporting a temporary copy's name and modification date would
  be **a fabricated value**, breaking product invariant #2 ("never invent a value"). **Rejected on
  correctness, not on taste.**
- **Placing the drop modifier inside `FeatureImport`.** Simplest to write, and it would put the
  affordance next to the UI that shows it. It would also give a feature module a filesystem location,
  contradicting ADR-0010 and OVERVIEW §2 — and it would do so **silently**, since the boundary script
  cannot currently see it. **Rejected**; the modifier lives in `RootView` and a new boundary rule closes
  the gap.
- **Mapping a rejected drop to the existing `preparationFailed` outcome.** Cheapest possible wiring, and
  it reuses vocabulary that already exists. But that outcome drives the flow into `.failed`, which would
  **discard a report already on screen** because the user dropped two files by accident. **Rejected**; a
  rejection is reported through a channel orthogonal to the flow state.
- **Selecting the first item of a multi-item drop.** Convenient, and arguably what a user "meant". It
  fabricates a choice out of an ambiguous gesture and depends on an ordering the drag does not
  meaningfully define. **Rejected.**

## Consequences

### Positive

- A second, faster entry point with **no new capability, no new pipeline and no new permission**: the
  drop reuses the coordinator, the security-scope handling, the mapper, the reader and the use case
  exactly as the panel does.
- The permission model stays minimal and per-item; the user still grants every single access.
- The location-free feature boundary becomes **statically enforced** rather than merely documented — a
  guarantee the project did not previously have.
- The panel path is untouched, so its behaviour cannot regress by construction.

### Negative / costs

- **A soft-deprecated API is adopted deliberately.** The chosen overload names its own replacement.
  Verified empirically that it compiles for macOS 15 under `-warnings-as-errors` without emitting a
  deprecation diagnostic, but a future SDK could harden the annotation, and migrating to the
  `DropSession` form is inevitable once the deployment target rises.
- **Pre-drop type filtering is lost.** The cursor will accept folders, app bundles and browser links
  that the app then rejects — the user is told "yes" and then "no". This is the direct price of not
  using `NSItemProvider`, and it is why rejection feedback must be immediate and clear.
- **Targeting feedback cannot be confirmatory** on this API generation, so the highlight promises less
  than a user might expect from it.
- **The sandbox path is not reachable by `swift test`.** The package tests run unsandboxed and unsigned,
  so the behaviour recorded below can only be re-checked in a signed, sandboxed `.app`. **Manual
  validation is part of the definition of done for the implementing change**, not an optional extra.
- **The observation is a sample, not a proof.** It covers the locations and item kinds listed below on
  one machine and one macOS version. Locations and sources it did not cover — iCloud files (downloaded
  or evicted), aliases, symlinks, `.app` bundles and file-promise sources such as Mail — remain
  unobserved, so a file-reference URL is unproven rather than impossible.

### Neutral

- No code in the package depends on the entitlement value; nothing in `Package.swift` changes.
- Should bookmarks arrive with persistence (ADR-0004), this decision is unaffected: the scope stays
  "items the user explicitly selected", by whichever explicit mechanism.

## Evidence from the sandboxed observation

Temporary instrumentation on a signed, sandboxed build recorded booleans only — no path, file name,
extension value or content. What it found:

**Local audio files (Downloads, Music, and another authorised location):** a single item;
`isFileURL == true`; `isFileReferenceURL == false`; `filePathURL` identical to the delivered URL; a
non-empty name and extension; not a directory; conforming to `UTType.audio`.

**Security scope:** `startAccessingSecurityScopedResource()` returned **`false`**, and the file was
readable anyway — both inside the synchronous handler and again after an asynchronous hop, without
re-acquiring anything. The URL still resolved to the same file resource afterwards. This matches the
auto-start behaviour Apple DTS describes for panel- and drop-provided URLs, and it confirms the existing
coordinator pattern is already correct: call `start`, treat `false` as a non-error, and balance with
`stop` only when it returned `true`.

**Rejectable inputs:** a folder arrived as a local URL with `isDirectory == true` and no audio
conformance; a two-item drop arrived with `itemCount == 2`; an image dragged from a web page produced
`itemCount == 0`. All three are distinguishable in the handler, so each can be rejected in full.

**No temporary copy** was involved: the delivered URL pointed at the user's own file throughout.

**Consequences fixed by this evidence:** no normalisation, no `filePathURL`, no file-reference adapter,
no change to `AudioFileReferenceMapper`, no bookmarks of any kind, no scope acquisition outside
`SourceInspectionCoordinator`, and no entitlement change.

## Risks that remain

- The observation is a **sample on one machine and one macOS version**, over the locations and item
  kinds listed above. It does not cover iCloud files (downloaded or evicted), aliases, symlinks, `.app`
  bundles, or file-promise sources such as Mail. Should any of those ever deliver a file-reference URL,
  `displayName` and `fileExtension` would be derived from a meaningless last path component, and that
  name travels into the exported JSON's `source` object. The mitigation is not preventive code but the
  manual validation run, extended over time.
- **Sandbox behaviour is still unreachable from `swift test`**, so every re-check of the above belongs
  to the manual runbook.

## Relationship to ADR-0010 and ADR-0013

Both remain **in force and unmodified**; per `docs/adr/README.md`, accepted ADRs are immutable.

- **ADR-0010** keeps deciding everything it decided: native selection, access held only for the duration
  of a single inspection via balanced `start`/`stopAccessingSecurityScopedResource()`, no bookmark
  persistence in this phase, and the absolute path treated neither as identity nor as export content.
  This record only adds a second mechanism through which the user performs that selection.
- **ADR-0013** keeps deciding the entitlement: `…user-selected.read-write` on the executable, source
  file read-only by design, export destination the only thing written. This record extends its scope
  phrasing — "items chosen through a panel" — to "items the user explicitly chooses, through a native
  panel or by dropping them onto the window". **The entitlement value itself does not change.**

This ADR supersedes nothing.

## Follow-ups

- The implementing change `add-drag-and-drop-file-import` owns the boundary rule, the manual sandbox
  validation, and the minimal corrections to `SECURITY.md` and `docs/privacy.md`, which currently state
  that files are reached only through native panels.
- Migration to `dropDestination(for:isEnabled:action:)` with `DropSession` becomes possible — and the
  targeting feedback can become confirmatory — if and when the deployment target moves to macOS 26.
- Batch import (more than one file per operation) remains explicitly out of scope and would need its own
  change and its own decision.
