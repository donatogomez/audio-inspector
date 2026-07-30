# Contributing to Audio Inspector

Audio Inspector is developed **spec-first**. Read this before writing code.

## Golden rules

1. **No significant implementation without an approved OpenSpec change.** Specs are the source of
   truth. Code follows an approved proposal + specification, not the other way around.
2. **Never modify a user's original audio files.** All analysis is read-only.
3. **Everything is local.** No network calls for analysis, no telemetry, no uploads.
4. **Treat file paths and names as untrusted input.** Never interpolate them into shell strings;
   always pass separated arguments to `Process`.
5. **Do not work directly on `main`** for implementation. Use a branch per change.

## Environment requirements

Verified working baseline for this project (as of bootstrap):

| Tool | Minimum / used | Notes |
| --- | --- | --- |
| macOS | 15+ (dev on 26.x) | Deployment target is macOS 15. |
| Xcode | 16+ (dev on 26.x) | Swift 6 toolchain. |
| Swift | 6.x | Strict Concurrency enabled. |
| Git | 2.4x | |
| GitHub CLI (`gh`) | optional | For PRs. |
| Homebrew | any recent | To install the dev tools below. |
| FFmpeg / FFprobe | 7+ (dev on 8.1) | **Dev/test dependency only.** See ADR-0003. |
| OpenSpec | 1.1.x | `npm i -g @fission-ai/openspec` |
| SwiftLint | 0.65+ | `brew install swiftlint` |
| SwiftFormat | 0.62+ | `brew install swiftformat` |

Install the toolchain tools:

```bash
brew install ffmpeg swiftlint swiftformat gh
npm install -g @fission-ai/openspec
```

> FFmpeg from Homebrew is a **GPL build**. That is fine for local development and CI, but it has
> distribution implications for any shipped binary. See
> [docs/adr/0003-ffmpeg-vs-native-audio-strategy.md](docs/adr/0003-ffmpeg-vs-native-audio-strategy.md).

## OpenSpec workflow

This project uses the modern OpenSpec artifact workflow (schema `spec-driven`). Do **not** invent
commands — consult `openspec --help` or the skills in `.claude/`.

```bash
openspec list                       # active changes
openspec new change "<kebab-name>"  # scaffold a new change
openspec status --change "<name>"   # artifact progress (proposal → design/specs → tasks)
openspec instructions <artifact> --change "<name>"   # template + guidance for an artifact
openspec validate <name> --strict   # validate a change or spec
openspec archive <name>             # after a change is fully implemented and merged
```

Artifact order for `spec-driven`: **proposal → (design, specs) → tasks**. Every requirement in a
spec MUST have at least one `#### Scenario:` (exactly four hashtags) in WHEN/THEN form.

### Telemetry

OpenSpec collects anonymous usage stats by default. This project opts out. Disable it in your
shell:

```bash
export OPENSPEC_TELEMETRY=0   # or: export DO_NOT_TRACK=1
```

CI sets `OPENSPEC_TELEMETRY=0`. See [docs/privacy.md](docs/privacy.md).

## Architectural decisions

Non-trivial technical choices are recorded as ADRs in [docs/adr/](docs/adr/). Add a new numbered
ADR (copy `0000-adr-template.md`) when you make a decision that future contributors would
otherwise have to reverse-engineer.

## Code quality

- Swift 6, Strict Concurrency, warnings treated as errors.
- Value types by default; correct `Sendable`; explicit actor isolation. No global singletons;
  use dependency injection.
- Typed errors; never silently ignore errors. Structured logging with `OSLog`.
- No `JSONSerialization` (use `Codable`). No completion handlers in new code (use async/await).
- No force-unwrap except where provably safe and commented.
- Domain models depend on **none** of: FFmpeg, AVFoundation, AudioToolbox, Accelerate, SwiftUI,
  AppKit, Core Data, SwiftData, `Process`/shell. See [docs/architecture.md](docs/architecture.md)
  and the enforced boundaries below.
- Run before pushing:

```bash
swift build
swift test
./Scripts/check-boundaries.sh
swiftformat --lint . && swiftlint
```

## Architecture boundaries

The dependency rule is enforced by the SwiftPM build graph (a target sees only its declared deps)
and, as a full-build backstop, by [`Scripts/check-boundaries.sh`](Scripts/check-boundaries.sh):
`AudioInspectorDomain` stays pure; `AudioInspectorMedia` is the only home of AVFoundation/
AudioToolbox/FFmpeg-via-`Process`; `AudioInspectorAnalysis` owns Accelerate; features never import
Media/Analysis. Run the script locally; CI will run it too.

## Pull requests

Small, single-purpose PRs. Fill in [`.github/pull_request_template.md`](.github/pull_request_template.md):
link the approved OpenSpec change, confirm no cross-boundary imports, and paste `swift test` /
`check-boundaries.sh` output. `main` must stay green. See
[docs/testing-strategy.md](docs/testing-strategy.md) for the testing conventions.

## Tests

- Prefer **Swift Testing** for new tests; XCTest only where required.
- Synthetic fixtures are generated **during tests** (sine, silence, clipping, DC offset, white
  noise, 50/60 Hz hum, inverted channels, low-pass cut, 16→24 padding, inflated sample rate, …).
- **No copyrighted musical material in the repository**, ever.

## Commits

Conventional Commits (`feat`, `fix`, `docs`, `refactor`, `chore`, `test`, `ci`, …). Do not add
AI co-author trailers.
