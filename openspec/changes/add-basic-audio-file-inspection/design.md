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

- `AudioFileReference` — an opaque, domain-level handle for a selected file: a stable `id`,
  `displayName`, `fileExtension`, `sizeBytes`, `safePath` (display representation), and
  `modifiedAt` (file metadata). **No `URL`, no bookmark, no AVFoundation** — infrastructure produces
  this from the picked file.
- `PropertyState` — `available | unavailable | unsupported | uncertain | failed` (ADR-0008).
- `Property<Value>` — pairs a `PropertyState` with an optional `Value` and an optional `note`; the
  invariant is that only `available`/`uncertain` may carry a value.
- `TechnicalProperties` — `container`, `duration` (seconds), `sampleRate` (Hz), `channelCount`,
  `bitDepth` (bits), `codec`, `declaredBitrate` (bps), `estimatedBitrate` (bps) — each a
  `Property<…>`. Declared and estimated bitrate are **separate fields**.
- `InspectionWarning` — `{ field: String?, kind: PropertyState, message: String }`.
- `InspectionStatus` — `completed | partial | failed(message)` — the global outcome.
- `InspectionReport` — `{ file: AudioFileReference, properties: TechnicalProperties,
  warnings: [InspectionWarning], status: InspectionStatus, generatedAt: Date }`. Pure data; it does
  **not** know about JSON (ADR-0009).

### Ports (protocols in `AudioInspectorDomain`)

- `AudioFilePropertyReading` — `func readProperties(of: AudioFileReference) async -> TechnicalProperties`.
  Implemented later by `AudioInspectorMedia` using AVFoundation/AudioToolbox; the domain sees only
  its own value types, so AVFoundation never leaks inward.
- `ReportExporting` — `func export(_ report: InspectionReport) throws -> Data`. Implemented outside
  the domain (App/infra) with a `Codable` DTO + `JSONEncoder` (ADR-0009); the domain does **not**
  import `JSONEncoder`.

### Use case

- `InspectAudioFileUseCase` (`nonisolated`, `async`): takes an `AudioFileReference`, calls
  `AudioFilePropertyReading`, derives warnings from any non-`available` property, computes the global
  `InspectionStatus`, and returns an `InspectionReport`. It owns no state and is fully testable with
  a **fake** `AudioFilePropertyReading` — no real files needed.

### Infrastructure (later commits, not this spec step)

- `AudioInspectorMedia`: the file picker adapter and the AVFoundation/AudioToolbox implementation of
  `AudioFilePropertyReading`, mapping platform metadata to domain value types and choosing the right
  `PropertyState` per field. Sandbox handling per ADR-0010.
- App composition root: the `Codable` DTO + `JSONEncoder` implementation of `ReportExporting`, wired
  and injected. Minimal SwiftUI presentation in a feature target.

### JSON export (`schemaVersion` 1)

The field-level contract lives in `docs/json-schema-v1.md` (updated by this change to the concrete
first-export shape). The domain report maps to a `Codable` DTO in the export layer; the DTO adds
`schemaVersion` and `generator`. See ADR-0009. Absent/unsupported/uncertain/error are distinguished
by each property's `state`.

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
  `PropertyState` exists; map missing/uncertain fields to `unsupported`/`unavailable`/`uncertain`
  rather than guessing. Validated by the later native-decoding spike (bootstrap ADR-0003).
- **Bit depth / codec reliability varies** → only report them `available` when reliably
  determinable; otherwise `uncertain`/`unsupported`.
- **`Property<Value>` is generic** → keep it small and `Sendable`; ensure the DTO mapping stays
  explicit so the JSON shape is stable.
- **JSON field-name reconciliation** with the earlier illustrative `docs/json-schema-v1.md` (see
  Open Questions).

## Open Questions

- **JSON v1 field names**: this change renames the earlier illustrative top-level fields
  (`fileIdentity`→`inspectedFile`, `mediaProperties`→`technicalProperties`,
  `analysisStatus`→`inspectionStatus`, engine id→`generator`) and adds top-level `warnings`, with
  DSP-era `measurements`/`findings` becoming **additive future** fields (still v1). Confirm this is
  the desired canonical v1 shape.
- **Umbrella `bootstrap-…` change**: it still proposes overlapping capabilities (`file-import`,
  `audio-inspection`, `analysis-reporting`). Recommend later narrowing or retiring it so per-slice
  changes are the source of truth. Governance decision for the maintainer.
- **Path representation**: exact form of the sandbox-safe path (display name only vs a redacted/
  relativized path). Leaning: display name + last path component; never the absolute path.
