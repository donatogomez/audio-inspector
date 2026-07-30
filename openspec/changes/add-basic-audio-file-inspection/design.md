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
  `uncertain(value?, reason)` (reason required) · `failed(PropertyFailure)`. A **property-level**
  failure (`PropertyFailure { code, message }`, stable `code`) is a distinct type from the **global**
  `InspectionError` — a property failure is never "file could not be opened", and vice-versa.
- `TechnicalProperties` — `container`, `duration`, `sampleRate`, `channelCount`, `bitDepth`,
  `codec`, `declaredBitrate`, `estimatedBitrate` — each a `Property<…>`. `container` lives **here**
  (it is an extracted technical property), not in the file metadata. Declared and estimated bitrate
  are **separate fields**; `estimatedBitrate` is always `uncertain` with a `reason` describing the
  method and its limitations.
- `InspectionWarning` — `{ code: WarningCode (stable), field: String?, kind, message: String }`.
- `InspectionStatus` — `completed | partial(message?) | failed(InspectionError)` — the global outcome
  (its `failed` carries the **global** `InspectionError`, not a property failure).
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

## Infrastructure reader (Group 3 — `AVFoundationAudioFilePropertyReader`)

Group 3 adds the **first real** implementation of the domain port `AudioFilePropertyReading`:
`AVFoundationAudioFilePropertyReader`, living in `AudioInspectorMedia`. It reads metadata-level facts
using Apple's media stack — **no DSP**. See ADR-0011 (infrastructure boundary) and ADR-0012 (extraction
strategy).

### Responsibility & boundary

- **The use case does not change.** `InspectAudioFileUseCase` keeps depending **only** on the port; it
  cannot tell the fake from the real reader. All group-3 work sits *below* the port.
- **AVFoundation implements the port.** `AVFoundationAudioFilePropertyReader: AudioFilePropertyReading`
  is the only place Apple media APIs are touched; `AudioInspectorMedia` is the only target that imports
  AVFoundation/AudioToolbox (enforced by the build graph + `Scripts/check-boundaries.sh`).
- **The domain never knows AVFoundation.** No `AVAsset`, `AVAssetTrack`, `CMFormatDescription`,
  `AudioStreamBasicDescription`, `NSError`, `AVError`, or `OSStatus` crosses the port. `Property<Value>`
  stays generic over plain value types (ADR-0011 §4).
- **Dependencies:** AVFoundation (`AVURLAsset`/`AVAsset`, `AVAssetTrack`), CoreMedia
  (`CMAudioFormatDescription` → `AudioStreamBasicDescription`), UniformTypeIdentifiers (`UTType`, for
  `container`), and AudioToolbox (`AudioFile`/`ExtAudioFile` properties) **only as a fallback**.
- **Invariants:** never mutates the file; selects the **audio track explicitly** (ignores cover art /
  non-audio tracks); never invents a value; per-property judgement produces a `Property` case; a
  whole-file failure is a typed `throws(InspectionError)`; the file is accessed only for the inspection
  duration (ADR-0010) and that security-scoped handling stays in infrastructure.

### Flow (per inspection)

1. Resolve the security-scoped resource for the selected file (infrastructure-only; ADR-0010) and
   `defer` its release.
2. Build an `AVURLAsset` and load `duration` and the **audio** tracks. If the asset cannot be opened /
   read / is access-denied → **throw** `InspectionError` (`fileOpenFailed` / `fileUnreadable` /
   `fileAccessDenied`); nothing else runs.
3. Select the first audio track; load its format descriptions → `AudioStreamBasicDescription`.
4. Map each field independently into its `Property` case (matrix below). A single field erroring maps to
   `Property.failed`; the rest continue.
5. Read `container` from the file's UTI / asset format; assemble `TechnicalProperties` and return it.
   Warnings/status derivation stays in the (unchanged) use case.

### Mapping infrastructure → domain

Translation happens **only** inside the adapter (ADR-0011 §3). Apple errors are **caught and converted**
(ADR-0011 §5): a whole-file error → thrown `InspectionError`; a single-property extraction error →
`Property.failed(PropertyFailure(code: .propertyReadError, message:))`. Apple's `NSError`/`OSStatus` text
may inform the *message* but never the *identity* — identity is the stable domain `code` (ADR-0008).

Per-property meaning of each non-`available` state, applied uniformly:

- **`unavailable`** — the file/format simply does not carry it (the source is *silent*), e.g. no
  container-declared nominal bitrate, or no audio track for a stream-level fact.
- **`unsupported`** — the format cannot express it, e.g. `bitDepth` for a lossy codec (AAC/MP3).
- **`uncertain`** — read but not reliable: an estimate, a self-labelled-estimate API, or a value made
  untrustworthy by a source discrepancy (ADR-0012 §3). Carries a `reason`.
- **`failed`** — extracting *that* property errored (API threw / returned inconsistent data) while the
  rest of the inspection continues. Distinct from "absent" and "untrustworthy".

When Apple does **not** offer a property, it is `unavailable` (silent) or `unsupported` (format cannot
express it) — never a fabricated value and never `failed`. When a property exists but **cannot be
determined reliably**, it is `uncertain` with a `reason`.

### Property matrix (planned sources & reliability)

Reliability claims are **hypotheses pending the ADR-0003 native-decoding spike** — not asserted as fact.

| Property | Planned primary API (fallback) | Reliability | Key limitations |
| --- | --- | --- | --- |
| `container` | File UTI (`UTType`) + asset/track `AudioFormatID` | Medium–High | UTI derives from type/extension, not deep inspection; extension may mislabel. |
| `duration` | `AVAsset.load(.duration)` (`CMTime`) | High (often) | VBR/streamed MP3 without a seek table can yield an **estimated** duration. |
| `sampleRate` | ASBD `mSampleRate` (audio track) | High | Requires a decodable audio track and a valid format description. |
| `channelCount` | ASBD `mChannelsPerFrame` / channel layout | High | Ambiguous/exotic layouts may need the channel layout, not just the count. |
| `bitDepth` | ASBD `mBitsPerChannel` (PCM/lossless) | High for PCM/lossless | **Not meaningful for lossy codecs** (AAC/MP3); `mBitsPerChannel` is 0/undefined there. |
| `codec` | ASBD `AudioFormatID` (FourCC) | High | Reflects the decoded audio format, not container quirks; needs a loaded track. |
| `declaredBitrate` | AudioToolbox `kAudioFilePropertyBitRate`; PCM derived exactly from `sampleRate × channels × bitDepth` | **Not guaranteed** | Apple does not expose a container-declared nominal bitrate for all formats; often absent for lossy. |
| `estimatedBitrate` | `AVAssetTrack.estimatedDataRate`, or `fileSize × 8 / duration` | Estimate only | **Always `uncertain`** by the group-1 domain contract; carries a `reason`. |

Per-property state decision (which `Property` case each field takes, and when):

| Property | `available` when | `unavailable` when | `unsupported` when | `uncertain` when | `failed` when |
| --- | --- | --- | --- | --- | --- |
| `container` | UTI/format resolves to a known type | no type resolvable | — (a container always conceptually exists) | UTI vs actual format disagree (ADR-0012 §3) | UTI/format read errors |
| `duration` | asset reports a reliable duration | asset exposes no duration | — | duration is an estimate (VBR w/o seek table) | duration load throws |
| `sampleRate` | ASBD carries a valid rate | no audio track present | — | ASBD present but value implausible/conflicting | format-description read throws |
| `channelCount` | ASBD/layout gives a definite count | no audio track present | — | layout ambiguous | format-description read throws |
| `bitDepth` | PCM/lossless with valid `mBitsPerChannel` | lossless expected but field absent | **lossy codec** (bit depth undefined) | value present but unreliable | ASBD read throws |
| `codec` | `AudioFormatID` maps to a known codec | no audio track present | — | container vs track format disagree | format-description read throws |
| `declaredBitrate` | codec/container declares a nominal rate (or PCM derived exactly) | **no declared bitrate exposed** (common for lossy) | — | declared value looks inconsistent | bitrate property read throws |
| `estimatedBitrate` | *never* (always uncertain) | *n/a* | — | **always** — it is an estimate (with `reason`) | estimation inputs (e.g. size or duration) unreadable |

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
