## Context

Implements the scaffolding step (Milestone A, group 1) as its own reviewable increment, without
modifying the bootstrap change. Structure and decisions are already fixed by the bootstrap:
[architecture.md](../../../docs/architecture.md), ADR-0001 (SPM boundaries), ADR-0005 (module set),
ADR-0002 (macOS 15), and `docs/project-principles.md` (#13, vertical slices). This document only
records the how, without duplicating those.

## Goals / Non-Goals

**Goals:** a compilable, empty skeleton that (1) encodes the approved boundaries in the build graph,
(2) launches an empty macOS window via a minimal composition root, (3) links every target in tests,
and (4) is covered by CI (`build`, `test`, boundaries).

**Non-Goals:** any product behavior — file import, AVFoundation/AudioToolbox, FFmpeg, DSP, findings,
JSON, persistence. No invented APIs. No DesignSystem/Persistence targets (deferred per ADR-0005). No
CLI/host executable (per ADR-0001).

## Decisions

- **One library product** (`AudioInspectorApp`) is exposed so the Xcode app target can link the
  composition root; other targets stay internal to the package. Test target depends on all targets
  by name.
- **Placeholders are empty public namespaces** (e.g. `public enum AudioInspectorDomain {}`), so
  every target has a compilable unit without inventing APIs.
- **`AppContainer` is a `@MainActor` value type** with an empty `init` and a `makeRootView()` that
  returns an empty `RootView`. No dependencies are wired yet (that arrives with the first slice).
- **The `@main` App lives in the Xcode target**, not in the `AudioInspectorApp` library (the library
  stays unit-testable; the Xcode target adds the bundle/entitlements/sandbox). The entry struct is
  named to avoid colliding with the `AudioInspectorApp` module name.
- **System-framework links (Accelerate/AVFoundation/AudioToolbox) are NOT added yet** — nothing uses
  them. They land in their own vertical slice, keeping this change free of DSP/media dependencies
  and honoring "no invented APIs".

## Risks / Trade-offs

- **Hand-authored `.xcodeproj`** can be fragile → keep the app target minimal (generated Info.plist,
  one Swift file, links the package product) and verify with `xcodebuild` before reporting success.
- **Feature-vs-Media dependency**: the task brief mentioned features depending on Media "when
  necessary"; the approved boundary rule (ADR-0005 / check-boundaries) forbids features importing
  Media/Analysis. Nothing is necessary at the skeleton stage, so features depend on the domain only;
  the App composition root does the wiring. This keeps boundaries intact (flagged, not silently
  changed).

## Open Questions

None blocking. Signing identity for the Xcode target is deferred (CI builds with signing disabled).
