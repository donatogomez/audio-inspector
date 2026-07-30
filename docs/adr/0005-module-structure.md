# ADR-0005: Module structure — pragmatic, seam-driven targets

- **Status**: Accepted
- **Date**: 2026-07-30
- **Deciders**: Project maintainer
- **Related**: ADR-0001, docs/architecture.md, docs/signal-flow-reuse-audit.md

## Context

The brief lists a candidate module split but warns: "propose a pragmatic modular architecture — do
not create modules for the sake of it." The SignalFlow reference has 24 targets for a
multi-platform IoT app; Audio Inspector is a single-window macOS utility and must start far smaller
and grow only when real boundaries appear. We want a clean domain boundary and testable DSP without
premature over-modularization.

## Decision

One Swift package `AudioInspectorKit` (`swift-tools-version: 6.2`) with the **7 initial targets**
below (adopting SignalFlow's Domain shape and library composition-root pattern, at ~1/4 the surface
area — no host executable, no glance/multiplatform surfaces). Targets are added only when a real
seam exists.

| Target | Role | Depends on | From day one? |
| --- | --- | --- | --- |
| `AudioInspectorDomain` | Pure core: `Entities/`, `ValueObjects/`, `Ports/`, `UseCases/`, `Errors/` | nothing (stdlib/Foundation values) | ✅ |
| `AudioInspectorAnalysis` | DSP + evidence engines | Domain, Accelerate | ✅ |
| `AudioInspectorMedia` | Probing/decoding adapters; only home of AVFoundation/AudioToolbox/FFmpeg-via-Process | Domain | ✅ |
| `AudioInspectorTesting` | `SyntheticAudioFactory`, port fakes, builders (reused by previews) | Domain (+ Analysis) | ✅ (test utility) |
| `FeatureImport` | SwiftUI import surface + model | Domain | ✅ |
| `FeatureAnalysis` | SwiftUI detail/report surface + model | Domain | ✅ |
| `AudioInspectorApp` | Composition root (library); wires concretes via DI | all of the above | ✅ |
| `AudioInspectorDesignSystem` | Shared UI components/formatting | Domain | ⏳ when real duplication appears |
| `AudioInspectorPersistence` | SwiftData result store | Domain | ⏳ Phase 2 (MVP needs none) |
| _CLI executable_ | Batch/headless analysis over the engine | App | ⏳ roadmap, once an engine exists |

The **Domain imports nothing** framework-side: not SwiftUI, AppKit, AVFoundation, AudioToolbox,
Accelerate, SwiftData, FFmpeg, and it does not use `Process`. `Analysis` and `Media` implement the
inward-facing ports. `AudioInspectorApp` is a **library** target (so it is unit-testable from the
CLI without Xcode); the thin Xcode macOS app target reuses it and adds the `@main` shell, bundle,
entitlements, and signing. **No `AudioInspectorHost` executable** is created up front — a
library-only package already builds/tests from the CLI, so an executable would only mimic
SignalFlow's structure without a consumer (see ADR-0001).

## Alternatives considered

- **Port SignalFlow's 24-target layout.** Massive over-modularization for a macOS utility (no
  networking, simulation, widgets, watch, App Intents, Foundation Models). Rejected outright.
- **All candidate modules up front (incl. DesignSystem, Persistence).** Risks empty/ceremonial
  modules before boundaries are proven. Rejected in favor of seam-driven growth toward the same end
  state.
- **Single target + folders.** Too coarse; couples DSP to UI and leaves the dependency rule
  unenforced. Rejected.

## Consequences

### Positive
- Strong domain boundary and testable DSP immediately; CI runs on plain `swift test`.
- No ceremonial modules; a clear destination so growth is directed, not ad hoc.

### Negative / costs
- Some refactoring as `DesignSystem`/`Persistence` are extracted later (mitigated by keeping the
  Domain ports stable).

### Neutral
- More targets than a single app, fewer than SignalFlow — a deliberate middle.

## Follow-ups

The bootstrap change's tasks scaffold Domain + Analysis + Media + Testing + the two Features + App
(library composition root) + the thin Xcode app + the boundary script; later phases add DesignSystem
and Persistence, and — only if a real need appears — a CLI executable.
