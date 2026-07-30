# Architecture

This document describes the intended architecture. It is a **proposal** refined through ADRs and
OpenSpec changes; nothing here is implemented yet.

## Goals

- Keep the **domain** (models, analysis logic, evidence reasoning) free of any dependency on
  FFmpeg, AVFoundation, SwiftUI, SwiftData/Core Data, or shell processes.
- Make audio-source strategy (native vs FFmpeg) an implementation detail hidden behind protocols.
- Support large collections: streaming, bounded memory, cancellation, capped concurrency, caching.
- Be testable from day one with synthetic fixtures and golden files.

## Shape: one SPM package + a thin Xcode app

The code is **one multi-target Swift package** `AudioInspectorKit` (`swift-tools-version: 6.2`,
Swift 6 language mode per target) plus a thin **Xcode macOS app** target. Bundle identifier:
`com.donatogomez.audioinspector`.

- **Boundaries are the build graph.** A target sees only its explicitly declared dependencies, so an
  undeclared `import` fails to compile. Clean Architecture stops being a diagram and becomes a
  compile-time constraint. A full `swift build` shares one module cache, so
  [`Scripts/check-boundaries.sh`](../Scripts/check-boundaries.sh) statically rejects any leaked
  import as a backstop (locally and in CI).
- **CLI build/test without Xcode.** A library-only package already runs `swift build` / `swift test`
  from the command line, so **no host executable is introduced**. `AudioInspectorApp` is the
  composition root **as a library** (unit-testable via an `AppContainer` test); the Xcode app target
  reuses it and adds only the `@main` entry point, the `.app` bundle, entitlements, sandbox, and
  signing. A CLI executable is a roadmap item for when a real analysis engine has a headless consumer.

See [adr/0001-native-macos-swiftui-spm.md](adr/0001-native-macos-swiftui-spm.md) and
[adr/0005-module-structure.md](adr/0005-module-structure.md).

```
audio-inspector/
├── Package.swift                    (AudioInspectorKit — tools 6.2; Swift 6 mode per target)
├── Sources/
│   ├── AudioInspectorDomain         (pure value types + Ports; no I/O, no frameworks)
│   ├── AudioInspectorAnalysis       (DSP & evidence engines; Domain + Accelerate)
│   ├── AudioInspectorMedia          (decoding/probing adapters: AVFoundation/AudioToolbox/FFmpeg)
│   ├── AudioInspectorTesting        (SyntheticAudioFactory, port fakes, builders — reused by previews)
│   ├── FeatureImport                (SwiftUI: import surface + model)
│   ├── FeatureAnalysis              (SwiftUI: detail/report surface + model)
│   └── AudioInspectorApp            (library composition root — the ONLY target that wires concretes)
├── Tests/AudioInspectorKitTests/
├── Scripts/check-boundaries.sh
└── App/AudioInspector.xcodeproj     (thin macOS app target: @main + bundle over AudioInspectorApp)
```

Targets are added **only when a real seam exists** — no empty/ceremonial modules.
`AudioInspectorDesignSystem` is deferred until real shared UI components exist; `AudioInspectorPersistence`
is deferred to Phase 2 (the MVP needs no persistence). See [adr/0005](adr/0005-module-structure.md).

## Dependency direction

```
FeatureImport ─┐
FeatureAnalysis┼──▶ Domain ◀── Analysis ──▶ Accelerate/vDSP
               │       ▲
               │       └──── Media ──▶ Domain     (AVFoundation/AudioToolbox/FFmpeg via Process here)
               │
               └── all wired by ──▶ AudioInspectorApp (library composition root)
                                          ▲
                                    App/*.xcodeproj (thin @main macOS shell)
```

- **Domain** depends on nothing but the standard library / Foundation value types. It defines the
  **Ports** (protocols) and value types.
- **Analysis** depends on Domain (+ Accelerate). Pure DSP and evidence reasoning.
- **Media** implements Domain's I/O ports using platform APIs and/or FFmpeg. This is the **only**
  place external processes or media frameworks appear.
- **Features** (SwiftUI) depend on Domain only (and a future DesignSystem) — never on Media/Analysis
  concretes or FFmpeg. They receive their use cases/ports via injection from the composition root.
- **App** (library composition root) is the only target that imports the concretes and wires them
  via initializer injection (no DI framework, no singletons). The Xcode app target is a thin `@main`
  shell over it.

These rules are enforced by the build graph and by `Scripts/check-boundaries.sh`.

## Domain Ports (implementation-agnostic)

These live in `AudioInspectorDomain/Ports/` and are the contract the rest of the system programs
against. The Domain also holds `Entities/`, `ValueObjects/`, `UseCases/`, and `Errors/`. The MVP
implements a subset (`AudioProbing`, `AudioDecoding`, `LoudnessAnalyzing`, `SpectralAnalyzing`,
`ReportGenerating`); the rest are the destination as later phases land:

- `AudioProbing` — container/codec/technical facts (explicitly selecting the audio stream).
- `AudioDecoding` — streamed PCM access (chunked, cancellable).
- `LoudnessAnalyzing` — peak, true peak, RMS, LUFS (M/S/I), LRA, crest factor.
- `SpectralAnalyzing` — spectra, band energy, centroid, rolloff, cutoff detection.
- `DynamicRangeAnalyzing` — DR metrics, limiting/clipping indicators.
- `ChannelAnalyzing` — correlation, phase, mid/side, mono compatibility, polarity.
- `NoiseAnalyzing` — hum, hiss, DC offset, periodic clicks, dropouts.
- `SourceEvidenceAnalyzing` — the **evidence engine** for transcoding / source inference.
- `AudioComparing` — align two versions and produce a structured comparison.
- `WaveformGenerating`, `SpectrogramGenerating` — visualization data producers.
- `AnalysisPersisting` — store/fetch results and bookmarks.
- `ReportGenerating` — build the two-level (plain/technical) report and JSON export.

Each protocol is small, `Sendable`-friendly, and returns Domain value types. Implementations are
injected (no singletons).

## The evidence engine (where it lives)

Source inference (e.g. "possible transcoding") is an aggregation of independent, weighted indicators
— never a single fixed-cutoff rule. That reasoning lives in `AudioInspectorAnalysis` behind the
`SourceEvidenceAnalyzing` port and returns Domain evidence/confidence types. The methodology itself
(indicators, tiers, confidence levels, alternative explanations) is defined once in
[analysis-methodology.md](analysis-methodology.md); this document only fixes *where* it sits in the
build graph.

## Concurrency model

Swift 6 complete strict-concurrency. In short: mutable shared state ⇒ `actor` (e.g. the batch
coordinator, the Media decode adapters); immutable data ⇒ `Sendable` value type (Domain, DSP
buffers); UI ⇒ `@MainActor`; everything else `nonisolated async`. `TaskGroup` for bounded
parallelism with cancellation propagation. No `DispatchQueue`, no `@unchecked Sendable`. The full
isolation map is in [concurrency.md](concurrency.md).

## Performance strategy

- Stream and process in **chunks**; do not load whole tracks into RAM unless justified.
- Bounded memory and backpressure; incremental/resumable processing where feasible.
- **Result cache** keyed by a versioned fingerprint (file hash + size + mtime + engine version);
  invalidate when the file or engine version changes.

## Persistence (Phase 2, not the MVP)

Results and metadata only — never audio, never file copies — behind the `AnalysisPersisting` port.
Store choice and rationale are in [adr/0004-persistence.md](adr/0004-persistence.md) (proposed:
SwiftData, pending a Phase-2 spike). The MVP does not persist.

## UI architecture

Native macOS: `NavigationSplitView` (sidebar: recent analyses / collections) → `Table` of files
(status, filters, search, progress) → detail with a summary tab and technical tabs (waveform,
loudness timeline, spectrogram, spectrum, dynamics, channels/phase, noise, metadata, comparison).
Feature modules expose `@Observable` view models fed by injected Domain protocols. Accessibility
and VoiceOver are requirements, not add-ons.

## Engine versioning

Every analysis records the **engine version** and the methodology/threshold set used. Changing a
threshold or algorithm bumps the version and invalidates cached results. This keeps output
auditable and reproducible across releases.
