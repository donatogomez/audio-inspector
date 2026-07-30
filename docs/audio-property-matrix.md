# Audio property extraction matrix — pre-spike hypothesis

**Status: pre-spike hypothesis.** Nothing here is a contractual guarantee. The concrete APIs, their
availability, and their reliability are **candidate sources subject to validation by the ADR-0003
native-decoding spike** (against real and synthetic fixtures for MP3, WAV, AIFF, FLAC, ALAC, AAC,
M4A). API and property names are illustrative of the *expected* source and may change with the SDK;
where a source is not yet decided it is marked *under evaluation*.

- Decisions (why AVFoundation sits behind the port; how errors are translated): **ADR-0011**.
- Strategy (API priority, reliability tiers, discrepancy policy): **ADR-0012** (Proposed).
- Change contract: `openspec/changes/add-basic-audio-file-inspection/design.md` §"Infrastructure reader".

The domain never sees any of these APIs; the adapter in `AudioInspectorMedia` maps them to
`Property<Value>` (ADR-0008: `available` / `unavailable` / `unsupported` / `uncertain` / `failed`).

## Candidate sources & expected reliability

| Property | Candidate source (subject to spike validation) | Expected reliability | Key limitations / open questions |
| --- | --- | --- | --- |
| `container` | Framework-recognized file type when the asset opens; UTI/extension only as a weak hint | Medium | UTI/extension **infer** a type, they do not prove the real container; deep byte inspection is out of scope. |
| `duration` | Asset duration reported by the framework (a `CMTime`) | Variable | May be indefinite, unloadable, or an estimate (e.g. VBR without a seek table); **no guaranteed public signal** to tell exact from estimated. |
| `sampleRate` | Selected audio track's stream format description | High (expected) | Needs a decodable audio track and a valid, non-empty format description. |
| `channelCount` | Selected audio track's stream format description / channel layout | High (expected) | Exotic/ambiguous layouts may need the layout, not a bare count. |
| `bitDepth` | Selected audio track's stream format description, for PCM/lossless | High for PCM/lossless (expected) | **Not meaningful for lossy codecs**; bits-per-channel is not interchangeable with bits-per-sample or packet/frame size — never inferred by formula. |
| `codec` | Selected audio track's technical format identifier (e.g. an `AudioFormatID`/FourCC) | High (expected) | Emit a **stable, non-localized** token; FourCC/numeric serialization format is pending the spike; never use a localized system description as identity. |
| `declaredBitrate` | A nominal bitrate **directly declared** by container/codec metadata, if the framework exposes one; **no self-computation** | **Not guaranteed** | Apple does not expose a declared nominal bitrate across all target formats; a lower-level fallback (AudioToolbox) is **under evaluation**, not decided. |
| `estimatedBitrate` | A framework value whose own API is labelled an estimate, **or** a self-computed estimate; source named in the `reason` | Estimate only | **Always `uncertain`** (group-1 contract). Candidate formula (non-contractual, spike-pending): `fileSize × 8 / duration` — see notes below. |

## Expected `Property` state per field (which case, and when)

| Property | `available` when | `unavailable` when | `unsupported` when | `uncertain` when | `failed` when |
| --- | --- | --- | --- | --- | --- |
| `container` | the framework directly recognizes the file's type on open | no type information at all | a recognized format with no applicable container concept (only if semantically correct) | type known only by UTI/extension inference, or signals disagree | reading the type errors |
| `duration` | a valid, finite duration is reported and no estimate signal is present | the asset exposes no duration | — | duration is indefinite, or known/suspected to be an estimate, and cannot be confirmed exact | the duration load errors |
| `sampleRate` | a valid rate from a valid format description | no audio track present | — | value implausible or format descriptions disagree | reading the format description errors |
| `channelCount` | a definite count from format description/layout | no audio track present | — | layout ambiguous or descriptions disagree | reading the format description errors |
| `bitDepth` | PCM/lossless with a valid, semantically-applicable value | lossless expected but the field is absent | **lossy codec** (bit depth does not apply) | a value exists but its meaning is ambiguous | reading a source that should carry it errors |
| `codec` | the technical format identifier maps to a known codec | no audio track present | — | container/UTI vs track format identifier disagree | reading the format description errors |
| `declaredBitrate` | a nominal bitrate is **directly declared** by metadata | no declared bitrate is exposed (common; includes PCM and most lossy) | — | a declared value looks internally inconsistent | reading a bitrate metadata source that should exist errors |
| `estimatedBitrate` | *never* (always uncertain) | *n/a* | — | **always** — it is an estimate, with the method in `reason` | the estimation inputs (e.g. size or duration) are unreadable |

## Notes on the candidate bitrate estimate (spike-pending, non-contractual)

- **Formula (candidate):** `estimatedBitrate ≈ fileSize × 8 / duration`, or a framework value that
  self-labels as an estimate. Not fixed as a contract until the spike validates it.
- **Prerequisites:** a readable file size **and** a usable duration. If either is missing — or the
  duration is itself `uncertain`/indefinite — the estimate is **not** computed (→ `unavailable`, not a
  guessed number).
- **Container/header overhead:** the size includes container/header/metadata bytes, not just audio
  payload, so the result is inherently approximate — this is **why it is always `uncertain`**.
- **Never** feeds `declaredBitrate`: a self-computed value is by definition not "declared".
