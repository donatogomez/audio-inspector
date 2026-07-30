# ADR-0001: Clean Architecture enforced at the SwiftPM target level (package + library composition root + thin Xcode app)

- **Status**: Accepted
- **Date**: 2026-07-30
- **Deciders**: Project maintainer
- **Related**: ADR-0002, ADR-0005, docs/architecture.md, docs/signal-flow-reuse-audit.md

## Context

Audio Inspector must feel like a professional native macOS utility (NavigationSplitView, Table,
inspector, toolbar, menus, keyboard, Quick Look, VoiceOver), process audio locally, and be highly
testable with isolated DSP logic. The brief mandates Swift 6, SwiftUI, Strict Concurrency,
async/await, and Swift Package Manager. The recurring failure mode in Swift apps is **architectural
erosion**: DSP/business logic leaking into views and infrastructure leaking into the UI. Folder
"layering" doesn't prevent this because nothing stops an `import`. The SignalFlow reference solves
this by making the dependency rule a **build constraint**.

## Decision

Build a **native macOS SwiftUI app** whose code is **one multi-target Swift package**
(`AudioInspectorKit`, `swift-tools-version: 6.2`, Swift 6 language mode per target) where each
layer/feature is a separate target with explicitly declared dependencies. A **library-only package
already builds and tests from the CLI** (`swift build` / `swift test`) with no Xcode project, so no
extra executable is introduced for that.

- **`AudioInspectorApp`** is the **composition root** as a *library* target — the only place that
  sees concrete implementations and wires them via initializer injection. Being a library keeps it
  unit-testable (an `AppContainer` test) without Xcode.
- A thin **Xcode macOS app** target reuses `AudioInspectorApp` and adds only the `.app` bundle,
  entitlements, sandbox, signing, and the `@main` entry point. It is the product's runnable shell.

No `AudioInspectorHost` executable is created now: a CLI has no consumer until a real analysis
engine exists (see ADR-0005 and docs/roadmap.md — a future `audio-inspector` CLI is a roadmap item,
not initial scaffolding). Boundaries are enforced by the build graph and, as a full-build backstop,
by `Scripts/check-boundaries.sh`. UIKit/AppKit only where a specific control requires it (wrapped
and isolated).

## Alternatives considered

- **Xcode workspace + separate local packages** (the bootstrap's first framing). Works, but a single
  multi-target package is simpler to navigate, keeps CI on plain `swift test`, and still lets a
  target "graduate" to its own package later with no source changes. Superseded by this decision.
- **Single monolithic Xcode app target, no packages.** Couples DSP to UI, slows tests, blurs the
  domain boundary, and leaves the dependency rule unenforced. Rejected.
- **Pure SwiftPM executable, no Xcode project at all.** Can't produce a properly sandboxed, signed,
  notarized `.app` with entitlements. Rejected for the shipped app.
- **A thin `AudioInspectorHost` executable "for CLI/CI" (SignalFlow's pattern).** Rejected: a
  library-only package already runs `swift build`/`swift test`, so the executable would only mimic
  SignalFlow's structure without a real consumer. Deferred to the roadmap as a possible future CLI
  once an analysis engine exists.
- **Catalyst / cross-platform UI.** Contradicts "truly native macOS, not a scaled iPhone UI".
  Rejected.
- **Third-party architecture/DI framework.** Violates the zero-dependency bias; initializer
  injection at the composition root suffices. Rejected.

## Consequences

### Positive
- The dependency rule lives in the build graph, not a review note: an undeclared `import` fails to
  compile, and the boundary script guarantees it on full builds too.
- Pure Domain + DSP tested with zero infrastructure; fast incremental builds; CI is `swift build` +
  `swift test` with no Xcode project.
- Isolation boundaries (actors, `@MainActor`) align with module boundaries.

### Negative / costs
- More `Package.swift` wiring than a single target; cross-cutting changes touch several targets.
- Some boilerplate at the composition root (explicit DI wiring).

### Neutral
- Encourages many small ports (protocols): great for testing, more types overall.

## Follow-ups

Exact target set in ADR-0005; deployment target in ADR-0002; the Xcode app target and CI YAML land
when the package is first compilable (Phase 1 / Phase 8).
