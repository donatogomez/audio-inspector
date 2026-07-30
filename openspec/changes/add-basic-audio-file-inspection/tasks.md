# Implementation Tasks

Spec only in this step — **no task below is implemented or checked yet.** Each task is small,
verifiable, maps to one logical commit, and contains nothing out of scope.

## 1. Domain models & contracts

- [ ] 1.1 Add `PropertyState` and `Property<Value>` (Sendable) with the value/state invariant
- [ ] 1.2 Add `AudioFileReference`, `TechnicalProperties`, `InspectionWarning`, `InspectionStatus`, `InspectionReport` value types (Sendable)
- [ ] 1.3 Add domain ports `AudioFilePropertyReading` and `ReportExporting`
- [ ] 1.4 Unit tests for the domain value types and invariants (pure, no files)

## 2. Use case with test doubles

- [ ] 2.1 Implement `InspectAudioFileUseCase` (nonisolated async): read properties → derive warnings → compute global status → build report
- [ ] 2.2 Add a fake `AudioFilePropertyReading` in `AudioInspectorTesting`
- [ ] 2.3 Unit tests: available/partial/failed outcomes, warning derivation, declared-vs-estimated bitrate — all with the fake, no real files

## 3. Basic technical inspection (infrastructure)

- [ ] 3.1 Implement the AVFoundation/AudioToolbox adapter for `AudioFilePropertyReading` (metadata only, no DSP), mapping each field to the correct `PropertyState`
- [ ] 3.2 Map file metadata (name, extension, size, modification date, safe `source` descriptor) into `AudioFileReference`; read `container` as a technical property into `TechnicalProperties`
- [ ] 3.3 Integration tests against a few in-test generated fixtures (no copyrighted audio)

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
