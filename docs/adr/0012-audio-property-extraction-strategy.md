# ADR-0012: Audio property extraction strategy — API priority, reliability tiers, and discrepancy policy

- **Status**: **Proposed** — the strategy shape is agreed, but the concrete APIs, per-property
  availability, and reliability all **depend on the ADR-0003 native-decoding spike** and are not
  asserted as fact. Promote to Accepted once the spike validates them.
- **Date**: 2026-07-31
- **Deciders**: Project maintainer
- **Related**: ADR-0003 (native-first), ADR-0008 (property model), ADR-0011 (infrastructure boundary),
  change add-basic-audio-file-inspection (group 3), docs/analysis-methodology.md

## Context

`AVFoundationAudioFilePropertyReader` (ADR-0011) must decide, per property, *which* Apple API to read
from, *how much* to trust the result, and *what* to do when sources disagree — all **without DSP**
(metadata only) and without inventing values (ADR-0008, honesty principle). Apple exposes overlapping,
sometimes inconsistent facts across layers: the file's UTI (UniformTypeIdentifiers), `AVAsset`/`AVURLAsset`
(duration, tracks), `AVAssetTrack` (`estimatedDataRate`, format descriptions), the
`CMAudioFormatDescription` → `AudioStreamBasicDescription` (ASBD: sample rate, channels, bits-per-channel,
format ID), and AudioToolbox (`AudioFile`/`ExtAudioFile` properties such as `kAudioFilePropertyBitRate`,
`kAudioFilePropertyDataFormat`) as a lower-level fallback. ADR-0003 warns that some of these are
container-declared rather than stream-measured, and that native sufficiency is unproven.

## Decision

### 1. API priority (highest-trust source first, per property)

All sources named below are **candidates, subject to spike validation**; exact API/property names are
*expected*, not contractual, and may change with the SDK (the detailed matrix lives in
`docs/audio-property-matrix.md`). The priority order is:

1. **The selected audio track's stream format description** is the expected primary source for
   `sampleRate`, `channelCount`, `bitDepth`, and `codec`. The **audio track is selected explicitly** by
   the deterministic track-selection policy in the change design — cover art and non-audio tracks are
   ignored (ADR-0003 §5).
2. **The asset's duration** is the expected primary source for `duration`.
3. **The framework-recognized file type** is primary for `container`; the file UTI/extension is only a
   **weak hint**, never proof of the real container.
4. **AudioToolbox file properties** are a **fallback under evaluation** — a *possible* lower-level
   source (e.g. for a nominal bitrate the format description does not carry), **not** a decided
   dependency and **not** a requirement of the adapter's first cut. No AudioToolbox-specific abstraction
   is designed until the spike shows it is needed.
5. **Self-computation from other properties** is the **last resort** and is *never* reported as
   measured: a computed estimate (or a framework value whose own API self-labels as an estimate) always
   feeds `estimatedBitrate` as `uncertain`, never `available`.

The reader consults exactly the sources needed for one property and stops at the first trustworthy
answer; it does not average or blend independent sources into a single fabricated number.

### 2. Reliability tiers

- **Reliable (may be `available`)** — read directly from the decoded audio track's format description
  for a well-formed, supported file: `sampleRate`, `channelCount`, `codec`, `duration`, and `bitDepth`
  **for PCM/lossless formats**. These are stream facts, not guesses.
- **Approximate (must be `uncertain` when present)** — `estimatedBitrate` **always** (per the group-1
  domain contract), and any value that had to be computed or came from an API that self-labels as an
  estimate. A tentative value may be carried, but always with a `reason`.
- **Conditional / not always knowable** — `declaredBitrate` is `available` **only** when the
  container/codec metadata *directly declares* a nominal bitrate (with **no self-computation**). Apple
  does not guarantee such a declared value across the target formats, so it is frequently `unavailable`
  (including for PCM and most lossy files). A PCM bitrate *can* be computed exactly from
  `sampleRate × channels × bitDepth`, but that is a **computation**, so it feeds `estimatedBitrate`
  (always `uncertain`), never `declaredBitrate`. `bitDepth` for lossy codecs is **not a meaningful
  property** → `unsupported`.
- **Impossible to know from metadata alone (out of scope here)** — true (measured) loudness, real
  dynamic range, transcode/source authenticity, actual per-frame integrity. These are **not** read by
  this reader; they are never emitted as basic properties, and their absence is not a `failed`.

### 3. Discrepancy policy

When two sources disagree (e.g. the container/UTI implies one codec but the track's `AudioFormatID`
says another; or the extension disagrees with the actual format):

- **Prefer the stream-measured source over the container-declared / extension-derived one** (the ASBD
  and track format ID outrank the file's UTI/extension).
- **Never silently pick one and present it as fact.** If the disagreement makes the value
  untrustworthy, report the property as **`uncertain`** with a `reason` naming the conflict; do not
  fabricate a reconciled value.
- **Deep container re-parsing to resolve the conflict is out of scope** for this metadata-only slice
  (and belongs to later authenticity work, explicitly a non-goal here). The honest state is
  `uncertain`, not a guess.
- A source being *silent* (absent) is **not** a discrepancy: absence maps to `unavailable`/`unsupported`
  per the property, never to `failed`.

`failed` is reserved for a genuine extraction **error** on that specific property (an API call threw or
returned inconsistent data) while the rest of the inspection continues — distinct from "absent" and
from "untrustworthy".

## Alternatives considered

- **Trust the container/UTI or the file extension as authoritative.** Cheapest, but extensions lie and
  container headers can misdeclare; presenting that as fact violates ADR-0008. Rejected — extension/UTI
  is a low-priority hint, not the primary source.
- **Always compute bitrate from size/duration and report it plainly.** Simple and always available, but
  it is an estimate; reporting it as `available` would invent precision. Rejected — it is always
  `uncertain` (and kept separate from `declaredBitrate`, per group 1).
- **Blend/average disagreeing sources into one number.** Produces a value that matches no real source
  and hides the conflict. Rejected — disagreement surfaces as `uncertain`.

## Consequences

### Positive
- A single, documented rule for every property's source, trust level, and conflict handling; honesty is
  preserved (no invented values); the matrix in the change design makes each decision auditable and
  testable with fakes before real files.

### Negative / costs
- Some properties users might expect (a clean declared bitrate for every lossy file) will legitimately
  come back `unavailable`/`uncertain`; the UI must present that honestly rather than showing a
  confident-looking number.

### Neutral
- The tiers here reuse ADR-0008's `available/unavailable/unsupported/uncertain/failed` vocabulary and
  will extend naturally to later measured metrics (which add the confidence levels from
  `docs/analysis-methodology.md`).

## Follow-ups

The concrete per-property source/state matrix lives in `docs/audio-property-matrix.md`, summarized in
the change's `design.md`.

**Spike 0031** (`docs/spikes/0031-audio-property-api-validation.md`, task 3.1) has now **partially
validated** this strategy for **PCM WAV/AIFF**: the reliable direct sources (ASBD `sampleRate`,
`channelCount`, `bitDepth`, `codec` FourCC), the `container` = `uncertain` stance (the UTI is
extension-driven and provably unreliable), `declaredBitrate` = `unavailable` (no direct source;
`estimatedDataRate` is 0 for PCM and named "estimated"), the always-`uncertain` `estimatedBitrate`, and
the global-vs-property error rule. It also concluded AudioToolbox is **not** needed for this slice.

This ADR **remains Proposed**. Promotion to Accepted requires closing what the spike could not: (a)
lossy/FLAC/ALAC/AAC/M4A behavior (bit depth `unsupported`, codec tokens, any `estimatedDataRate`
usefulness); (b) multi-track ordering and format-description discrepancy handling for N>1; (c) whether
an AudioToolbox fallback is ever justified for the real container or a nominal bitrate. Those are
validated (and this ADR updated) as groups 3.3+ and later slices exercise real/synthetic fixtures for
MP3, WAV, AIFF, FLAC, ALAC, AAC, M4A.
