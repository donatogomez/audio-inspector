## Context

First functional vertical slice, spec only. It must run end-to-end (select → open → read basic
properties → show → export) with **no DSP**. It also establishes three durable patterns reused by
every later slice: how property availability/certainty is modelled (ADR-0008), how the domain report
is kept separate from the JSON contract (ADR-0009), and how sandboxed file access works (ADR-0010).
Boundaries are fixed by `docs/architecture.md`, ADR-0001/0005, and `Scripts/check-boundaries.sh`.

## Goals / Non-Goals

**Goals:** prove the full path; keep the domain pure and testable without opening real files;
represent every property's state explicitly; produce a `schemaVersion` 1 JSON with a sandbox-safe
file representation.

**Non-Goals (out of scope):** waveform, FFT, spectrogram, LUFS, true peak, clipping, phase, dynamic
range, silence detection, transcode/codec-authenticity detection, fingerprinting, metadata editing,
batch import, drag-and-drop, persistence, recent files, file comparison, FFmpeg, any quality score,
any forensic conclusion.

## Decisions

### Domain models (in `AudioInspectorDomain`, all `Sendable` value types)

- `AudioFileReference` — an opaque, domain-level descriptor of the selected file: a stable `id`,
  `displayName`, `fileExtension`, `sizeBytes`, `modifiedAt` (file metadata), and a `source` kind
  (`userSelectedLocalFile`). **No path, no `URL`, no bookmark, no AVFoundation** — the actual
  security-scoped access handle stays in infrastructure (ADR-0010) and is never part of this
  exported identity.
- `Property<Value>` — an **exhaustive sum type** (ADR-0008), not a struct, so invalid states are
  unrepresentable: `available(Value)` · `unavailable(reason?)` · `unsupported(reason?)` ·
  `uncertain(value?, reason)` (reason required) · `failed(code, message)`. `code` is a **stable**
  identifier; `message` is descriptive and not part of the error's identity.
- `TechnicalProperties` — `container`, `duration`, `sampleRate`, `channelCount`, `bitDepth`,
  `codec`, `declaredBitrate`, `estimatedBitrate` — each a `Property<…>`. `container` lives **here**
  (it is an extracted technical property), not in the file metadata. Declared and estimated bitrate
  are **separate fields**; `estimatedBitrate` is always `uncertain` with a `reason` describing the
  method and its limitations.
- `InspectionWarning` — `{ code: WarningCode (stable), field: String?, kind, message: String }`.
- `InspectionStatus` — `completed | partial | failed(code, message)` — the global outcome.
- `InspectionReport` — `{ file: AudioFileReference, properties: TechnicalProperties,
  warnings: [InspectionWarning], status: InspectionStatus }`. Pure data; it does **not** know about
  JSON, and it does **not** carry `schemaVersion`, `generatedAt`, or `generator` — those belong to
  the export envelope (ADR-0009).

### Ports (protocol in `AudioInspectorDomain`)

- `AudioFilePropertyReading` — `func readProperties(of: AudioFileReference) async throws(InspectionError) -> TechnicalProperties`.
  Implemented later by `AudioInspectorMedia` using AVFoundation/AudioToolbox; the domain sees only
  its own value types, so AVFoundation never leaks inward. Narrow responsibility — it only *reads*:
  per-property issues are `Property` cases; a **global** failure is a typed `throws(InspectionError)`.

**`ReportExporting` is NOT a domain port** (decision, group 1). No domain use case exports — the use
case returns a domain `InspectionReport`, and exporting it to JSON is a delivery concern invoked by
the app/UI layer. Defining an export protocol in the domain would be a port with no domain consumer.
So the export protocol/DTO/`JSONEncoder` live entirely in the **export layer** (ADR-0009); the
domain stays free of any export concept.

### Use case

- `InspectAudioFileUseCase` (`nonisolated`, `async`): takes an `AudioFileReference`, calls
  `AudioFilePropertyReading`, derives warnings from any non-`available` property, computes the global
  `InspectionStatus` (mapping a thrown `InspectionError` to `.failed`), and returns an
  `InspectionReport`. It owns no state and is fully testable with a **fake** `AudioFilePropertyReading`
  — no real files needed.

### Infrastructure (later commits, not this spec step)

- `AudioInspectorMedia`: the file picker adapter and the AVFoundation/AudioToolbox implementation of
  `AudioFilePropertyReading`, mapping platform metadata to domain value types and choosing the right
  `Property` case per field. Sandbox handling per ADR-0010.
- Export layer: the `Codable` DTO + `JSONEncoder` that maps an `InspectionReport` to the
  `schemaVersion` 1 contract, wired in the composition root. Minimal SwiftUI presentation in a
  feature target.

### JSON export (`schemaVersion` 1)

The field-level contract lives in `docs/json-schema-v1.md` (the canonical v1 shape). The exporter
creates the **envelope** (`schemaVersion`, `generatedAt`, `generator`) and maps the domain report
into a **flat** `Codable` DTO where each property is `{ state, value, unit?, reason?, error? }`
(ADR-0009). The file origin is exported as a safe `source` object (`kind`, `displayName`,
`locationDisclosure: "omitted"`) — **no path, URL, bookmark, or parent directory** (ADR-0010).
Absent/unsupported/uncertain/error are distinguished by each property's `state`; `container` is a
technical property, not file metadata.

### Testability without real files

Everything above the picker/AVFoundation adapter is tested with in-memory value types and a fake
`AudioFilePropertyReading` (scripted properties/states). JSON export is tested by encoding an
in-memory `InspectionReport` and asserting on the DTO/JSON. Only a small number of **integration**
tests touch real files, using deterministic fixtures generated in-test (later slice) — never
copyrighted audio.

## Sandbox & file selection (summary — see ADR-0010)

Native open panel under App Sandbox; the panel grants user-scoped read access to the chosen file.
Access is held only for the **duration of the inspection** via `startAccessingSecurityScopedResource`
/ `stopAccessingSecurityScopedResource`. **No bookmark persistence** in this slice (persistence is
deferred). Absolute paths are not treated as stable identity and are not exported by default; the
result carries a sandbox-safe representation. No new entitlement beyond App Sandbox is requested.

## Risks / Trade-offs

- **AVFoundation may not expose some properties for some formats** → that is exactly why
  the `Property` sum type exists; map missing/uncertain fields to `unsupported`/`unavailable`/`uncertain`
  rather than guessing. Validated by the later native-decoding spike (bootstrap ADR-0003).
- **Bit depth / codec reliability varies** → only report them `available` when reliably
  determinable; otherwise `uncertain`/`unsupported`.
- **`Property<Value>` is generic** → keep it small and `Sendable`; ensure the DTO mapping stays
  explicit so the JSON shape is stable.
- **JSON field-name reconciliation** with the earlier illustrative `docs/json-schema-v1.md` (see
  Open Questions).

## Open Questions

- **Umbrella `bootstrap-…` change** (governance, for the maintainer): analysis shows it is fully
  superseded — its foundational content shipped as plain commits + the accepted `project-skeleton`
  spec, its basic-inspection content is now governed here, and its loudness/spectral/findings
  content belongs to future per-slice changes. Narrowing it would empty it, so per the "if it becomes
  purposeless, stop and propose" rule it is **not** edited here; recommendation is to archive it as
  *superseded* (or replace it with a lean foundational change). Awaiting the maintainer's decision.
  Until then, the obsolete JSON field names exist **only** inside that (never-accepted, to-be-retired)
  change — never in an accepted spec or in the canonical `docs/json-schema-v1.md`.

_Resolved during consistency review:_ JSON v1 field names are fixed as canonical in
`docs/json-schema-v1.md`; the file origin uses a safe `source` object (no path) with
`locationDisclosure: "omitted"`; the property model is an exhaustive sum type (ADR-0008).
