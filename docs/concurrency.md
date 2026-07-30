# Concurrency Design

Audio Inspector builds under **Swift 6 strict concurrency** (complete checking). The goal is not to
use actors for show but to model the real system — batches of files, streamed decoding, parallel
DSP, cancellation — so that **data races are impossible at compile time** and isolation boundaries
map onto the architecture. Approach adapted from SignalFlow (`docs/07-concurrency.md`); see
[signal-flow-reuse-audit.md](signal-flow-reuse-audit.md).

## Isolation map

| Component | Isolation | Why |
| --- | --- | --- |
| SwiftUI views, presentation models (`@Observable`), router | `@MainActor` | UI state mutates on the main thread; Observation drives re-render |
| Domain value types (facts, metrics, evidence, report), pure policies | `nonisolated` `Sendable` value types | immutable, race-free by construction |
| Use cases (e.g. `AnalyzeFileUseCase`) | `nonisolated`, `async` | orchestration with no state of their own; run wherever awaited |
| `AudioProbing` / `AudioDecoding` adapters (Media) | `actor` or `nonisolated async` | own file handles / decoder state; serialize access to a subprocess or `ExtAudioFile` |
| DSP engines (Analysis) | `nonisolated` `Sendable` functions | pure transforms over `Sendable` buffers; parallelizable |
| **Batch/analysis coordinator** | `actor` | owns the work queue, per-file + global progress, capped concurrency, cancellation, retry |
| Result cache / persistence (Phase 2) | `@ModelActor` `actor` | serializes store access off-main |

Rule of thumb: **mutable shared state ⇒ `actor`; immutable data ⇒ `Sendable` value type; UI ⇒
`@MainActor`.** Everything else is `nonisolated async` and runs wherever it is awaited. No locks, no
`DispatchQueue`, and **no `@unchecked Sendable`** in first-party code.

## Structured concurrency & cancellation

- Per-file analysis fans work out with `withThrowingTaskGroup` for **bounded parallelism** (a
  capped worker count) with **automatic cancellation propagation** — if the user cancels or leaves,
  child tasks are cancelled.
- Decoding and DSP are **streamed in chunks** and check `Task.isCancelled` / honor cooperative
  cancellation at chunk boundaries, so a cancelled analysis stops promptly with bounded memory.
- Even the single-file MVP routes through the coordinator actor so Phase 2 batching slots in without
  reworking isolation.
- Progress is reported as `Sendable` snapshots pushed from the coordinator to `@MainActor` models
  (e.g. via `AsyncStream`), never by touching UI state from a background context.

## Determinism

DSP transforms are pure functions of their input buffers and the engine version; given the same
input and version they produce identical output within documented tolerances. Any randomized test
signal uses a **seeded** generator (see [testing-strategy.md](testing-strategy.md)).

## Enforcement

Swift 6 language mode is set per target in `Package.swift`; strict-concurrency diagnostics are
errors. Module boundaries that back these isolation choices are checked by
[`Scripts/check-boundaries.sh`](../Scripts/check-boundaries.sh).
