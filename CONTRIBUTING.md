# Contributing to Audio Inspector

The operational **runbook**: environment, commands, workflow, and the definition of done. It
deliberately does **not** restate the architecture, the invariants, or the working rules — those live
in [`OVERVIEW.md`](OVERVIEW.md) (orientation + invariants) and [`CLAUDE.md`](CLAUDE.md) (rules + session
protocol). Read those two once before starting.

Development is **spec-first** and mostly solo + AI: no significant code without an approved OpenSpec
change, and **never implement on `main`** — branch per change.

## Environment

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

```bash
brew install ffmpeg swiftlint swiftformat gh
npm install -g @fission-ai/openspec
```

> Homebrew FFmpeg is a **GPL build** — fine for local dev/CI, but it has distribution implications for
> any shipped binary (ADR-0003). The MVP ships without FFmpeg.

Export `OPENSPEC_TELEMETRY=0` (the project opts out of OpenSpec telemetry; CI sets it too).

## OpenSpec workflow

Modern artifact workflow (schema `spec-driven`); artifact order **proposal → (design, specs) → tasks**.
Every requirement needs at least one `#### Scenario:` (exactly four hashtags) in WHEN/THEN form. Don't
invent commands — check `openspec --help` or the `.claude/` skills.

```bash
OPENSPEC_TELEMETRY=0 openspec list                        # active changes
OPENSPEC_TELEMETRY=0 openspec new change "<kebab-name>"   # scaffold a change
OPENSPEC_TELEMETRY=0 openspec status --change "<name>"    # artifact progress
OPENSPEC_TELEMETRY=0 openspec validate <name> --strict    # validate a change/spec
OPENSPEC_TELEMETRY=0 openspec archive <name>              # after implemented AND merged
```

## Definition of done

A change is done when all four gates are green:

```bash
./Scripts/check-boundaries.sh                              # architecture boundaries
swift build -Xswiftc -warnings-as-errors                   # zero-warnings build
swift test                                                 # Swift Testing suite
OPENSPEC_TELEMETRY=0 openspec validate --all --strict      # specs/changes valid
```

Style, run locally before pushing: `swiftformat --lint . && swiftlint`.

## Adding a decision

Copy `docs/adr/0000-adr-template.md` for a hard, hard-to-reverse choice a future contributor would
otherwise have to reverse-engineer. ADRs are immutable once Accepted; reverse one with a new
superseding ADR.

## Pull requests

Small, single-purpose PRs using [`.github/pull_request_template.md`](.github/pull_request_template.md):
link the approved OpenSpec change, confirm no cross-boundary imports, and paste the gate output. `main`
must stay green.
