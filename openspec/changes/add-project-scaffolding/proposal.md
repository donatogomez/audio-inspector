## Why

The bootstrap defined the architecture, ADRs, principles, and the MVP plan, but there is no
compilable code yet. Before any vertical slice can begin, the project needs a **buildable, empty
skeleton** that encodes the approved module boundaries and gives every future increment a place to
land. This change adds only infrastructure — no Audio Inspector functionality.

## What Changes

- Add `Package.swift` for `AudioInspectorKit` (`swift-tools-version: 6.2`, Swift 6 language mode per
  target, macOS 15) with the seven approved targets and their dependency wiring:
  `AudioInspectorDomain`, `AudioInspectorAnalysis`, `AudioInspectorMedia`, `AudioInspectorTesting`,
  `FeatureImport`, `FeatureAnalysis`, `AudioInspectorApp`. No CLI/host executable, no external
  dependencies.
- Add a minimal placeholder source per target (empty namespaces; no invented APIs).
- Add the `AppContainer` composition root (minimal injection, no logic) and an empty `RootView`.
- Add a minimal macOS Xcode app target (`com.donatogomez.audioinspector`) with a SwiftUI `@main`
  that shows an empty window, reusing the `AudioInspectorApp` library.
- Add one link/compile smoke test per target (no functional tests).
- Update CI to run `swift build`, `swift test`, and `./Scripts/check-boundaries.sh`.

Explicitly **out of scope** (no code for any of these): file import, AVFoundation/AudioToolbox
usage, FFmpeg, DSP/FFT/LUFS/True Peak/spectrogram/waveform/clipping, findings, JSON export,
persistence/SwiftData. This PR does not implement product behavior.

No **BREAKING** changes.

## Capabilities

### New Capabilities

- `project-skeleton`: The buildable, boundary-enforced project skeleton — the package builds, the
  app launches to an empty window, module boundaries hold, and each target links — with no product
  functionality.

### Modified Capabilities

None.

## Impact

- New: `Package.swift`, `Sources/<target>/…` placeholders, `Tests/AudioInspectorKitTests/…` smoke
  tests, `App/AudioInspector.xcodeproj` + app sources/entitlements, updated
  `.github/workflows/ci.yml`.
- Does not touch the `bootstrap-native-macos-audio-analysis-foundation` change, the ADRs, the
  architecture, or the project principles.
