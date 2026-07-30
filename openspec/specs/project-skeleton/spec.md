# project-skeleton Specification

## Purpose
TBD - created by archiving change add-project-scaffolding. Update Purpose after archive.
## Requirements
### Requirement: The package builds with all approved targets

The `AudioInspectorKit` Swift package SHALL build successfully with `swift build`, declaring exactly
the seven approved targets (`AudioInspectorDomain`, `AudioInspectorAnalysis`, `AudioInspectorMedia`,
`AudioInspectorTesting`, `FeatureImport`, `FeatureAnalysis`, `AudioInspectorApp`) plus one test
target, using `swift-tools-version: 6.2`, Swift 6 language mode, a macOS 15 platform, and no
external or CLI/executable targets.

#### Scenario: Clean build succeeds

- **WHEN** `swift build` is run on a clean checkout
- **THEN** all targets compile and link with no errors and no warnings

### Requirement: Module boundaries are enforced

The skeleton SHALL respect the approved dependency rule: `AudioInspectorDomain` depends on nothing;
`AudioInspectorAnalysis` and `AudioInspectorMedia` depend only on `AudioInspectorDomain`; the two
feature targets depend only on `AudioInspectorDomain`; `AudioInspectorApp` (composition root) depends
on the domain, analysis, media, and feature targets. The boundary check SHALL pass.

#### Scenario: Boundary check passes

- **WHEN** `./Scripts/check-boundaries.sh` is run against the populated `Sources/`
- **THEN** it reports no violations and exits zero

### Requirement: The app launches to an empty window

The macOS app target SHALL provide a SwiftUI `@main` entry point that builds and presents an empty
window, obtaining its root view from the `AppContainer` composition root, with no product logic.

#### Scenario: App target builds

- **WHEN** the Xcode app target is built for macOS
- **THEN** it compiles, links the `AudioInspectorApp` library, and produces a launchable app whose
  window is empty

### Requirement: Each target links in tests

There SHALL be one minimal smoke test per target that imports the target and verifies it links and
compiles, without exercising any functional behavior.

#### Scenario: Smoke tests pass

- **WHEN** `swift test` is run
- **THEN** one link/compile test per target passes and no functional behavior is asserted

