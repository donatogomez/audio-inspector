# Implementation Tasks

Spec only in this step — **no task below is implemented or checked yet.** Each task is small,
verifiable, maps to one logical commit, and contains nothing out of scope.

## 1. Domain models & contracts

- [x] 1.1 Add `Property<Value>` (exhaustive sum type; conditional `Sendable`/`Equatable`) plus stable codes/errors at two distinct levels: `PropertyFailure`/`PropertyFailureCode` (property-level, in `Property.failed`) and `InspectionError`/`InspectionErrorCode` (global), plus `WarningCode`/`WarningKind`. (Canonical name is `Property<Value>`; no separate `PropertyState` type — the state is the case.)
- [x] 1.2 Add `AudioFileReference`, `AudioFileSource`, `TechnicalProperties`, `InspectionWarning`, `InspectionStatus`, `InspectionReport` value types (Sendable/Equatable)
- [x] 1.3 Add domain port `AudioFilePropertyReading` (`async throws(InspectionError) -> TechnicalProperties`). `ReportExporting` is **not** a domain port — it lives in the export layer (no domain use case exports); see design.md and ADR-0009.
- [x] 1.4 Unit tests for the domain value types, invariants, stable codes, and Sendable conformance (pure, no files)

## 2. Use case with test doubles

- [x] 2.1 Implement `InspectAudioFileUseCase` (nonisolated async): read properties → derive warnings → compute global status → build report
- [x] 2.2 Add a fake `AudioFilePropertyReading` in `AudioInspectorTesting`
- [x] 2.3 Unit tests: available/partial/failed outcomes, warning derivation, declared-vs-estimated bitrate — all with the fake, no real files

## 3. Basic technical inspection (infrastructure — `AVFoundationAudioFilePropertyReader`)

Spec fixed by design.md §"Infrastructure reader", ADR-0011 (boundary, Accepted) and ADR-0012
(extraction strategy, **Proposed**), with the candidate matrix in `docs/audio-property-matrix.md`
(pre-spike hypothesis). No DSP. The use case and port are unchanged. Native-API sources/reliability are
hypotheses pending the ADR-0003 native-decoding spike, so the spike is the first task.

- [ ] 3.1 **Documented technical spike**: validate the candidate sources against real + synthetic fixtures for MP3, WAV, AIFF, FLAC, ALAC, AAC, M4A; confirm which properties are reliable/approximate/absent; record findings and promote ADR-0012 (or update it if a gap is found)
- [ ] 3.2 Adapter skeleton: `AVFoundationAudioFilePropertyReader` in `AudioInspectorMedia` conforming to `AudioFilePropertyReading`, implementing the deterministic track-selection policy; no field mapping yet
- [ ] 3.3 Map the reliable structural facts from the selected track's format description: `sampleRate` and `channelCount` (valid → `available`; no track → `unavailable`; disagreement → `uncertain`; read error → `failed`)
- [ ] 3.4 Map `container`, `duration`, and `codec` with their uncertainty policies (direct recognition → `available`; UTI/extension-only or estimate/discrepancy → `uncertain`; `codec` emits a stable non-localized token)
- [ ] 3.5 Map the conditional capabilities: `bitDepth` (PCM/lossless `available`, lossy `unsupported`, never formula-inferred), and the two bitrates kept separate — `declaredBitrate` (directly declared or `unavailable`, no self-computation) and `estimatedBitrate` (**always `uncertain`** with a `reason`)
- [ ] 3.6 Translate platform errors into domain errors by scope: whole-file failures → thrown `InspectionError` (`fileOpenFailed`/`fileUnreadable`/`fileAccessDenied`); single-property errors → `Property.failed(.propertyReadError)` — no `NSError`/`OSStatus` crosses the port (ADR-0011 §5)
- [ ] 3.7 Tests: unit tests for the mapper and error-translation with controlled in-memory inputs (no real files), **plus** one minimal integration test on a fixture generated in-test with public APIs and stably writable in CI (PCM WAV/AIFF); formats that macOS can read but not reliably generate in CI (e.g. lossy) are covered by the 3.1 spike / manual exploratory validation, not a CI codec matrix; no copyrighted audio; fixtures cleaned up

## 4. JSON export (schemaVersion 1)

- [ ] 4.1 Implement the `Codable` DTO + `JSONEncoder` `ReportExporting` in the app/infra layer (domain stays free of JSONEncoder), per `docs/json-schema-v1.md`
- [ ] 4.2 Ensure states distinguish absent/unsupported/uncertain/failed and no absolute private path is emitted by default
- [ ] 4.3 Unit tests: encode in-memory reports; assert top-level fields, per-property states, and stable field names

## 5. Minimal presentation

- [ ] 5.1 Minimal SwiftUI view (feature target) showing the report: file identity, properties with states, warnings, status
- [ ] 5.2 An export action that writes the JSON

## 6. File selection (sandbox)

- [ ] 6.1 Native open-panel selection under App Sandbox; hold security-scoped access only for the inspection duration (ADR-0010); no bookmark persistence
- [ ] 6.2 Wire selection → use case → presentation in the composition root

## 7. Integration & end-to-end

- [ ] 7.1 End-to-end test/flow: select (fixture) → inspect → report → export JSON, no DSP
- [ ] 7.2 Verify originals are never modified (hash before/after) and no network access occurs

## 8. Documentation & validation

- [ ] 8.1 Update any developer docs strictly needed for the slice; confirm ADR-0008/0009/0010 reflect the implementation
- [ ] 8.2 `swift build -Xswiftc -warnings-as-errors`, `swift test`, `./Scripts/check-boundaries.sh`, `openspec validate --all --strict` all green

## Acceptance criteria

- [ ] AC.1 A user can select one local audio file and see a structured report with per-property states, warnings, and a global status — with **no DSP**
- [ ] AC.2 Unavailable/unsupported/uncertain/failed properties are represented explicitly; no value is invented; no inference is shown as fact
- [ ] AC.3 Declared and estimated bitrate are separate fields
- [ ] AC.4 The report exports as `schemaVersion` 1 JSON per `docs/json-schema-v1.md`, with no absolute private path by default
- [ ] AC.5 A global failure (unopenable file) yields `inspectionStatus = failed` with no fabricated data and a responsive app
- [ ] AC.6 The domain imports none of: AVFoundation, AudioToolbox, URL-bookmark APIs, SwiftUI, AppKit, JSONEncoder; `check-boundaries.sh` passes
- [ ] AC.7 All scenarios in the `audio-file-inspection` spec are covered by tests
