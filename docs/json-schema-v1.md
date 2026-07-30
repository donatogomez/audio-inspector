# JSON export — schema version 1

The **contract** for Audio Inspector's JSON export. This is a specification only — no `Codable` or
Swift code is implemented yet. The goal is a **minimal, extensible** shape, not a model of every
future metric. The OpenSpec requirement lives in the `analysis-reporting` capability; this document
is the field-level reference it points to.

## Versioning rules

- `schemaVersion` is an **integer**, starting at **1**.
- Changes are **additive when possible** (new optional fields do **not** bump the version).
- An **incompatible** change (removing/renaming a field, changing a type or the meaning of a value)
  **increments `schemaVersion`**.
- `analysisEngineVersion` is separate: it tracks the *analysis methodology/thresholds*, so results
  can change while the schema stays at 1.

## Top-level shape

| Field | Type | Notes |
| --- | --- | --- |
| `schemaVersion` | integer | `1` for this contract. |
| `analysisEngineVersion` | string | Version of the analysis engine/methodology that produced the result. |
| `generatedAt` | string (ISO-8601) | When the export was produced. |
| `fileIdentity` | object | Identity of the analyzed file (see below). |
| `mediaProperties` | object | Container/codec/technical facts (see below). |
| `measurements` | object | Computed metrics (open map; MVP fills a subset). |
| `findings` | array of finding | Observations/warnings (see below); may be empty. |
| `analysisStatus` | object | Completion/status of the analysis (see below). |

## `fileIdentity`

| Field | Type | Notes |
| --- | --- | --- |
| `fileName` | string | Display name only — never a full personal path in shared exports. |
| `sizeBytes` | integer | |
| `modifiedAt` | string (ISO-8601) | |
| `fileHash` | object | `{ "algorithm": string, "value": string }` — cryptographic hash of file bytes. |
| `audioHash` | object \| null | Optional hash of decoded PCM, when available. |

## `mediaProperties`

Measured facts, each a plain value (with units where relevant): `container`, `codec`,
`durationSeconds`, `declaredBitrateKbps`, `estimatedAvgBitrateKbps`, `bitrateMode` (`"cbr"` |
`"vbr"`), `sampleRateHz`, `declaredBitDepth`, `effectiveBitDepth` (nullable estimate), `channels`,
`channelLayout`, `hasCoverArt` (boolean). Unknown/inapplicable fields are `null`.

## `measurements`

An open object of metric → value, so new metrics are additive. MVP keys (each a number with an
implied unit documented in [analysis-methodology.md](analysis-methodology.md)): `samplePeakDbfs`,
`truePeakDbfs`, `rmsDbfs`, `integratedLufs`, `dcOffset`, `clippingDetected` (boolean),
`intersampleClippingSuspected` (boolean), `significantMaxFrequencyHz`. Absent metrics are omitted or
`null`; adding a metric later does not bump `schemaVersion`.

## `findings[]`

Each finding is an object:

| Field | Type | Notes |
| --- | --- | --- |
| `identifier` | string | **Stable** slug (e.g. `"possible-transcoding"`) so findings can be tracked across versions. |
| `severity` | string | e.g. `"info"` \| `"notice"` \| `"warning"`. |
| `confidence` | string | One of `none` \| `weak` \| `medium` \| `strong` \| `inconclusive`. |
| `evidence` | array | Measured facts backing the finding (e.g. `[{ "label": "spectral cutoff", "value": "16.1 kHz", "detail": "persists 92% of file" }]`). |
| `explanation` | string | Plain-language why-it-matters. |
| `alternativeExplanations` | array of string | Other plausible causes; may be empty. |

This mirrors the evidence/inference/conclusion + confidence model in
[analysis-methodology.md](analysis-methodology.md). **No aggregate 0–100 score field exists.**

## `analysisStatus`

| Field | Type | Notes |
| --- | --- | --- |
| `state` | string | e.g. `"completed"` \| `"partial"` \| `"failed"` \| `"cancelled"`. |
| `warnings` | array of string | Non-fatal issues during analysis (e.g. a metric skipped). |
| `notes` | string \| null | Optional free-text (e.g. what could not be determined). |

## Illustrative example (non-normative)

```json
{
  "schemaVersion": 1,
  "analysisEngineVersion": "0.1.0",
  "generatedAt": "2026-07-30T18:20:00Z",
  "fileIdentity": {
    "fileName": "track.flac",
    "sizeBytes": 31457280,
    "modifiedAt": "2026-07-01T10:00:00Z",
    "fileHash": { "algorithm": "sha256", "value": "…" },
    "audioHash": { "algorithm": "sha256", "value": "…" }
  },
  "mediaProperties": {
    "container": "FLAC", "codec": "flac", "durationSeconds": 253.4,
    "declaredBitrateKbps": null, "estimatedAvgBitrateKbps": 992, "bitrateMode": "vbr",
    "sampleRateHz": 96000, "declaredBitDepth": 24, "effectiveBitDepth": 16,
    "channels": 2, "channelLayout": "stereo", "hasCoverArt": true
  },
  "measurements": {
    "samplePeakDbfs": -1.2, "truePeakDbfs": -0.8, "rmsDbfs": -14.6,
    "integratedLufs": -12.9, "dcOffset": 0.0001,
    "clippingDetected": false, "intersampleClippingSuspected": false,
    "significantMaxFrequencyHz": 21000
  },
  "findings": [
    {
      "identifier": "inflated-sample-rate",
      "severity": "warning",
      "confidence": "medium",
      "evidence": [
        { "label": "significant max frequency", "value": "≈21 kHz", "detail": "no useful energy above" },
        { "label": "effective bit depth", "value": "16", "detail": "lower 8 bits look like padding" }
      ],
      "explanation": "Stored as 24/96 but the signal looks like a 16/44.1 source; no real quality gain.",
      "alternativeExplanations": ["A deliberately band-limited master could look similar."]
    }
  ],
  "analysisStatus": { "state": "completed", "warnings": [], "notes": null }
}
```
