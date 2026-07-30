# SignalFlow → Audio Inspector reuse audit

Audit of [`donatogomez/signal-flow`](https://github.com/donatogomez/signal-flow) (inspected at the
real paths below), comparing its **practices** with the Audio Inspector bootstrap and deciding what
to reuse, adapt, reference conceptually, or drop.

**Hard rule:** SignalFlow is an **IoT monitoring** app. We reuse *practices and structure*, never
its domain code (devices, telemetry, alerts, simulation, SwiftData models, Foundation Models,
networking, widgets, watch, App Intents). Audio Inspector starts **smaller** and grows only when
real boundaries appear.

Disposition legend: **Reuse** = adopt the artifact adapted only in names/paths · **Adapt** = same
idea, materially reworked for audio · **Concept** = borrow the principle, write our own · **Skip** =
not applicable to Audio Inspector.

## Infrastructure & practices

| SignalFlow path | Purpose | Detected practice / pattern | Disposition | Reason | Impact on Audio Inspector | Phase |
| --- | --- | --- | --- | --- | --- | --- |
| `Package.swift` | Build manifest, 24 targets | **Clean Architecture enforced by SwiftPM targets**: a target sees only its declared deps, so layering is a compile-time constraint. Swift 6 language mode per target (`.swiftLanguageMode(.v6)`). `defaultLocalization`. Host executable + library composition root so `swift build/test` run from CLI. | **Adapt** | The boundary-as-build-graph idea is exactly what we want; the 24-target surface is not. | One small package (`AudioInspectorKit`, `swift-tools-version: 6.2`) with 7 targets (no host executable); Swift 6 mode per target. Replaces the earlier "Xcode workspace + packages" framing (ADR-0001). | 1 |
| `Sources/DomainKit/` (Entities, ValueObjects, Ports, UseCases, Policies, Errors) | Pure business core, depends on nothing | **Domain = pure value types + `Ports` (protocols) + `UseCases`**; dependency inversion; no framework imports | **Adapt** | Perfect fit for our forensic domain (facts, metrics, evidence, confidence, report). | `AudioInspectorDomain` mirrors this folder shape with audio concepts; imports nothing (no AVFoundation/Accelerate/SwiftUI/Process). | 1 |
| `Scripts/check-boundaries.sh` | Static import-rule enforcement | **grep-based boundary checker** closing SwiftPM's shared-module-cache gap on full builds; numbered rules; fail-fast | **Adapt** | Same failure mode applies to us; the rules must match *our* modules, not SignalFlow's 16. | New, smaller `Scripts/check-boundaries.sh` with Audio-Inspector rules (Domain purity; Media owns AVFoundation/AudioToolbox/Process; Analysis owns Accelerate; Features never import Media). | 1 |
| `.github/workflows/ci.yml` | CI | `macos-26` runner; `check-boundaries` → `swift build` → `swift test`; `concurrency: cancel-in-progress`; separate Xcode-app build job | **Adapt (deferred)** | We have no compilable package yet; runner/Swift/OpenSpec/cache must be re-verified before committing YAML. | Strategy documented now (mirror the boundary→build→test gate + `openspec validate --strict`); YAML written when the package exists. | 8 (strategy now) |
| `.github/pull_request_template.md` | PR hygiene | Summary/Why/Changes + **Architecture checklist** (no cross-boundary imports, ADR referenced) + **Testing checklist** (`swift build`, `swift test`, `check-boundaries.sh`) + trade-offs + self-review | **Adapt** | Cheap, high-value, reinforces the boundary + spec discipline. | New `.github/pull_request_template.md` adapted to our checks and OpenSpec (`openspec validate --strict`). | 1 |
| `docs/adr/` + `docs/adr/README.md` | Decisions | Light **MADR**: Status/Date/Deciders/Context/Decision/Consequences (Positive/Negative/Neutral)/Alternatives. **Immutable once accepted; superseded by a new ADR.** "A decision with no trade-offs is an assumption in disguise." | **Adapt** | Our ADRs already exist but used a looser shape; align to MADR + immutability. | Adapt `docs/adr/0000-adr-template.md` + `README.md` to MADR; reformat consequences going forward. | 1 |
| `docs/07-concurrency.md` | Concurrency design | **Isolation map**: `@MainActor` UI/presentation · `actor` for mutable shared state · `nonisolated Sendable` pure domain · `nonisolated async` use cases · `TaskGroup` bounded parallelism + cancellation · no locks, no `@unchecked Sendable` | **Adapt** | Directly transferable; our audio pipeline has the same shapes (batch coordinator actor, pure DSP, MainActor UI). | New `docs/concurrency.md` with an audio-specific isolation map. | 1 |
| `docs/09-testing-strategy.md` + `Tests/**` | Testing | **Swift Testing only**; pyramid; **parameterized `arguments:`**; `#expect`/`#require`/`#expect(throws:)`; `confirmation` for streams; traits (`.tags`/`.timeLimit`/`.serialized`/`.disabled(if:)`); **fakes/stubs over mocks** (ports make doubles trivial); data builders; a shared `TestingSupportKit` reused by tests **and** previews; injected `Clock`/seeded RNG for determinism | **Adapt** | The determinism + fakes-over-mocks approach is exactly what synthetic audio fixtures need. | New `docs/testing-strategy.md`; document a future `SyntheticAudioFactory` (deterministic signal generators) living in `AudioInspectorTesting`. | 1 (docs) / 1–7 (impl) |
| `CoreKit/SeededRandomNumberGenerator`, `SimulationDeterminismTests`, `SimulationCancellationTests` | Deterministic simulation + cancellation | Seeded RNG; determinism + cooperative-cancellation tests | **Concept** | We don't simulate IoT, but synthetic audio must be **bit-reproducible** and analysis must be cancellable. | Seeded generation inside `AudioInspectorTesting`; cancellation tests for the analysis pipeline. | 1–2 |
| `Sources/SignalFlowApp` (library composition root) + `App/*.xcodeproj` (thin shell) | Runnable app + CLI/CI coverage | **Composition root as a library** reused by a thin Xcode app target | **Adapt** | A *library* composition root is unit-testable from the CLI (`AppContainer` test) while the real `.app` (sandbox/entitlements/notarization) stays a thin `@main` target. | `AudioInspectorApp` (library) + a thin macOS Xcode app target. | 1 |
| `Sources/SignalFlowHost` (executable `@main`) | CLI/CI entry point | A thin host executable so `swift build/test` run from the CLI | **Skip (reconsidered)** | A **library-only package already runs `swift build`/`swift test`** — the executable's stated justification doesn't hold, and no CLI consumer exists yet. Adding it would only mimic SignalFlow's structure. | **No `AudioInspectorHost`.** A CLI is a roadmap item for when an analysis engine has a headless consumer. | roadmap |
| `README.md` (24k) | Front door | **Demonstrates** practices with real code + mermaid, doesn't just claim them | **Concept** | Our README should show the boundary model + honesty guarantees, not just assert them. | Add an "Architecture at a glance" + "how boundaries are enforced" section; keep the forensic-honesty framing. | 1 |
| `docs/10-documentation-strategy.md` (numbered docs) | Doc organization | One topic per numbered doc; ADRs separate | **Concept** | We prefer named docs + OpenSpec; adopt the *separation-of-concerns* idea, not the numbering. | New `docs/README.md` index that also pins the **documentation hierarchy** (specs vs changes vs docs vs ADRs vs issues/PRs). | 1 |
| `.gitignore` | Ignore rules | Swift/Xcode/SPM ignores | **Reuse** (already equivalent) | Ours already covers this + audio-fixture privacy. | Keep our `.gitignore`. | — |
| `LICENSE` | License | SignalFlow ships a license | **Adapt** | Decision made: **MIT** (ADR-0007), compatible with the no-bundled-FFmpeg strategy. | `LICENSE` (MIT © 2026 Donato Gómez) committed at the root. | 1 |
| _absent_: `.claude/`, `CLAUDE.md`, `AGENTS.md` | AI-assistant config | **SignalFlow has none** | **Concept** | We shouldn't invent agent scaffolding "because SignalFlow does" — it doesn't. But a project `CLAUDE.md` matches the user's own global convention and helps future sessions. | Add a concise project `CLAUDE.md`; **defer** specialized review agents (documented proposal, no empty files). | 1 (CLAUDE.md) / later (agents) |

## Domain / feature code — explicitly NOT reused

| SignalFlow area | Why it's skipped |
| --- | --- |
| `DomainKit` entities (`Device`, `Alert`, `TelemetryReading`, `AlertRule`, …), policies, use cases | IoT domain; Audio Inspector's domain is audio facts/metrics/evidence. Only the *shape* (Entities/ValueObjects/Ports/UseCases) is reused. |
| `NetworkingKit`, `SimulationKit`, `DataKit` (remote/simulated telemetry) | No networking and no device simulation in Audio Inspector (100% local, file-driven). |
| `PersistenceKit` SwiftData `@Model`s | Persistence is deferred (Phase 2); models will be audio-result records, not telemetry. |
| `IntelligenceKit` (Foundation Models) | No ML in the MVP; possible far-future, unrelated to IoT insights. |
| `WidgetSupportKit`, `AppIntentsKit`, `LiveActivityKit`, `Watch*Kit`, `SnapshotKit` | iOS/watchOS glance surfaces; Audio Inspector is a macOS desktop utility with no equivalent. |
| The 24-target layout / `App/SignalFlow.xcodeproj` iOS+watch targets | We start with ~7 targets + a host; we do **not** port the target explosion. |

## Net effect

Adopt SignalFlow's **method** (boundary-enforced Clean Architecture, ports, a library composition
root, boundary script, MADR ADRs, Swift-Testing determinism, PR discipline, concurrency isolation
map) at **~1/4 the surface area**, and keep the forensic-analysis domain entirely our own. We
deliberately drop what doesn't earn its place — notably the host executable (a library-only package
already builds/tests from the CLI).
