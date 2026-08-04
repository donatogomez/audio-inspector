## Why

The shipped MVP can only start an inspection one way: the user opens a native panel and picks a file.
Dragging a file onto the window is the idiomatic macOS gesture for "look at this", and its absence is
the most visible friction in the finished slice — a collector comparing several rips has to walk
through the panel every single time.

Nothing about the inspection itself needs to change to fix this. The existing
`SourceInspectionCoordinator` already abstracts *where the file URL comes from* behind an injected
`chooseSource` seam, which its own unit tests exercise today with a constant URL. A drop is simply that
seam supplied by a different gesture. The work is therefore about **routing and boundaries**, not about
inspection.

## What Changes

- The user may start an inspection by **dropping one local audio file anywhere on the app window**, in
  the initial state and while a report is displayed.
- The drop **reuses the existing pipeline end to end** — the same coordinator, the same security-scoped
  access, the same `AudioFileReferenceMapper`, the same AVFoundation reader, the same
  `InspectAudioFileUseCase`, the same report and the same export. There is no second pipeline and no
  second coordinator; the coordinator is extended with a shared body that inspects a URL already
  obtained, and the mapper, the reader and the use case do not change.
- **Exactly one file per operation.** A drop carrying more than one item is rejected in full; the first
  item is never chosen silently, because that would be a selection the user did not make.
- A rejected drop **preserves whatever was on screen**, including a previously shown report, and never
  becomes an inspection failure. Rejections travel on a channel orthogonal to the flow state.
- `URL` and AppKit stay confined to `AudioInspectorApp`; `FeatureImport` receives an opaque action and
  safe visual state, never a location. A new boundary rule enforces this statically, because the
  compiler cannot.
- The open panel keeps working with **no behavioural change whatsoever**.

Selected API, verified by compiling against the installed SDK for a macOS 15 deployment target:
`View.dropDestination(for: URL.self, action:isTargeted:)` (macOS 13+). ADR-0014 records why the
`DropSession` overload (macOS 26) is unreachable, why `onDrop`/`NSItemProvider` is declined despite not
being deprecated, and why a `FileRepresentation`-based `Transferable` is rejected outright.

## Capabilities

### New Capabilities

None. Drag & drop is a second mechanism for an existing capability, not a new one — which is why no
separate `audio-file-import` capability is introduced.

### Modified Capabilities

- `audio-file-inspection`: the requirement *Select a single local audio file* is widened from "through
  the native macOS file-open panel" to "through an explicit user selection — the native panel **or**
  dragging the file onto the window" — while preserving every guarantee it already makes: a single local
  file, the original never modified, App Sandbox with no new entitlement, access held only for the
  operation, no persisted URL or bookmark, no location disclosure, neutral cancellation, and honest
  property states.

## Impact

- **Affected specs:** `audio-file-inspection` (one `MODIFIED` requirement; the other five requirements
  are untouched).
- **Affected code (implementation, not this commit):** `AudioInspectorApp` (`RootView`, `AppContainer`,
  a new dropped-payload validator) and `FeatureImport` (`ImportFlowModel`, `ImportFlowView`, a small
  `DropRejection` value type). Roughly 90 lines of production code and one new source file.
- **New decision:** ADR-0014, extending — without modifying — ADR-0010 and ADR-0013 to cover drag & drop
  as an explicit user selection.
- **Tooling:** a new rule in `Scripts/check-boundaries.sh` rejecting `import AppKit` and real use of the
  `URL` type in `Sources/Feature*`.
- **Documentation:** minimal corrections to `SECURITY.md` and `docs/privacy.md`, which currently state
  that files are reached only through native panels.
- **Explicitly unchanged:** `AudioInspectorDomain`, `AudioInspectorMedia`, `AudioInspectorAnalysis`,
  `FeatureAnalysis`, `SourceInspectionCoordinator`, `SourceSelection`, `AudioFileReferenceMapper`, the
  JSON v1 contract and its exporter, the app entitlements, and `Package.swift`. No new dependency.

**Out of scope:** batch import or multi-file drops, drag & drop *out* of the app, file promises,
persistence, bookmarks, recent files, any DSP (waveform, FFT, spectrogram, loudness, true peak,
clipping, transcode detection), any redesign of the report surface, and any change to the JSON contract.
