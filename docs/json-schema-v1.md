# JSON export — schema version 1

The canonical **contract** for Audio Inspector's JSON export. Specification only — the `Codable`
DTO that produces it lives in the export layer (ADR-0009), never in the domain. This is the
field-level reference the `audio-file-inspection` OpenSpec capability points to. It is deliberately
minimal for the first slice (technical properties, no DSP) and grows **additively**.

## Envelope vs. domain report

`schemaVersion`, `generatedAt`, and `generator` are part of the **export envelope**, created by the
exporter — **not** the domain `InspectionReport` (ADR-0009). `generatedAt` is the moment the JSON is
produced, which need not equal the inspection time.

## Versioning rules

- `schemaVersion` is an **integer**, starting at **1**.
- Changes are **additive when possible** — new optional fields (e.g. future `measurements`,
  `findings` for DSP) do **not** bump the version.
- An **incompatible** change (removing/renaming a field, changing a type or the meaning of a value)
  **increments `schemaVersion`**.

## Top-level shape

| Field | Type | Null? | Notes |
| --- | --- | --- | --- |
| `schemaVersion` | integer | no | `1`. Envelope. |
| `generatedAt` | string (ISO-8601, UTC, `Z`) | no | Export time. Envelope. |
| `generator` | object | no | `{ "name": string, "version": string }`. Envelope. |
| `inspectedFile` | object | no | Descriptive file metadata (see below). |
| `technicalProperties` | object | no | Map of property → stateful value (see below). |
| `warnings` | array | no | May be empty. Warning objects (see below). |
| `inspectionStatus` | object | no | Global outcome (see below). |

Future (additive, still v1): `measurements`, `findings` — only once DSP slices land.

## `inspectedFile`

Descriptive metadata of the file **as a file** — never extracted signal properties, and never a
location. There is **no `path` field** and **no `container` field** here (container is a *technical
property*; see below).

| Field | Type | Null? | Notes |
| --- | --- | --- | --- |
| `name` | string | no | Display name incl. extension. |
| `fileExtension` | string | yes | Lowercased, no dot; `null` if none. |
| `sizeBytes` | integer | yes | Unit: `bytes`. `null` (+ a warning) if the attribute can't be read. |
| `modifiedAt` | string (ISO-8601) | yes | File modification date — **file metadata, not forensic evidence**. `null` (+ a warning) if unavailable. |
| `source` | object | no | Safe origin descriptor (see below). |

**Decision — plain nullable metadata, not the state envelope.** `inspectedFile` uses simple
nullable fields, **not** the `available/unavailable/unsupported/uncertain/failed` envelope. That
richer envelope is reserved for **extracted technical properties**, where format limitations and
extraction errors are semantically important. For basic filesystem/selection metadata the only
meaningful distinction is present/absent → `null`, with a `warnings[]` entry (stable `code`) when a
normally-present attribute is missing, and it may downgrade `inspectionStatus` to `partial`.

### `source`

| Field | Type | Null? | Notes |
| --- | --- | --- | --- |
| `kind` | string | no | `"userSelectedLocalFile"`. |
| `displayName` | string | no | Same as `inspectedFile.name`; human-facing. |
| `locationDisclosure` | string | no | `"omitted"` — the location is intentionally not disclosed. |

**Never exported by default:** absolute path, `file://` URL, security-scoped bookmark,
sandbox-internal identifiers, or the parent directory name (ADR-0010).

## `technicalProperties`

Keys are property names; values are **flat stateful-property** objects — the wire form of the
domain's exhaustive sum type (ADR-0008):

```
{ "state": <state>, "value": <typed>|null, "unit": <string>?, "reason": <string>?, "error": {"code","message"}? }
```

- `state` ∈ `"available" | "unavailable" | "unsupported" | "uncertain" | "failed"`.
- `value` is **non-null only** for `available` (required) and `uncertain` (optional); it is `null`
  for `unavailable`, `unsupported`, `failed`.
- `reason` accompanies `unavailable` / `unsupported` (optional) and `uncertain` (**required**).
- `error` (`{ code, message }`, stable `code`) is present **only** for `failed`.
- The four "no value" meanings map exactly: **absent** = `unavailable`; **format can't express it**
  = `unsupported`; **read but untrustworthy** = `uncertain`; **extraction errored** = `failed`.

MVP property keys and units (units are stable tokens: `seconds`, `hertz`, `bitsPerSecond`, `bytes`):

| Key | value type | unit | Notes |
| --- | --- | --- | --- |
| `container` | string | — | Detected container/type, **as a technical property** (may be `unavailable`/`uncertain`/`failed`). |
| `duration` | number | `seconds` | |
| `sampleRate` | integer | `hertz` | |
| `channelCount` | integer | — | Count (unitless). |
| `bitDepth` | integer | `bits` | Usually `unsupported` for lossy codecs. |
| `codec` | string | — | Only `available` when reliably determinable. |
| `declaredBitrate` | integer | `bitsPerSecond` | Container/stream-declared. |
| `estimatedBitrate` | integer | `bitsPerSecond` | **Always `uncertain`**; `reason` states the actual source (the framework's own track-level data-rate estimate, e.g. `AVAssetTrack.estimatedDataRate`) and that it may not exactly represent the stream. Kept **separate** from `declaredBitrate`. |
| `averageFileBitrate` | integer | `bitsPerSecond` | **Always `uncertain`** (never `available`; ADR-0018); calculated as `sizeBytes × 8 ÷ duration` — the file's **whole size**, including any container header, tag or embedded artwork, not the audio payload alone. `reason` states this explicitly. Absent when the file's size or a confirmed duration is not known. Kept **separate** from both `declaredBitrate` and `estimatedBitrate` — three distinct claims about a rate, never merged. |

**Failure vs. inspection outcome.** `technicalProperties` reflects whether property inspection
happened. When `inspectionStatus.state` is `"failed"` (a global failure — the file could not be opened
or read at all), `technicalProperties` **MUST** be the empty object `{}`: no property was inspected.
When the state is `"completed"` or `"partial"`, all nine technical-property keys **MUST** be present,
each with its explicit `state` (an absent datum is `unavailable`/`unsupported`, never omitted). `{}`
therefore means "no inspection occurred", distinct from an inspected property that turned out absent.
Descriptive-metadata warnings (`metadata_*`, see below) may still appear on a global failure **without**
changing the `failed` state.

## Stable codes

`code`s (warnings) and `error.code`s (failed) are **stable, machine-processable** snake_case tokens;
messages are descriptive and are **not** part of the code's identity (they may be reworded or
localized). Initial registry (grows additively):

- Warning codes: `metadata_size_unavailable`, `metadata_modified_at_unavailable`,
  `property_unavailable`, `property_unsupported`, `property_uncertain`, `property_extraction_failed`.
- **Property-failure codes** (a single property's `failed` state → `technicalProperties[..].error.code`):
  `property_read_error`. These come from the domain's `PropertyFailure` and belong only to a property.
- **Inspection-error codes** (a *global* failure → `inspectionStatus.error.code`): `file_open_failed`,
  `file_unreadable`, `file_access_denied`. These come from the domain's `InspectionError` and belong
  only to the whole inspection. The two code spaces are disjoint by design.

## `warnings[]`

| Field | Type | Null? | Notes |
| --- | --- | --- | --- |
| `code` | string | no | Stable token from the registry. |
| `field` | string | yes | The property/metadata key it concerns; `null` if general. |
| `kind` | string | no | The non-`available` state: `unavailable`/`unsupported`/`uncertain`/`failed`. |
| `message` | string | no | Descriptive (not identity). |

## `inspectionStatus`

| Field | Type | Null? | Notes |
| --- | --- | --- | --- |
| `state` | string | no | `"completed"` \| `"partial"` \| `"failed"`. |
| `message` | string | yes | Present for `partial`/`failed`. |
| `error` | object | yes | `{ code, message }` — present **only** when `state = "failed"` (global failure). |

## Realistic example

```json
{
  "schemaVersion": 1,
  "generatedAt": "2026-07-30T16:40:00Z",
  "generator": { "name": "Audio Inspector", "version": "0.1.0" },
  "inspectedFile": {
    "name": "interview-side-a.m4a",
    "fileExtension": "m4a",
    "sizeBytes": 8421376,
    "modifiedAt": "2026-06-12T09:03:00Z",
    "source": {
      "kind": "userSelectedLocalFile",
      "displayName": "interview-side-a.m4a",
      "locationDisclosure": "omitted"
    }
  },
  "technicalProperties": {
    "container":       { "state": "available",   "value": "mpeg-4" },
    "duration":        { "state": "available",   "value": 372.51, "unit": "seconds" },
    "sampleRate":      { "state": "available",   "value": 44100,  "unit": "hertz" },
    "channelCount":    { "state": "available",   "value": 2 },
    "bitDepth":        { "state": "unsupported", "value": null,   "reason": "AAC does not define a PCM bit depth" },
    "codec":           { "state": "available",   "value": "aac" },
    "declaredBitrate": { "state": "available",   "value": 128000, "unit": "bitsPerSecond" },
    "estimatedBitrate":{ "state": "uncertain",   "value": 180904, "unit": "bitsPerSecond",
                         "reason": "Framework estimated data rate; an estimate — not a declared bitrate — that may not exactly represent the stream." },
    "averageFileBitrate": { "state": "uncertain", "value": 133875, "unit": "bitsPerSecond",
                         "reason": "Calculated from the file's total size and duration; includes any container header, metadata and embedded artwork, not only the audio payload — always an approximation of the audio stream's own rate, never a declared or measured one." }
  },
  "warnings": [
    { "code": "property_unsupported", "field": "bitDepth", "kind": "unsupported",
      "message": "Bit depth is not defined for this lossy codec." },
    { "code": "property_uncertain", "field": "estimatedBitrate", "kind": "uncertain",
      "message": "Bitrate was estimated from size and duration, not read from the stream." }
  ],
  "inspectionStatus": { "state": "partial", "message": "Some properties are not exposed by this format." }
}
```

Example of a **global failure**:

```json
{
  "schemaVersion": 1,
  "generatedAt": "2026-07-30T16:41:00Z",
  "generator": { "name": "Audio Inspector", "version": "0.1.0" },
  "inspectedFile": {
    "name": "broken.wav", "fileExtension": "wav", "sizeBytes": 0, "modifiedAt": null,
    "source": { "kind": "userSelectedLocalFile", "displayName": "broken.wav", "locationDisclosure": "omitted" }
  },
  "technicalProperties": {},
  "warnings": [
    { "code": "metadata_modified_at_unavailable", "field": "modifiedAt", "kind": "unavailable",
      "message": "Modification date could not be read." }
  ],
  "inspectionStatus": {
    "state": "failed",
    "message": "The file could not be opened for inspection.",
    "error": { "code": "file_open_failed", "message": "The audio file could not be opened." }
  }
}
```

This document is the canonical `schemaVersion` 1 contract. It supersedes the earlier illustrative
draft (which used `fileIdentity`/`mediaProperties`/`analysisStatus` and a `path` field). DSP-era
fields will be added additively without bumping the version.
