# Audio property extraction matrix

**Status: partially validated by spike 0031** (PCM WAV/AIFF only; see
`docs/spikes/0031-audio-property-api-validation.md`). The two tables below are the **pre-spike
hypotheses**, kept verbatim for history; the **Post-spike findings** section records what was actually
observed and the decision now proposed. Lossy/FLAC/ALAC/AAC/M4A remain **unvalidated** (candidate,
subject to the wider spike / real files). API and property names may change with the SDK.

- Decisions (why AVFoundation sits behind the port; how errors are translated): **ADR-0011**.
- Strategy (API priority, reliability tiers, discrepancy policy): **ADR-0012** (Proposed).
- Change contract: `openspec/changes/add-basic-audio-file-inspection/design.md` §"Infrastructure reader".
- Evidence: **spike 0031** (`docs/spikes/0031-audio-property-api-validation.md`).

The domain never sees any of these APIs; the adapter in `AudioInspectorMedia` maps them to
`Property<Value>` (ADR-0008: `available` / `unavailable` / `unsupported` / `uncertain` / `failed`).

> _The next two tables are the **pre-spike hypotheses**, preserved unchanged for history. The
> post-spike decisions are in the "Post-spike findings" section at the bottom._

## Candidate sources & expected reliability (pre-spike hypothesis)

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

## Post-spike findings (spike 0031 — PCM WAV/AIFF)

What was actually observed on macOS 26.3 / Xcode 26.6 / Swift 6.3.3 against runtime-generated PCM
fixtures. Lossy/FLAC/ALAC/AAC/M4A remain **unvalidated** (candidate). Full evidence:
`docs/spikes/0031-audio-property-api-validation.md`.

| Property | Validated source (PCM) | Discarded / negative finding | Confidence after spike | Recommended state | Open questions |
| --- | --- | --- | --- | --- | --- |
| `container` | — (none reliable) | `URLResourceValues.contentType` (UTI) is extension-driven and **lied** (WAV→`.aiff` reported `public.aiff-audio`); AVFoundation exposes **no real container** signal | High that UTI is unreliable | **`uncertain`** from UTI/extension; `unavailable` if none — **never `available`** via AVFoundation alone | Does AudioToolbox `kAudioFilePropertyFileFormat` give the real container? (fallback, unexercised) |
| `duration` | `AVAsset.load(.duration)` → `CMTime` seconds | `CMTime` valid/numeric flags do **not** prove correctness: truncated file → valid, numeric, finite `0.0` | Medium | `available` if finite numeric; `uncertain` if indefinite/degraded; **no exact-vs-estimated promise** | Behavior for VBR/lossy without seek tables (untested) |
| `sampleRate` | ASBD `mSampleRate` | — | High (PCM) | `available`; `unavailable` if no track | Multi-track / disagreement (untested for N>1) |
| `channelCount` | ASBD `mChannelsPerFrame` | — | High (PCM) | `available`; `unavailable` if no track | Exotic channel layouts (untested) |
| `bitDepth` | ASBD `mBitsPerChannel` (=16 observed) | **Not** `mBytesPerFrame`/`mBytesPerPacket` (2/4, channel-dependent) | High (PCM) | `available` when `lpcm` & `mBitsPerChannel>0`; **`unsupported`** for lossy | Confirm lossy → `mBitsPerChannel==0` (untested) |
| `codec` | `mFormatID` / media subtype FourCC (`'lpcm'`) | localized descriptions (not used) | High | `available` as stable token: ASCII FourCC if printable, else `0x%08X` | Non-printable IDs (untested); normalization out of scope |
| `declaredBitrate` | — (none) | `AVAssetTrack.estimatedDataRate` = **0.0 for PCM** and is named "estimated" anyway | High that no direct source exists (PCM) | **`unavailable`** | AudioToolbox `kAudioFilePropertyBitRate` for lossy? (fallback, unexercised) |
| `estimatedBitrate` | `fileSize×8/duration` (418336 vs stream 352800 — overhead) | using it as `declaredBitrate` | High that it is approximate | **always `uncertain`**; input from `estimatedDataRate` (if >0) or the file-based formula | `estimatedDataRate` usefulness for lossy (untested) |

**Errors (semantic classes observed):** asset/`loadTracks` throw → **global** `InspectionError`
(missing / empty / text-as-audio); a truncated file loaded with **partial** results (structural fields
OK, duration degraded to `0.0`, no throw). A pure property-level `failed` was **not** forced (rare;
open for 3.6). Absence of a datum (`estimatedDataRate==0`) is **not** an error.

**AudioToolbox decision:** **not** adopted for group 3 — AVFoundation + CoreMedia cover every field the
basic PCM slice needs. Kept as an unexercised, documented fallback for the *real container* and a
*nominal bitrate* only, to be validated in isolation if a later slice needs them.
