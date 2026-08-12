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
| `measurements` | object | **key omitted, not `null`, when absent** | DSP-derived measurements (see below). Additive; present only when at least one measurement exists. |

Future (additive, still v1): `findings` — only once a capability needs it.

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

## `measurements` (additive — DSP-derived, never metadata)

`measurements` never joins `technicalProperties`: everything under it required decoding sample data,
which `technicalProperties`'s own boundary excludes by design (ADR-0018). The key is **omitted
entirely** when there is nothing to report — not present as `null` — so a report exported without any
measurement is byte-identical to one exported before this object existed. Its absence carries no
warning and never changes `inspectionStatus`; a measurement is orthogonal to whether the file's
metadata could be read.

It currently holds two **siblings** — `signalLevels` and `truePeak` — and **each is independently
omitted** when its own measurement does not exist. All four combinations are therefore representable
and none is faked: either alone, both, or neither (in which case `measurements` itself is absent).
There is deliberately **no aggregate** over them: nothing says "the measurements succeeded", because
each answers only for itself. A new measurement adds a sibling key, which is additive and needs no
version bump.

### `measurements.signalLevels`

Peak, RMS, DC offset and clipped-sample count, overall and per channel — the wire form of the domain's
`SignalLevelMetrics`. Present only when `SignalLevelMetrics` was actually produced (not `loading`,
`unavailable`, `failed`, or a cancelled operation — those all collapse to `measurements` being absent
before export is ever reached).

**Values are the domain's own linear amplitude, never dBFS.** A decibel conversion is a presentation
concern, applied only inside the app's UI layer; the wire contract exports what was measured, in the
unit it was measured in — the same principle `technicalProperties` already follows for `sampleRate`
(Hz, not a rendered `"44.1 kHz"` string).

| Field | Type | Null? | Notes |
| --- | --- | --- | --- |
| `overall.peakSample` | number | yes | Linear amplitude. `null` iff every channel has `sampleCount == 0` ("not computable", never a fabricated `0`). Can exceed `1.0` — a genuinely out-of-range sample is kept exactly as measured, never clamped. |
| `overall.rms` | number | yes | Linear amplitude. Same null rule as `peakSample`. |
| `overall.dcOffset` | number | yes | Linear, signed. Same null rule as `peakSample`. |
| `overall.clippedSampleCount` | integer | no | Always defined, even when every channel is empty (`0`, not `null`) — counting is defined over zero samples. |
| `channels` | array | no | One entry per channel, in the stream's own order. May be empty only if the stream itself reports no channels (never observed in practice). |
| `channels[].sampleCount` | integer | no | `0` iff this channel's other three fields are `null`. |
| `channels[].peakSample` / `.rms` / `.dcOffset` | number | yes | Same shape and null rule as the `overall` fields, per channel. |
| `channels[].clippedSampleCount` | integer | no | Always defined. |

No clipping threshold is exported: it is a named constant of the analysis engine
(`SignalLevelMetricsAccumulator.clippingThreshold`), not a fact this measurement itself carries, and
this contract has no engine-version field yet for such a constant to be meaningfully anchored to.

Example, added to the realistic export below when signal level metrics are available:

```json
"measurements": {
  "signalLevels": {
    "overall": { "peakSample": 0.708, "rms": 0.22, "dcOffset": -0.0003, "clippedSampleCount": 12 },
    "channels": [
      { "sampleCount": 13230000, "peakSample": 0.708, "rms": 0.25, "dcOffset": 0.0006, "clippedSampleCount": 0 },
      { "sampleCount": 13230000, "peakSample": 0.501, "rms": 0.18, "dcOffset": -0.0011, "clippedSampleCount": 12 }
    ]
  }
}
```

Pinned by `JSONReportExportMeasurementsTests` (overall/per-channel/multichannel shape, the
not-computable-vs-zero distinction, values beyond full scale, determinism, and that the key is fully
absent — not `null` — when there is nothing to report).

### `measurements.truePeak`

The maximum of the waveform **reconstructed between** the stored samples — the wire form of the
domain's `TruePeakMeasurement`. Present only when a measurement was actually produced (`loading`,
`unavailable`, `failed` and a cancelled operation all collapse to the key being absent before export is
reached: this document describes measurements, never lifecycle).

**It is a different measurement from `signalLevels.peakSample`, not a refinement of it.** That value is
the largest **stored** sample, exact and directly reduced; this one is an estimate produced by an
interpolation filter, and it is normally larger. Neither is derived from the other, and neither implies
anything about `clippedSampleCount`: a file can have zero clipped samples and a true peak above `1.0`,
which is the inter-sample case this measurement exists to reveal.

**Values are the domain's own linear amplitude, never dBTP.** The decibel form (`20 · log10(value)`,
shown as `dBTP`) is a presentation concern applied only in the app's UI layer — the same rule
`signalLevels` follows for dBFS. No unit string travels with the numbers; this contract states the unit.

| Field | Type | Null? | Notes |
| --- | --- | --- | --- |
| `overall` | number | yes | Linear amplitude, **not** an object — there is one number here. `null` iff every channel has `sampleCount == 0` ("not computable", never a fabricated `0`). Can exceed `1.0` and is never clamped: a reconstruction above full scale is the fact this measurement exists to report. |
| `channels` | array | no | One entry per channel, in the stream's own order. Channels are identified by position only — no name, no layout. |
| `channels[].sampleCount` | integer | no | Frames this channel's measurement covered. `0` **iff** `truePeak` is `null`, in both directions. |
| `channels[].truePeak` | number | yes | Linear amplitude, same rules as `overall`. A genuinely silent channel that *was* measured reports a real `0`; a channel that carried no samples reports `null`. |
| `method.oversamplingFactor` | integer | no | Points per input sample the reconstruction was evaluated at (`8` for the current methodology). |
| `method.filter` | string | no | Stable identifier of the reconstruction filter (`"polyphase_fir_v1"`). |

`method` sits **inside** `truePeak` rather than at `measurements` level: it describes this measurement,
and hoisting it would imply it covers `signalLevels`, which has no such methodology. Its two fields
come from the measurement's own record, so a document always describes the methodology that actually
ran.

**The filter is an identity, not a recipe.** The tap count, window, cutoff and coefficients are
deliberately absent: a consumer is told *which* methodology produced the number, not how to re-run one.
**No conformance to a standard is claimed** — this filter was designed to recorded parameters and
validated against analytic ground truth and an independent R128 implementation, not built from
ITU-R BS.1770 Annex 2's own coefficients (ADR-0019 §6) — so no `bs1770`, `ebu`, `r128` or `compliant`
token appears anywhere in the document.

Example, beside `signalLevels` when both are available:

```json
"measurements": {
  "truePeak": {
    "overall": 1.087,
    "channels": [
      { "sampleCount": 13230000, "truePeak": 1.087 },
      { "sampleCount": 13230000, "truePeak": 0.932 }
    ],
    "method": { "oversamplingFactor": 8, "filter": "polyphase_fir_v1" }
  }
}
```

Pinned by `JSONReportExportTruePeakTests` (linear unit with no dBTP anywhere, the zero-vs-null
distinction, values beyond full scale, channel order, exact key sets, the method following the
measurement rather than a constant, coexistence with `signalLevels` as siblings, byte-identity when
absent, determinism, and `schemaVersion` staying `1`) and by
`EndToEndFlowTests.theRealTruePeakPathReachesTheExportedDocument`, which drives a real file through the
real decode and asserts the exported number is the measured one.

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
draft (which used `fileIdentity`/`mediaProperties`/`analysisStatus` and a `path` field). `measurements`
is the first DSP-era field, added additively without bumping the version, per the rule stated above;
any future measurement (e.g. true peak) is a sibling key under `measurements`, added the same way.
