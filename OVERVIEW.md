# Audio Inspector — Project Overview

The read-first orientation for the project. It gives a human or an AI the durable mental model:
**what the project is, the rules that must never break, how it is built, and where every kind of
information lives.** Everything here is meant to stay true for years.

- It **explains decisions, architecture, and intent** — it never describes the current code or state.
- For anything that changes (task status, per-field behavior, the wire schema), it **points to the
  source of truth** rather than copying it. A copy that drifts is worse than a link.
- **To resume work / see the real state**, follow the protocol in `CLAUDE.md`: read `CURRENT.md`
  (last focus), then run `openspec list` and `git status`. This document holds no state.

---

## 1. What it is, and the invariants that define it

Audio Inspector is a **native macOS 15+ forensic audio-quality tool**. You open a local audio file and
it examines the **signal and its technical facts** — not just the tags — and explains what can and
cannot be known about the file's source, master, rip, and integrity. Audience: music collectors, DJs,
audiophiles, people digitizing vinyl/tape/CD. Swift 6, SwiftUI, SPM, strict concurrency. Licensed MIT.
Product philosophy: `docs/vision.md`, `docs/project-principles.md`, `docs/analysis-methodology.md`.

**Product invariants** — breaking one is a defect, not a trade-off:

1. **Honesty over verdicts.** Separate evidence / inference / conclusion; every judgment carries a
   confidence level (`none/weak/medium/strong/inconclusive`). Never present an inference as fact.
2. **Never invent a value.** Missing/uncertain/unsupported/errored data is represented as such — never
   fabricated. (Encoded in the type system; see §3.)
3. **No aggregate score.** Never reduce a file to "quality: 83/100."
4. **Format ≠ quality.** A container/codec, or a higher sample-rate/bitrate/bit-depth, is not quality.
5. **Local & non-destructive.** All processing on-device; **originals are never modified**; no network,
   no telemetry.
6. **Never disclose location.** No absolute path, `file://` URL, bookmark, sandbox id, or parent
   directory leaves the app by default. File paths/names are untrusted input.

## 2. Architecture & structural invariants

Governing decision (ADR-0001, ADR-0005; detail in `docs/architecture.md`): **Clean Architecture where
the dependency rule is a compile-time constraint.** Each layer is its own SwiftPM target that sees only
its declared dependencies, so an illegal cross-layer `import` fails to compile;
`Scripts/check-boundaries.sh` is the static backstop and runs in CI.

```
FeatureImport ─┐
FeatureAnalysis┼──▶ Domain ◀── Analysis ──▶ Accelerate/vDSP
               │      ▲
               │      └──── Media ──▶ Domain   (AVFoundation/AudioToolbox/FFmpeg-via-Process live here)
               │
               └── all wired by ──▶ AudioInspectorApp (library composition root)
                                          ▲
                                    App/*.xcodeproj (thin @main macOS shell)
```

| Target | Role | May import |
| --- | --- | --- |
| `AudioInspectorDomain` | Pure core: value types, ports, use cases | stdlib / Foundation values only |
| `AudioInspectorAnalysis` | Pure DSP & evidence engines | Domain (+ Accelerate) |
| `AudioInspectorMedia` | The only media/infra adapter | Domain + AVFoundation/AudioToolbox/CoreAudio; may spawn `Process` |
| `AudioInspectorTesting` | Port fakes, builders, fixtures | Domain (+ Analysis) — **not** AVFoundation |
| `FeatureImport`, `FeatureAnalysis` | SwiftUI slices | Domain only |
| `AudioInspectorApp` | Composition root (library): wires concretes to ports | all of the above |

The Xcode `.app` target is a `@main` shell over `AudioInspectorApp`; because the package is
library-only (no host executable, ADR-0001), `swift build`/`swift test` exercise everything from the
CLI.

**Structural invariants — build-enforced, never break these:**

- **Domain imports nothing framework-side** and uses no `Process`.
- **Media is the sole home of AVFoundation/AudioToolbox/CoreAudio and of `Process`;** any subprocess
  uses **separated argument vectors** (never `sh -c`, never interpolate paths) and **always selects the
  audio stream explicitly**. **Accelerate belongs only to Analysis.** **Features never import
  Media/Analysis.** **No `Sources/` target imports `AudioInspectorTesting`.**
- **No framework type or framework error ever crosses a domain port** — adapters translate to domain
  value types and domain errors (ADR-0011). This is the semantic complement to the import rules.

**Concurrency (Swift 6 complete checking; detail in `docs/concurrency.md`):** mutable shared state ⇒
`actor`; immutable data ⇒ `Sendable` value type; UI ⇒ `@MainActor`; else `nonisolated async`. No
`DispatchQueue`, **no `@unchecked Sendable`**, no manual locks.

## 3. The domain model (concepts & decisions)

The pure domain encodes the honesty invariants in the type system. These are design decisions; read
`Sources/AudioInspectorDomain/`, the active change's `design.md`, and ADR-0008 for exact shapes.

- **`Property<Value>` is an exhaustive sum type (ADR-0008)** so invalid states are unrepresentable. Its
  cases mean semantically distinct things that must stay distinct: *available* (trustworthy value) ·
  *unavailable* (source silent) · *unsupported* (format cannot express it) · *uncertain* (read but
  unreliable, reason required) · *failed* (extraction errored). This is invariant #2 made structural.
- **Two disjoint error levels.** A **property-level** failure and a **global** inspection error have
  **separate code spaces**; a property failure is never "file could not be opened," and vice-versa. For
  both, **the stable `code` is the identity; the message is descriptive only.**
- **Extracted facts carry two deliberate decisions:** the detected **container is a technical property**
  (not file metadata, because it can be uncertain/unavailable), and **declared and estimated bitrate
  are separate fields, never conflated** (a directly-declared rate vs. an always-`uncertain` estimate).
- **The report is pure data** — it carries no JSON envelope, URL, or framework type (ADR-0009). The
  **use case only orchestrates** (read via a port → derive warnings → compute status) and never throws.
- **The file reference is safe and ephemeral** — it carries no path/URL/bookmark; the real access
  handle stays in infrastructure (ADR-0010), upholding invariant #6.

## 4. Infrastructure, the port pattern, and how to extend it

Adapters implement domain ports; the domain never learns which implementation ran. The AVFoundation
property reader in `AudioInspectorMedia` is the reference example (ADR-0011 boundary; ADR-0012
extraction strategy, still **Proposed**). Its durable rules:

- **Errors are classified by *scope*, not by SDK code:** a whole-file failure is a thrown global error;
  a single-property read error is a `Property.failed` while the rest of the report continues; **absence
  is never `failed`.** Apple's numeric codes are never enumerated (they vary by SDK).
- **No Apple type or error crosses the port** (§2). **The URL arrives via an injected resolver seam,**
  because the domain reference has no URL (ADR-0010); sandboxed selection wires it later.
- **Conservative under an unproven strategy:** where a mapping would need unvalidated codec
  classification, the reader stays conservative rather than guess. Per-field source→state detail lives
  in `docs/audio-property-matrix.md` and the reader source — **not restated here** (it evolves).

**How to add any new capability (reader, decoder, analyzer) — the repeatable recipe:**

1. **Spec first** — no significant implementation without an approved OpenSpec change (§5).
2. **Define the port** in `AudioInspectorDomain/Ports/`: a small `Sendable` protocol in pure domain
   types (framework types never appear in its signature).
3. **Implement it** in `AudioInspectorMedia` (I/O, platform, subprocess) or `AudioInspectorAnalysis`
   (pure DSP), translating platform shapes and errors to domain values inside the adapter.
4. **Fake it** in `AudioInspectorTesting` for use-case/feature tests; unit-test the adapter's pure logic
   directly.
5. **Wire the concrete only in `AudioInspectorApp`** (composition root) via initializer injection.
6. **Record any hard decision as a new ADR;** keep the boundary script and the port stable.

## 5. Where each kind of information lives

Each kind of knowledge has **one** home — the one that already owns its truth. This document links to
them and restates none, so it can stay stable while they evolve.

| Need | Single source of truth |
| --- | --- |
| What the app is, for a visitor | `README.md` |
| Durable orientation, invariants, this map | **`OVERVIEW.md`** (this file) |
| Current working focus / how to resume | `CURRENT.md`, then `openspec list` + `git status` |
| Rules for AI-assisted work + session protocol | `CLAUDE.md` |
| Environment, commands, workflow, definition of done | `CONTRIBUTING.md` |
| What the system must do (accepted behavior) | `openspec/specs/` |
| In-flight work + live task status | `openspec/changes/<name>/` (`tasks.md`) |
| Code, branch, and commit state | git |
| Decisions (with rationale) | `docs/adr/` (index + status in `docs/adr/README.md`) |
| Stable explanations (architecture, concurrency, testing, methodology) | `docs/` (index in `docs/README.md`) |
| Per-field property behavior | `docs/audio-property-matrix.md` + the reader source |
| The JSON wire contract | `docs/json-schema-v1.md` |
| Roadmap / phases | `docs/roadmap.md` |
| Actionable debt / ideas | GitHub issues |

Rule of thumb: a **requirement** → an OpenSpec spec; a **decision** → an ADR; an **explanation** →
`docs/`; a **task** → a change's `tasks.md`; **intent/where-I-am** → `CURRENT.md`; **truth of code or
tasks** → git / OpenSpec.
