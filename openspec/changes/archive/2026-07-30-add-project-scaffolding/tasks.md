# Implementation Tasks

Scaffolding only — no product behavior. Each group is a small, coherent commit.

## 1. OpenSpec change

- [x] 1.1 Create the `add-project-scaffolding` change (proposal, spec, design, tasks); `openspec validate --strict` passes

## 2. Package skeleton

- [x] 2.1 Add `Package.swift` (`AudioInspectorKit`, tools 6.2, Swift 6 mode, macOS 15) with the seven targets + one test target, wired per the dependency rule; no external deps, no executables
- [x] 2.2 Add a placeholder source per target (empty public namespace; no invented APIs)
- [x] 2.3 Add `AppContainer` (minimal composition root) and an empty `RootView` in `AudioInspectorApp`

## 3. Smoke tests

- [x] 3.1 Add one link/compile test per target in `AudioInspectorKitTests` (Swift Testing)

## 4. macOS Xcode app

- [x] 4.1 Add `App/AudioInspector.xcodeproj` with a SwiftUI `@main` app (empty window) linking the `AudioInspectorApp` product, bundle id `com.donatogomez.audioinspector`, macOS 15, App Sandbox entitlement
- [x] 4.2 Verify with `xcodebuild` (signing disabled)

## 5. CI

- [x] 5.1 Update `.github/workflows/ci.yml` to run `./Scripts/check-boundaries.sh`, `swift build`, `swift test`

## 6. Quality gate

- [x] 6.1 `swift build` clean (no warnings), `swift test` green, `./Scripts/check-boundaries.sh` passes, `openspec validate --strict` passes; review concurrency and module dependencies
