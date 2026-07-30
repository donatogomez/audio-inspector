# CLAUDE.md — Audio Inspector

Project rules for AI-assisted work. Global preferences (Spanish communication, Conventional Commits
without AI co-author trailers, native-platform bias) still apply; this file adds the project
specifics.

## What this is

Native **macOS 15+** forensic audio-quality tool. Swift 6 (`swift-tools-version: 6.2`), SwiftUI,
SPM, Strict Concurrency, async/await. Bundle id `com.donatogomez.audioinspector`. Licensed **MIT**.
100% local, never modifies original files, results are probabilistic with explicit confidence. See
[docs/vision.md](docs/vision.md).

## Workflow — spec-driven (OpenSpec)

- **No significant implementation without an approved OpenSpec change.** Specs are the source of
  truth. See [docs/README.md](docs/README.md) for the doc hierarchy.
- OpenSpec 1.1.x flow: `openspec new change <name>` → fill `proposal.md` → `design.md` + `specs/` →
  `tasks.md`; `openspec status --change <name>`; `openspec validate <name> --strict`;
  `openspec archive <name>` after merge. Don't invent commands — check `openspec --help`.
- Run OpenSpec with telemetry off: `OPENSPEC_TELEMETRY=0` (already exported in the maintainer's shell).

## Architecture boundaries (enforced)

Single SPM package `AudioInspectorKit` (multi-target) + a thin Xcode macOS app target (the `@main`
shell). `AudioInspectorApp` is a **library** composition root (no host executable — a library-only
package already `swift build`/`swift test`s from the CLI). Boundaries are the build graph; a helper
script catches full-build leaks.

- **`AudioInspectorDomain` imports nothing** but the standard library / Foundation value types.
  It must NOT import: SwiftUI, AppKit, AVFoundation, AudioToolbox, Accelerate, SwiftData, FFmpeg, or
  use `Process`.
- **`AudioInspectorAnalysis`** = pure DSP: Domain + Accelerate only.
- **`AudioInspectorMedia`** = the ONLY module that imports AVFoundation/AudioToolbox or spawns
  `Process` (FFmpeg/FFprobe). Always pass separated argument vectors — never `sh -c`, never
  interpolate paths. Always select the audio stream explicitly.
- **`Feature*`** modules import Domain (+ a future DesignSystem) only — never Media/Analysis.
- **`AudioInspectorApp`** is the composition root (the only place that wires concretes via DI).
- Run `./Scripts/check-boundaries.sh` before pushing. See [docs/architecture.md](docs/architecture.md).

## Concurrency

Swift 6 complete checking. Mutable shared state ⇒ `actor`; immutable data ⇒ `Sendable` value type;
UI ⇒ `@MainActor`; everything else `nonisolated async`. No `DispatchQueue`, no `@unchecked
Sendable`. `TaskGroup` for bounded parallelism + cancellation. See [docs/concurrency.md](docs/concurrency.md).

## Analysis honesty (non-negotiable)

Separate **evidence / inference / conclusion**; attach a confidence level (`none/weak/medium/strong/
inconclusive`); give alternative explanations; **no aggregate 0–100 score**; never assert
transcoding from a single frequency cutoff. See [docs/analysis-methodology.md](docs/analysis-methodology.md).

## Testing

Swift Testing; fakes-over-mocks via Domain ports; deterministic synthetic fixtures (a future
`SyntheticAudioFactory` in `AudioInspectorTesting`); explicit numeric tolerances; golden files
pinned per engine version; **no copyrighted audio in the repo**. Cross-check loudness vs FFmpeg
`ebur128`. See [docs/testing-strategy.md](docs/testing-strategy.md).

## Commands

```bash
swift build
swift test
./Scripts/check-boundaries.sh
swiftformat --lint . && swiftlint
openspec validate <change> --strict
```

## Git

Work on a branch, never implement on `main`. **Do not commit or push without explicit user
approval.** Small, single-purpose PRs using `.github/pull_request_template.md`.
