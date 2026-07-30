# JSON export — schema version 1

The **contract** for Audio Inspector's JSON export. Specification only — the `Codable` DTO that
produces it lives in the export layer (ADR-0009), never in the domain. This document is the
field-level reference the `audio-file-inspection` OpenSpec capability points to. The shape is
deliberately minimal for the first slice (technical properties, no DSP) and grows **additively**.

## Versioning rules

- `schemaVersion` is an **integer**, starting at **1**.
- Changes are **additive when possible** — new optional fields (e.g. future `measurements`,
  `findings` for DSP results) do **not** bump the version.
- An **incompatible** change (removing/renaming a field, changing a type or the meaning of a value)
  **increments `schemaVersion`**.

## Top-level shape

| Field | Type | Null? | Notes |
| --- | --- | --- | --- |
| `schemaVersion` | integer | no | `1` for this contract. |
| `generatedAt` | string (ISO-8601, UTC, `Z`) | no | When the export was produced. |
| `generator` | object | no | `{ "name": string, "version": string }` — the app/generator identity. |
| `inspectedFile` | object | no | File identity (see below). |
| `technicalProperties` | object | no | Map of property → stateful value (see below). |
| `warnings` | array | no | May be empty. Warning objects (see below). |
| `inspectionStatus` | object | no | Global outcome (see below). |

Future (additive, still v1): `measurements` and `findings` appear only once DSP slices land.

## `inspectedFile`

| Field | Type | Null? | Notes |
| --- | --- | --- | --- |
| `name` | string | no | Display name incl. extension. |
| `fileExtension` | string | yes | Lowercased, no dot; `null` if none. |
| `sizeBytes` | integer | no | File size in bytes. |
| `container` | string | yes | Detected container/type; `null` if undetermined. |
| `path` | string | no | **Sandbox-safe** representation (display name / last component). **Never the absolute private path by default.** |
| `modifiedAt` | string (ISO-8601) \| null | yes | File modification date — **file metadata only, not forensic evidence**. |

## `technicalProperties`

An object whose keys are property names and whose values are **stateful property** objects:

```
{ "state": <state>, "value": <typed> | null, "unit": <string> (optional), "note": <string> (optional) }
```

- `state` ∈ `"available" | "unavailable" | "unsupported" | "uncertain" | "failed"` (ADR-0008).
- `value` is present (non-null) **only** for `available` and (optionally) `uncertain`; it is `null`
  for `unavailable`, `unsupported`, and `failed`.
- This is how the four "no value" meanings are distinguished: **absent** = `unavailable`; **format
  cannot express it** = `unsupported`; **read but untrustworthy** = `uncertain`; **extraction
  errored** = `failed`.

MVP property keys, with units:

| Key | value type | unit | Notes |
| --- | --- | --- | --- |
| `duration` | number | `seconds` | |
| `sampleRate` | integer | `hertz` | |
| `channelCount` | integer | `channels` | |
| `bitDepth` | integer | `bits` | `unsupported` for most lossy codecs. |
| `codec` | string | — | Only `available` when reliably determinable. |
| `declaredBitrate` | integer | `bitsPerSecond` | The container/stream-declared bitrate. |
| `estimatedBitrate` | integer | `bitsPerSecond` | Derived from size/duration — **distinct** from declared. |

## `warnings[]`

| Field | Type | Null? | Notes |
| --- | --- | --- | --- |
| `field` | string | yes | The property key it concerns; `null` if general. |
| `kind` | string | no | One of the non-`available` states: `unavailable`/`unsupported`/`uncertain`/`failed`. |
| `message` | string | no | Plain-language explanation. |

## `inspectionStatus`

| Field | Type | Null? | Notes |
| --- | --- | --- | --- |
| `state` | string | no | `"completed"` \| `"partial"` \| `"failed"`. |
| `message` | string | yes | Present especially for `failed`. |

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
    "container": "mpeg-4",
    "path": "interview-side-a.m4a",
    "modifiedAt": "2026-06-12T09:03:00Z"
  },
  "technicalProperties": {
    "duration":        { "state": "available",   "value": 372.51, "unit": "seconds" },
    "sampleRate":      { "state": "available",   "value": 44100,  "unit": "hertz" },
    "channelCount":    { "state": "available",   "value": 2,      "unit": "channels" },
    "bitDepth":        { "state": "unsupported", "value": null,   "note": "AAC does not expose a PCM bit depth" },
    "codec":           { "state": "available",   "value": "aac" },
    "declaredBitrate": { "state": "available",   "value": 128000, "unit": "bitsPerSecond" },
    "estimatedBitrate":{ "state": "uncertain",   "value": 180904, "unit": "bitsPerSecond", "note": "derived from size/duration; includes container overhead" }
  },
  "warnings": [
    { "field": "bitDepth", "kind": "unsupported", "message": "Bit depth is not defined for this lossy codec." },
    { "field": "estimatedBitrate", "kind": "uncertain", "message": "Estimated from file size and duration, not read from the stream." }
  ],
  "inspectionStatus": { "state": "partial", "message": "Some properties are not exposed by this format." }
}
```

This document supersedes the earlier illustrative draft: it fixes the concrete `schemaVersion` 1
field names for the first export. DSP-era fields will be added additively without bumping the
version.
