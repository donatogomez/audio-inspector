# Implementation Tasks

Tasks for implementing the MVP defined by this change. **Not executed in the bootstrap session** —
each group is a small, reviewable increment for a later branch.

**Development philosophy (vertical slices):** the first increment is a **complete, runnable
end-to-end flow with no complex math** — select → open → decode → show properties → export JSON.
Complex algorithms (LUFS, True Peak, FFT/spectrum, spectrogram, DR) are added **only after** that
flow works, one small demonstrable increment at a time. Prefer many small verifiable increments over
a few large ones. See `docs/project-principles.md` (#13).

---

## Milestone A — Runnable vertical slice (NO complex math)

### 1. Project scaffolding (app launches)

- [ ] 1.1 Create `Package.swift` for `AudioInspectorKit` (`swift-tools-version: 6.2`, Swift 6 language mode per target, macOS 15 platform, warnings-as-errors) with targets `AudioInspectorDomain`, `AudioInspectorAnalysis`, `AudioInspectorMedia`, `AudioInspectorTesting`, `FeatureImport`, `FeatureAnalysis`, `AudioInspectorApp` (library composition root) — no host executable
- [ ] 1.2 Wire target dependencies to enforce the dependency rule (Domain depends on nothing; Features → Domain only; App = composition root)
- [ ] 1.3 Add the thin Xcode macOS `.app` target (`com.donatogomez.audioinspector`, `@main` shell) reusing `AudioInspectorApp`; configure App Sandbox entitlements and security-scoped bookmark usage
- [ ] 1.4 Add `Scripts/check-boundaries.sh` rules for the real modules and a `make`/script entry point for `format`, `lint`, `test`, `boundaries`
- [ ] 1.5 Add SwiftFormat + SwiftLint configs; confirm `.github/pull_request_template.md` checks match the scripts
- [ ] 1.6 **Runnable:** the app launches to an empty state

### 2. Domain for the slice (properties + report, no DSP)

- [ ] 2.1 Define Domain value types for the slice: file identity, media properties, analysis status, report, engine version — all `Sendable`, `Codable`
- [ ] 2.2 Define the ports the slice needs: `AudioProbing`, `AudioDecoding`, `ReportGenerating`
- [ ] 2.3 Define the confidence and evidence/inference/conclusion types (per `docs/analysis-methodology.md`) and a `findings` model — present but empty during the slice; used by later milestones

### 3. Open + decode + read properties (no math)

- [ ] 3.0 **Native-decoding spike (ADR-0003):** validate AVFoundation/`ExtAudioFile` against real + synthetic fixtures for MP3/WAV/AIFF/FLAC/ALAC/AAC/M4A — decode compatibility, reliable properties (bit depth/sample rate/layout/duration), damaged-file behavior, metadata/extra-stream handling, differences vs FFprobe, large-file performance. Record findings; update ADR-0003 if a gap is found
- [ ] 3.1 Implement security-scoped-bookmark import (drag-and-drop + file picker), read-only, single file
- [ ] 3.2 Implement native probing (AVFoundation/AudioToolbox) for container/codec/technical facts (container, codec, duration, bitrate declared/estimated + CBR/VBR, sample rate, declared bit depth, channels, layout, cover-art presence), selecting the audio stream explicitly
- [ ] 3.3 Implement the FFprobe-backed probing adapter behind the same port (dev/reference cross-check), separated `Process` arguments (no shell)
- [ ] 3.4 Implement streamed, cancellable PCM decoding with bounded memory (proves the file opens and decodes)
- [ ] 3.5 Compute the cryptographic file hash (and decoded-PCM hash where appropriate)

### 4. Minimal report + JSON export (properties only)

- [ ] 4.1 Assemble a properties-only report (no DSP metrics, empty `findings`) tagged with the engine version
- [ ] 4.2 Implement versioned JSON export via `Codable` to the `schemaVersion: 1` contract (`docs/json-schema-v1.md`): `fileIdentity`, `mediaProperties`, empty `measurements`/`findings`, `analysisStatus`

### 5. Minimal UI — the first demonstrable end-to-end slice

- [ ] 5.1 App shell: `NavigationSplitView`, empty states, toolbar, menus, keyboard support
- [ ] 5.2 Import surface (drag-and-drop + file picker) with progress/cancellation for the single-file flow
- [ ] 5.3 Properties view (container/codec/duration/sample rate/declared bit depth/channels/…)
- [ ] 5.4 Export action that writes the `schemaVersion: 1` JSON
- [ ] 5.5 **✅ Milestone A runnable & demoable:** select → open → decode → show properties → export JSON, with no complex math

### 6. Tests & CI for the slice

- [ ] 6.1 Seed `AudioInspectorTesting` with the minimal deterministic fixtures the slice needs (silence, a sine, and small per-format samples)
- [ ] 6.2 Import/decode/property/export tests; verify originals are unmodified (hash before/after); FFprobe-parsing tests (well-formed + malformed)
- [ ] 6.3 Cancellation and streaming/bounded-memory tests
- [ ] 6.4 Verify an available GitHub Actions macOS + Xcode image, then add CI mirroring SignalFlow's gate: `./Scripts/check-boundaries.sh` → `swift build` → `swift test`, plus SwiftFormat/SwiftLint checks, `openspec validate --strict`, a separate Xcode-app build job, artifacts, caching (`OPENSPEC_TELEMETRY=0`, `concurrency: cancel-in-progress`)

---

## Milestone B+ — Add analysis incrementally (each step leaves the app runnable)

### 7. Simple level metrics (arithmetic, not FFT/LUFS)

- [ ] 7.1 Implement sample peak, RMS, DC offset, and basic clipping detection with vDSP; surface them in the UI and in the JSON `measurements`

### 8. Loudness (complex — only now)

- [ ] 8.1 Implement integrated LUFS (BS.1770/R128) with named, engine-versioned constants
- [ ] 8.2 Implement true peak via ≥4× oversampling; flag inter-sample clipping
- [ ] 8.3 Add reference cross-check tests against FFmpeg `ebur128` with explicit tolerances

### 9. Spectral & visualization (complex)

- [ ] 9.1 Implement streamed waveform overview generation (bounded memory)
- [ ] 9.2 Implement average spectrum (documented FFT window/size)
- [ ] 9.3 Implement basic spectrogram (time × frequency × magnitude)
- [ ] 9.4 Implement significant-max-frequency estimation over time with confidence; never assert transcoding from a single cutoff

### 10. Findings & richer report

- [ ] 10.1 Estimate effective bit depth vs declared bit depth
- [ ] 10.2 Generate cautious findings with confidence + alternative explanations; no aggregate score
- [ ] 10.3 Extend the report (plain summary + technical view) and the JSON `findings[]`; expand fixtures (low-pass cut, 16→24 padding, inflated sample rate, inverted channels)
- [ ] 10.4 Detail view: technical tabs (level/loudness, waveform, spectrum, spectrogram) + accessibility/VoiceOver pass

---

## Definition of Done

- [ ] D.1 Milestone A ships first: a single supported file can be imported (drag + picker), opened, decoded, its properties shown, and exported as `schemaVersion: 1` JSON — end-to-end, no complex math
- [ ] D.2 Subsequent increments add level metrics, loudness, spectral visuals, and cautious findings, **each leaving the app runnable and demoable**
- [ ] D.3 All scenarios in this change's specs are covered by passing tests
- [ ] D.4 Originals are provably never modified (verified by hash before/after) and no network access occurs
- [ ] D.5 `swiftformat --lint`, `swiftlint`, `swift test`, `./Scripts/check-boundaries.sh`, and `openspec validate --strict` all pass with no warnings
