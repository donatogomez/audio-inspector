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

The mapper emits `technicalProperties: {}` **iff** `inspectionStatus == .failed` (a global failure — no
property was inspected); in `completed`/`partial` it emits the eight explicit per-property entries.
Descriptive-metadata warnings (`metadata_size_unavailable` / `metadata_modified_at_unavailable`) are
produced by the **use case** from the `AudioFileReference`, never fabricated by the exporter.

### Testability without real files

Everything above the picker/AVFoundation adapter is tested with in-memory value types and a fake
`AudioFilePropertyReading` (scripted properties/states). JSON export is tested by encoding an
in-memory `InspectionReport` and asserting on the DTO/JSON. Only a small number of **integration**
tests touch real files, using deterministic fixtures generated in-test (later slice) — never
copyrighted audio.

The AVFoundation adapter itself (group 3) is likewise tested without needing real files for its
*logic*: its pure per-field mappers and the whole-file **global-error classifier** are `internal`
(not `private`), so the package test target drives them via `@testable import` with controlled
in-memory inputs — a hand-built `AudioStreamBasicDescription`, a `CMTime`, a `Float` data rate, a
`UTType`, a `LoadedProperty` state, or a constructed `CocoaError`/`AVError`. This is a **testability
seam only**: it changes visibility, not behaviour or the reader's public API, and no Apple type
crosses the domain port (the internal surface stays inside `AudioInspectorMedia`). `container`'s
mapping is split into a pure `container(fromContentType: UTType?)` helper so the load (IO, which can
`failed`) is separable from the deterministic type→`Property` mapping. A single **integration** test
generates a tiny PCM WAV/AIFF fixture in-test with public `AVAudioFile` APIs (unique temp dir,
removed via `defer`) to exercise the real load path end-to-end; SDK-dependent error *codes* are not
pinned in that integration test (the classifier's code mapping is covered deterministically by the
in-memory suite), consistent with spike 0031's SDK-dependence caveat.

## Infrastructure reader (Group 3 — `AVFoundationAudioFilePropertyReader`)

Group 3 adds the **first real** implementation of the domain port `AudioFilePropertyReading`:
`AVFoundationAudioFilePropertyReader`, living in `AudioInspectorMedia`. It reads metadata-level facts
using Apple's media stack — **no DSP**. See ADR-0011 (infrastructure boundary), ADR-0012 (extraction
strategy), and the task-3.1 evidence in
[docs/spikes/0031-audio-property-api-validation.md](../../../docs/spikes/0031-audio-property-api-validation.md)
(partially validated for PCM WAV/AIFF).

### Responsibility & boundary

- **The use case does not change.** `InspectAudioFileUseCase` keeps depending **only** on the port; it
  cannot tell the fake from the real reader. All group-3 work sits *below* the port.
- **AVFoundation implements the port.** `AVFoundationAudioFilePropertyReader: AudioFilePropertyReading`
  is the only place Apple media APIs are touched; `AudioInspectorMedia` is the only target that imports
  AVFoundation/AudioToolbox (enforced by the build graph + `Scripts/check-boundaries.sh`).
- **The domain never knows AVFoundation.** No `AVAsset`, `AVAssetTrack`, `CMFormatDescription`,
  `AudioStreamBasicDescription`, `NSError`, `AVError`, or `OSStatus` crosses the port. `Property<Value>`
  stays generic over plain value types (ADR-0011 §4).
- **Dependencies (candidate sources, subject to spike validation — see
  [audio-property-matrix.md](../../../docs/audio-property-matrix.md)):** AVFoundation and CoreMedia for
  the asset, its audio track, and the track's stream format description; UniformTypeIdentifiers only as
  a **weak hint** for `container`. **AudioToolbox is a fallback under evaluation, not a decided
  requirement** — it must not shape the adapter's initial design (ADR-0012). Every concrete API name in
  the matrix is *expected*, not contractual, until the ADR-0003 spike validates it.
- **Invariants:** never mutates the file; selects the **audio track explicitly** (ignores cover art /
  non-audio tracks); never invents a value; per-property judgement produces a `Property` case; a
  whole-file failure is a typed `throws(InspectionError)`; the file is accessed only for the inspection
  duration (ADR-0010) and that security-scoped handling stays in infrastructure.

### Flow (per inspection)

1. Resolve the security-scoped resource for the selected file (infrastructure-only; ADR-0010) and
   `defer` its release. Because the domain `AudioFileReference` carries no URL, the adapter obtains the
   URL through a **constructor-injected resolver seam** (`(AudioFileReference) -> URL?`); the sandbox
   file-selection work (group 6) wires the concrete security-scoped provider, and until then the default
   resolver yields no URL (a global access failure). The 3.2 skeleton establishes this seam only.
2. Build an `AVURLAsset` and load the **audio** tracks — the **only** whole-file step. If that load
   fails (the asset cannot be opened / read / is access-denied) → **throw** a **global** `InspectionError`
   (`fileAccessDenied` for permission denial, `fileUnreadable` for an unrecognizable/corrupt file, else
   the `fileOpenFailed` fallback — classified by *scope*, not by which API threw, ADR-0011 §5); nothing
   else runs.
3. Select the audio track by the deterministic **track-selection policy** below, then run the remaining
   loads as **per-property** loads that do **not** abort the inspection: the track's format
   description(s), its `estimatedDataRate`, and the asset `duration`. Each captures value / absence /
   read-error, so a thrown load becomes a per-property `Property.failed` (the ASBD-dependent fields —
   `sampleRate`/`channelCount`/`bitDepth`/`codec` — fail together when the format-descriptions load
   errors) rather than a global failure.
4. Map each field independently into its `Property` case (per-field policy below; full matrix in
   [audio-property-matrix.md](../../../docs/audio-property-matrix.md)). A single field erroring maps to
   `Property.failed(PropertyFailure(.propertyReadError, …))`; the rest continue. No `NSError`/`AVError`/
   `OSStatus` crosses the port — Apple errors are inspected only inside the adapter.
5. Read `container`; assemble `TechnicalProperties` and return it. Warnings/status derivation stays in
   the (unchanged) use case.

### Track-selection policy (deterministic)

The audio track is chosen by an explicit, revisable rule — never an undefined "primary track":

- **Zero audio tracks** → every stream-level field (`sampleRate`, `channelCount`, `bitDepth`, `codec`)
  is `unavailable`; this is not a global failure by itself.
- **Exactly one audio track** → use it.
- **Multiple audio tracks** → select the **first** element of the returned audio tracks (the
  framework-provided order is **observable but its semantics are not guaranteed** — this is a
  provisional, revisable rule, not a claim of a "primary/preferred" track) and record that a selection
  was made; alternate/auxiliary tracks are ignored in this slice. Multi-track ordering was **not
  validated** by spike 0031 (single-track fixtures) — a later concern.
- **Empty or missing format description** → the affected field is `unavailable` (no data), not `failed`.
- **Multiple format descriptions, or a format change within the track** → if they disagree on a field,
  that field is `uncertain` with a `reason`; the reader does not pick one and present it as fact.
- **A read that genuinely errors** (the description load throws) → the affected field is `failed`.

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

### Per-property policy (summary — full matrix is a separate pre-spike document)

The detailed source/reliability/state matrix lives in
[docs/audio-property-matrix.md](../../../docs/audio-property-matrix.md) (**status: partially validated
by spike 0031** for PCM WAV/AIFF — observed/inferred/not-tested marked there). The contract-level rules
per field (the most conservative statement; the report may carry more detail):

- **`container`** — spike 0031 found **no direct real-container signal among the AVFoundation/CoreMedia
  APIs evaluated** (only the codec), and the UTI is extension-driven and was provably wrong for a WAV
  renamed `.aiff` (reported `public.aiff-audio`). So in this slice `container` is `uncertain` with a
  `reason` when inferred from UTI/extension, and `unavailable` when no type is resolvable — **never
  `available`** on current evidence. Conflicting signals → `uncertain` (no invented reconciliation).
  **No deep byte inspection.**
- **`duration`** — a **positive**, finite, numeric duration with no estimate signal → `available`; a
  returned **`0.0`** → `uncertain`/`unavailable` unless a legitimate zero-length is evidenced (spike
  0031: a truncated copy returned a valid+numeric+finite `0.0`, so a bare "finite → available" rule is
  insufficient); indefinite/non-numeric → `unavailable`/`uncertain`; load error → `failed`. There is
  **no guaranteed public signal** to prove exact-vs-estimated, so the reader does not promise that
  split — a documented limitation.
- **`sampleRate` / `channelCount`** — read from the selected track's format description per the
  track-selection policy above: valid value → `available`; no track → `unavailable`; descriptions
  disagree/implausible → `uncertain`; read error → `failed`.
- **`codec`** — emit a **stable, non-localized token** derived from the track's technical format
  identifier (e.g. a serialized `AudioFormatID`/FourCC); **never** a localized system description.
  Full normalization is out of scope; the exact token serialization is pending the spike. Known
  identifier → `available`; no track → `unavailable`; container vs track disagree → `uncertain`.
- **`bitDepth`** — a **conditional capability**: `available` only when a semantically-applicable value
  is present (PCM/lossless); **`unsupported` for lossy codecs** (not a stand-in for "the API didn't give
  it"); ambiguous signal → `uncertain`; absent where expected → `unavailable`. Bits-per-channel is not
  interchangeable with bits-per-sample or packet/frame size, and is **never inferred by formula**.
- **`declaredBitrate` vs `estimatedBitrate`** — the two are kept strictly separate:
  - `declaredBitrate` is a nominal rate **directly declared** by container/codec metadata, with **no
    self-computation**. If only an estimate exists (including any framework value whose API self-labels
    as an estimate), `declaredBitrate` is `unavailable`. PCM's exact size is a *computation*, so it does
    **not** make `declaredBitrate` `available` either — it feeds the estimate.
  - `estimatedBitrate` is **always `uncertain`** (group-1 contract), carrying the method in its
    `reason`. Its candidate formula, prerequisites, and why it is always approximate are documented in
    the matrix (spike-pending, non-contractual); it is not computed when its inputs are missing.

### Global vs per-property errors (semantic rule, not an SDK code table)

The adapter classifies an Apple error by its **scope/effect**, not by enumerating `NSError`/`OSStatus`
codes (which vary by SDK):

- If the error prevents producing **any** useful set of properties (cannot open, unreadable input,
  access denied) → it is **global**: throw `InspectionError` with the semantically matching stable
  `code`.
- If the error breaks **one** extraction while the rest can still be read → it is **per-property**:
  `Property.failed(PropertyFailure(code: .propertyReadError, …))`. E.g. a `load(.duration)` failure when
  the tracks/format descriptions still loaded is a **property-level** `duration` failure, **not** global
  — the classifier keys on scope, never on which API threw (spike 0031, Experiment H).

Absence is never `failed`; it is `unavailable`/`unsupported` per the field.

## Sandbox & file selection (summary — see ADR-0010 and ADR-0013)

Native open panel under App Sandbox; the panel grants user-scoped access to the chosen file. Access
is held only for the **duration of the inspection** via `startAccessingSecurityScopedResource`
/ `stopAccessingSecurityScopedResource`. **No bookmark persistence** in this slice (persistence is
deferred). Absolute paths are not treated as stable identity and are not exported by default; the
result carries a sandbox-safe representation. The only entitlement beyond App Sandbox is
`com.apple.security.files.user-selected.read-write` (ADR-0013) — required because the same executable
setting covers both the inspected file and the save-panel export destination. No folder-wide or
system-wide entitlement is added; the **source file is still treated as strictly read-only by the
design and the code**, and the only thing written is the export destination the user picked.

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
