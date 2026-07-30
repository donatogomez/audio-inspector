## Context

Greenfield native macOS app (macOS 15+, Swift 6, SwiftUI, Strict Concurrency). This change lays the
foundation and delivers the smallest useful forensic slice: inspect one file. The detailed
rationale lives in the repository docs and ADRs; this document summarizes the technical approach for
the bootstrap change and records what is intentionally deferred.

- Architecture: `docs/architecture.md`
- Methodology (evidence/inference/conclusion, confidence, metric definitions): `docs/analysis-methodology.md`
- Decisions: `docs/adr/0001…0007`

## Goals / Non-Goals

**Goals:**

- Clean domain boundary: `AudioInspectorDomain` depends on nothing but the standard library and
  defines the protocols (`AudioProbing`, `AudioDecoding`, loudness/spectral/reporting) the rest of
  the system programs against.
- Native-first audio (AVFoundation/AudioToolbox/Accelerate); FFmpeg only behind protocols, as a
  dev/test adapter and reference oracle (ADR-0003).
- Streamed, cancellable analysis with bounded memory; results are deterministic given input +
  engine version.
- Honest output: every warning carries a confidence level and, where relevant, alternative
  explanations. No arbitrary numeric score.
- Read-only, local, non-destructive; sandbox-ready with security-scoped bookmarks.

**Non-Goals (this change):**

- Batch/folder import, cancellation of *many* files, retry queues (Phase 2).
- Container-integrity deep checks, persistence/result cache (Phase 2).
- Full loudness suite/timeline, dynamics/master analysis (Phase 3).
- Transcoding evidence engine, analog-source detection, version comparison (Phases 4–7).
- Any ML. Any tag writing. Any network.

## Decisions

- **App shape**: one SwiftPM package `AudioInspectorKit` (`swift-tools-version: 6.2`; boundaries =
  build graph) + a thin Xcode macOS app target (`com.donatogomez.audioinspector`) reusing the
  `AudioInspectorApp` **library** composition root (ADR-0001, ADR-0005). Start with `Domain`,
  `Analysis`, `Media`, `Testing`, `FeatureImport`, `FeatureAnalysis`, `App`; add `DesignSystem`/
  `Persistence` when seams appear. **No host executable** (a library-only package already builds/
  tests from the CLI). Boundaries backstopped by `Scripts/check-boundaries.sh`.
- **Native decoding is a hypothesis**: native-first (ADR-0003) is the direction, but AVFoundation/
  AudioToolbox sufficiency for all seven formats is validated by an **early Phase-1 spike** against
  real + synthetic fixtures before MVP decoding commits to it; FFmpeg stays available (dev/test)
  behind the ports if a gap appears. The MVP ships without bundled FFmpeg regardless.
- **JSON export**: a minimal, extensible, **versioned** contract from the MVP (`schemaVersion: 1`);
  the field-level contract is documented in `docs/json-schema-v1.md` (spec, not code, at this stage).
- **Deployment target macOS 15** (ADR-0002).
- **Audio I/O behind Domain protocols; native-first, FFmpeg abstracted** (ADR-0003). Every
  FFmpeg/FFprobe call selects the audio stream explicitly; subprocesses use separated argument
  vectors via `Process`, never `sh -c`.
- **Loudness/true-peak** per ITU-R BS.1770/EBU R128, implemented in `Analysis` with vDSP,
  cross-checked against FFmpeg `ebur128` in tests (ADR-0006). Thresholds are named constants tied
  to an engine version.
- **Reporting** is two-level (plain + technical) and records the engine version. JSON export via
  `Codable` (no `JSONSerialization`).
- **Concurrency**: `async`/`await` pipelines; a coordinating actor owns progress + cooperative
  cancellation even for the single-file MVP (so Phase 2 batching slots in cleanly).
- **Testing**: Swift Testing; synthetic fixtures generated in-test (sine, silence, clipping, DC
  offset, low-pass cut, 16→24 padding, inflated sample rate, inverted channels, …); golden files
  with explicit numeric tolerances; FFmpeg used as a reference oracle. No copyrighted audio in the
  repo.

## Risks / Trade-offs

- **Native loudness correctness** → cross-check against FFmpeg `ebur128` with pinned tolerances;
  version the constants.
- **Effective bit depth / significant max frequency are heuristic** → present as evidence with
  explicit thresholds and confidence; never assert transcoding from a single cutoff.
- **FLAC/ALAC decode edge cases via native APIs** → covered by fixtures; FFmpeg fallback path stays
  available behind the abstraction.
- **Over-modularization** → seam-driven package growth (ADR-0005); no empty modules.
- **Sandbox + bookmark friction** → design import around security-scoped bookmarks from day one.
- **CI runner/Xcode combo may not match the dev machine** → verify an available GitHub Actions
  macOS + Xcode image before adding CI; do not assume one exists.

## Migration Plan

Greenfield; no data migration. Work happens on branch `chore/bootstrap-foundation` (docs/specs)
and subsequent implementation branches per task group. Nothing is pushed or merged without
maintainer approval. Rollback = revert the branch; no released artifacts exist yet.

## Open Questions

Resolved since the first draft: license = **MIT** (ADR-0007); bundle id =
`com.donatogomez.audioinspector`; `swift-tools-version` = **6.2**; JSON = versioned from the MVP
(`schemaVersion` 1, `docs/json-schema-v1.md`); **no bundled FFmpeg** in the MVP; **no host
executable**. Remaining:

- **Native-API decoding sufficiency** — a hypothesis to validate with the Phase-1 spike (ADR-0003),
  not a decision to pre-make here.
- **Signing team / notarization identity** — needed only when the Xcode app target and distribution
  are set up (Phase 1 / Phase 8).
