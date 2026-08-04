# Testing Strategy

Testing is built **into the architecture**, not bolted on. Because the domain is pure and every
collaborator is a port (protocol), the interesting logic is tested with no real audio files, no
subprocess, and no flakiness. The suite uses **Swift Testing** exclusively (XCTest only where a
constraint requires it). Approach adapted from SignalFlow (`docs/09-testing-strategy.md`); see
[signal-flow-reuse-audit.md](signal-flow-reuse-audit.md).

## The testing pyramid

```
   UI / smoke (few)      import → analyze → report renders end-to-end
   Integration (some)    Media adapter + Analysis over a generated fixture file
   Unit (many)           DSP transforms • metric math • evidence rules • report/JSON mapping
```

Most value sits in the wide base: **pure DSP and evidence logic**, which is fast, deterministic, and
exhaustive. Higher tiers verify the wiring.

### Where the automated suite stops

The end-to-end tier runs inside `swift test`: it walks the whole production chain — a generated
fixture on disk, the safe file reference, the real media reader, the use case, the report held by the
flow model, its presentation, the real exporter and a real write — substituting **only** the two
points where a person acts in that flow (the open and save panels) plus the clock and generator
identity. The other human entry point, dropping a file onto the window, is covered a tier below: the
integration tests inject the URL the drop would have produced and drive the same coordinator.

What it deliberately cannot reach: code signing, the entitlements the shipped app actually gets, the
sandbox powerbox, the native panels, a real drag from Finder, visual rendering, and real network
traffic — the package tests run unsandboxed and never launch the `.app`. Those are validated by hand with
[manual-validation-mvp.md](manual-validation-mvp.md). Two guarantees straddle the line: the *absence
of networking code* is enforced statically by `Scripts/check-boundaries.sh`, and the *absence of a
network entitlement* by a configuration test — neither claims to prove that no traffic occurs, which
only the manual observation can suggest.

## Swift Testing features we rely on

- `@Test` / `@Suite` grouped by behavior.
- **Parameterized `arguments:`** for table-driven metric/threshold coverage (one test, many signals)
  — e.g. a table of `(signal, expectedPeak, expectedLUFS±tol)`.
- `#expect` / `#require` (soft vs hard), `#expect(throws:)` for typed errors.
- `confirmation` for async/stream assertions (progress events, cancellation).
- Traits: `.tags` (concurrency, golden), `.timeLimit` (bound runtime), `.serialized` (a suite that
  must not run in parallel), `.disabled(if:)` (gate anything needing an optional external tool).

## Fakes over mocks

No mocking framework (it would add a dependency and isn't needed). Because every collaborator is a
Domain **port**, test doubles are ordinary types in `AudioInspectorTesting`:

- **Fakes/stubs** of `AudioProbing`, `AudioDecoding`, `LoudnessAnalyzing`, etc. that replay scripted
  results — assert on **outcomes**, not framework-recorded expectations.
- **Data builders** for domain fixtures (technical facts, metrics) to keep tests readable.
- `AudioInspectorTesting` is a real module reused by the test targets **and** by SwiftUI previews, so
  previews and tests share the same doubles.

## Numeric tolerance & golden files

- DSP results are compared with **explicit tolerances** (dB and linear), never exact equality on
  floats.
- **Golden files**: reference metric/spectrum outputs are pinned per **analysis engine version**;
  a change that shifts values must bump the engine version and update goldens deliberately.
- Loudness/true-peak are **cross-checked against FFmpeg `ebur128`** in tests within a documented
  tolerance (FFmpeg as a reference oracle — see [adr/0006](adr/0006-loudness-truepeak-methodology.md)).

## Determinism, cancellation, concurrency

- All test signals are generated deterministically (seeded where randomness is used), so runs are
  bit-reproducible.
- Explicit tests for **cooperative cancellation** (an analysis stops promptly and leaves bounded
  state) and for **bounded-memory streaming**.

## SyntheticAudioFactory (planned)

A deterministic generator living in `AudioInspectorTesting`, producing small in-memory / temp-file
signals so tests never ship audio. **Not fully implemented yet** — but the architecture and test
strategy assume it. Planned generators:

- silence; sine (single); multi-tone; white noise; pink noise (if it adds value);
- DC offset; hard clipping; 50 Hz hum; 60 Hz hum;
- inverted channel; inverted polarity; duplicated mono (false stereo);
- inter-channel delay; low-pass cut; high-pass cut; abrupt gain change; dropout;
- 16→24-bit padding; resampled (e.g. 44.1→96 kHz) signal; dithered signal.

Each generator is parameterized (duration, sample rate, bit depth, channels, level) and paired with
the metric/evidence it exercises (e.g. the low-pass generator feeds significant-max-frequency and
transcoding-evidence tests; the padding generator feeds effective-bit-depth tests).

## Copyright

**No copyrighted musical material in the repository.** Every fixture is synthetic and generated in
tests. Private local fixtures, if ever used, live under a git-ignored path.
