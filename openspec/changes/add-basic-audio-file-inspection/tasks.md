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
- [x] 2.4 Derive descriptive-metadata warnings in `InspectAudioFileUseCase`: emit `metadata_size_unavailable` when `sizeBytes == nil` and `metadata_modified_at_unavailable` when `modifiedAt == nil` (both codes when both are absent), derived from the `AudioFileReference` in **both** the successful and the global-failure paths, combined with the technical-property warnings **with no duplicates**; global status is `.completed` when there is no global failure and no warnings, `.partial` when there is no global failure and ≥1 warning, and `.failed(error)` is **preserved on a global (reader-thrown) failure even when metadata warnings are present** (never recomputed to `.partial`). Unit tests cover every case. Implements the `docs/json-schema-v1.md` plain-nullable-metadata rule. **No JSON-exporter code** (DTO/mapper/encoder/`ReportExporting` stay in group 4).

## 3. Basic technical inspection (infrastructure — `AVFoundationAudioFilePropertyReader`)

Spec fixed by design.md §"Infrastructure reader", ADR-0011 (boundary, Accepted) and ADR-0012
(extraction strategy, **Proposed**), with the candidate matrix in `docs/audio-property-matrix.md`
(pre-spike hypothesis). No DSP. The use case and port are unchanged. Native-API sources/reliability are
hypotheses pending the ADR-0003 native-decoding spike, so the spike is the first task.

- [x] 3.1 **Documented technical spike** — validated candidate sources against runtime-generated PCM WAV/AIFF fixtures; recorded which properties are reliable/approximate/absent, the track/container/duration/codec/bitDepth/bitrate/error policies, and the AudioToolbox decision in `docs/spikes/0031-audio-property-api-validation.md`; ADR-0012 updated (stays Proposed) and the matrix marked partially-validated. Lossy/FLAC/ALAC/AAC/M4A remain for 3.3+ / a wider spike.
- [x] 3.2 Adapter skeleton: `AVFoundationAudioFilePropertyReader` in `AudioInspectorMedia` conforming to `AudioFilePropertyReading`, implementing the deterministic track-selection policy (open asset → load audio tracks → select `track[0]` → first format description → assemble via per-field mappers); field mappers are conservative placeholders (deferred to 3.3–3.5), a global open/track-load failure throws `InspectionError`, and the URL is obtained via a constructor-injected resolver seam (group 6 wires the security-scoped provider). No field mapping, no AudioToolbox.
- [x] 3.3 Map the reliable structural facts from the selected track's format description: `sampleRate` and `channelCount` (valid → `available`; no track → `unavailable`; disagreement → `uncertain`; read error → `failed`). Implemented via a shared ASBD-extraction helper (value-copied from the first format description, no pointer retained); `sampleRate` from `mSampleRate` (finite, >0, exact `Int`) and `channelCount` from `mChannelsPerFrame` (>0), each yielding `available` (valid) or `unavailable` (no track/ASBD or a non-representable value — no fabricated value, per design). The `uncertain` (disagreement across multiple format descriptions — only the first is kept, so it is undetectable here; a documented later concern) and `failed` (a genuine format-description read error → per-property `failed`, per design §Track-selection) states are **not** part of this field-mapping task; the global-vs-per-property error scope is owned by task 3.6.
- [x] 3.4 Map `container`, `duration`, and `codec` with their uncertainty policies (direct recognition → `available`; UTI/extension-only or estimate/discrepancy → `uncertain`; `codec` emits a stable non-localized token). `container` from `URLResourceValues.contentType` (a `UTType`): a resolved type → `uncertain` carrying the non-localized UTI identifier (no direct-recognition source exists — spike 0031/F — so never `available`), no type → `unavailable`. `duration` from the already-loaded `CMTime`: positive finite numeric → `available`; **zero → `uncertain` keeping the observed `0`**; **negative → `unavailable`** (invalid); `nil`/invalid/indefinite/non-numeric/non-finite → `unavailable` (errored→`failed` refinement is 3.6). `codec` from the reused ASBD `mFormatID` → a stable big-endian FourCC token (printable ASCII with **trailing-space padding trimmed**, e.g. `'aac '`→`aac`; NUL/control/non-ASCII/leading-or-internal-space → fixed-width uppercase hex — finalizing the serialization the spike deferred), `available` for a non-zero id, else `unavailable`. Discrepancy reconciliation and the failed/error taxonomy stay with 3.6.
- [x] 3.5 Map the conditional capabilities: `bitDepth` (PCM/lossless `available`, lossy `unsupported`, never formula-inferred), and the two bitrates kept separate — `declaredBitrate` (directly declared or `unavailable`, no self-computation) and `estimatedBitrate` (**always `uncertain`** with a `reason`). `bitDepth` from the reused ASBD `mBitsPerChannel` (never byte/packet-derived): Linear PCM (`kAudioFormatLinearPCM`) with `>0` → `available`; PCM with `0` → `unavailable`; **any non-PCM → `unavailable`**. This `[x]` covers **only the spike-validated PCM capability**: the criterion's `lossless → available` and `lossy → unsupported` are **explicitly deferred** — the spike (0031) validated no compressed format (no ALAC/FLAC/AAC/MP3 fixtures) and ADR-0012 (still Proposed) forbids a codec table / classifying by elimination, so ALAC/FLAC are **not** yet mapped to `available` and lossy codecs are **not** yet mapped to `unsupported` (both would be unvalidated false precision); they are conservatively `unavailable` until a later compressed-fixture validation resolves ADR-0012. `declaredBitrate` → `unavailable` (no direct source in AVFoundation per spike 0031/G; no self-computation, no AudioToolbox). `estimatedBitrate` → **always `uncertain`** (per criterion/matrix/design; never `unavailable`): carries the loaded `estimatedDataRate` as the tentative value only when finite, `>0`, and exactly an `Int` (no rounding), else `uncertain` with no value (spike 0031/G observed `0` for PCM). No fileSize/duration self-computation.
- [x] 3.6 Translate platform errors into domain errors by scope: whole-file failures → thrown `InspectionError` (`fileOpenFailed`/`fileUnreadable`/`fileAccessDenied`); single-property errors → `Property.failed(.propertyReadError)` — no `NSError`/`OSStatus` crosses the port (ADR-0011 §5). A private `LoadedProperty<Value>` (value/unavailable/failed) captures each per-property load, so the flow distinguishes absence from a read error without retaining any Apple error. Only the `loadTracks` load is global (classified by bridged `CocoaError`/`AVError` → `fileAccessDenied`/`fileUnreadable`/`fileOpenFailed` fallback); format-descriptions/duration/estimatedDataRate/resourceValues read errors become per-property `Property.failed(.propertyReadError)` (deterministic, non-localized messages). `declaredBitrate` stays `unavailable` (absent capability, not an error). `estimatedBitrate` stays always-`uncertain` except a read error → `failed` (matrix-sanctioned). Existing valid mappings and the FourCC token are unchanged; the use case's `property_extraction_failed` warning policy already covers `.failed`.
- [x] 3.7 Tests: unit tests for the mapper and error-translation with controlled in-memory inputs (no real files), **plus** one minimal integration test on a fixture generated in-test with public APIs and stably writable in CI (PCM WAV/AIFF); formats that macOS can read but not reliably generate in CI (e.g. lossy) are covered by the 3.1 spike / manual exploratory validation, not a CI codec matrix; no copyrighted audio; fixtures cleaned up. Implemented with a minimal testability seam: the adapter's pure field mappers and the global-error classifier are `internal` (reachable via `@testable import`, no Apple type crosses the domain), and `container`'s `UTType? → Property` mapping is split into a pure `container(fromContentType:)` helper so absence/presence map without filesystem access. Three test files added — `AVFoundationPropertyMappingTests` (pure per-field mapping incl. FourCC token, PCM/zero/negative/NaN/∞/fractional, zero/negative/indefinite/invalid duration, always-uncertain estimated bitrate, per-property `failed` scope), `AVFoundationErrorTranslationTests` (`globalError(from:)` over controlled `CocoaError`/`AVError`/generic), and `AVFoundationPropertyReaderIntegrationTests` (in-test PCM WAV+AIFF fixture → domain properties; deterministic global-throw paths for no-URL / missing file / unreadable bytes). Fixtures are generated with public `AVAudioFile` APIs in a unique temp dir and removed via `defer`; no repo binaries, no network.

## 4. JSON export (schemaVersion 1)

- [x] 4.1 Implement the `Codable` DTO + `JSONEncoder` `ReportExporting` in the app/infra layer (domain stays free of JSONEncoder), per `docs/json-schema-v1.md`
- [x] 4.2 Ensure states distinguish absent/unsupported/uncertain/failed and no absolute private path is emitted by default
- [x] 4.3 Unit tests: encode in-memory reports; assert top-level fields, per-property states, and stable field names

## 5. Minimal presentation

- [x] 5.1 Minimal SwiftUI view (feature target) showing the report: file identity, properties with states, warnings, status
- [x] 5.2 An export action that writes the JSON

## 6. File selection (sandbox)

- [x] 6.1 Native open-panel selection under App Sandbox; hold security-scoped access only for the inspection duration (ADR-0010); no bookmark persistence; set the user-selected file entitlement to read-write per ADR-0013 (source stays read-only by design; hash-verified in 7.2)
- [x] 6.2 Wire selection → use case → presentation in the composition root

## 7. Integration & end-to-end

- [x] 7.1 End-to-end test/flow: select (fixture) → inspect → report → export JSON, no DSP
- [x] 7.2 Verify originals are never modified (hash before/after) and no network access occurs

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
