# ADR-0011: AVFoundation lives behind the domain port — the infrastructure boundary for property reading

- **Status**: Accepted
- **Date**: 2026-07-31
- **Deciders**: Project maintainer
- **Related**: ADR-0001, ADR-0003, ADR-0005, ADR-0008, ADR-0009, docs/architecture.md, change add-basic-audio-file-inspection (group 3)

## Context

Group 3 of `add-basic-audio-file-inspection` implements the **real** reader of basic technical
properties: `AVFoundationAudioFilePropertyReader`, the first concrete implementation of the domain
port `AudioFilePropertyReading` (introduced in group 1). It reads metadata-level facts (container,
duration, sample rate, channel count, bit depth, codec, declared/estimated bitrate) using Apple's
media stack — **no DSP** (ADR-0003, native-first).

The architecture (ADR-0001/0005, `Scripts/check-boundaries.sh`) already forbids
`AudioInspectorDomain` from importing AVFoundation/AudioToolbox: only `AudioInspectorMedia` may. What
this ADR fixes is not *where the import is allowed* (the build graph already enforces that) but the
**semantic contract of the seam**: what the adapter is allowed to let cross into the domain, and in
which direction knowledge flows. Apple's media types (`AVAsset`, `AVAssetTrack`,
`CMFormatDescription`, `AudioStreamBasicDescription`, `NSError`/`AVError`) are framework-shaped,
`Objective-C`-bridged, and not `Sendable`-clean; letting any of them — or Apple's error values —
leak inward would couple the pure core to a specific platform and undo ADR-0008's honesty model.

## Decision

The port stays in the domain; **all** AVFoundation/AudioToolbox knowledge stays in infrastructure;
the adapter is the *only* translation point. Concretely:

1. **The port belongs to the domain.** `AudioFilePropertyReading` is a domain-owned protocol
   expressed purely in domain value types
   (`AudioFileReference` in, `TechnicalProperties` out, typed `throws(InspectionError)`). The domain
   defines *what* it needs read, never *how*. The use case (`InspectAudioFileUseCase`) depends only on
   this port — it is unchanged by group 3 and cannot tell a fake from the real AVFoundation reader.

2. **AVFoundation lives outside the domain.** `AVFoundationAudioFilePropertyReader` is defined in
   `AudioInspectorMedia`, the single target permitted to import AVFoundation/AudioToolbox. The domain
   target does not link, import, or reference any Apple media type.

3. **Mapping happens only in infrastructure.** Translating Apple's shapes
   (`AudioStreamBasicDescription.mSampleRate`, `mChannelsPerFrame`, `mBitsPerChannel`, the
   `AudioFormatID`, `AVAssetTrack.estimatedDataRate`, the asset's `duration`, the file's UTI, …) into
   the domain's `Property<Value>` cases is done **inside the adapter**. Nothing above the port (use
   case, features, export) performs any AVFoundation-shaped reasoning.

4. **`Property<Value>` never knows AVFoundation.** The sum type (ADR-0008) is generic over plain
   value types (`Int`, `Double`, `String`). The choice of case — `available` / `unavailable` /
   `unsupported` / `uncertain` / `failed` — is the adapter's judgement, but the *type* carries no
   platform vocabulary. This is what lets the same report be produced by a fake, by AVFoundation, or
   (hypothetically, per ADR-0003) by an FFmpeg adapter, without changing the domain.

5. **Apple's errors never cross the port.** AVFoundation/AudioToolbox raise `NSError`/`AVError`/OSStatus
   values. The adapter **catches every one of them** and converts them into the domain's own typed
   errors: a whole-file failure (cannot open / unreadable / access denied) becomes a thrown
   **global** `InspectionError` (stable `code`); a single-property extraction error becomes a
   **property-level** `Property.failed(PropertyFailure)`. No `NSError`, `AVError`, `OSStatus`, or Apple
   error domain/user-info string is ever exposed through `AudioFilePropertyReading`. Messages are
   descriptive only; identity is the stable domain `code` (ADR-0008).

The direction of knowledge is strictly inward-agnostic: **domain → port ← infrastructure**. The
domain points down to a protocol; infrastructure implements up to it; nothing platform-specific flows
back up.

## Alternatives considered

- **Return Apple types (or a thin wrapper) from the port and map in the use case.** Would pull
  AVFoundation vocabulary into the domain, break ADR-0001/0005 boundaries, and make `Property` and the
  use case platform-aware. Rejected — it defeats the entire testable-core design.
- **Let AVFoundation `NSError` propagate as the port's error type.** Simplest to write, but couples
  the domain's error space to Apple's, loses the property-vs-global error distinction (ADR-0008), and
  makes stable machine-processable codes impossible. Rejected.
- **Put the mapping in a shared "mapping" module imported by both domain and Media.** Adds a
  ceremonial module for one seam and risks the domain transitively seeing Apple types. Rejected — the
  adapter *is* the mapping; no extra module earns its place (ADR-0005, seam-driven targets).

## Consequences

### Positive
- The pure core stays framework-free and fully testable with fakes; the AVFoundation reader is swappable
  (fake / native / future FFmpeg) with zero domain change; honest error semantics are preserved end to
  end; `check-boundaries.sh` keeps the seam enforced mechanically.

### Negative / costs
- The adapter must exhaustively catch and translate Apple errors and states — more mapping code and
  careful per-property judgement (documented in the change's property matrix), rather than passing
  Apple values through.

### Neutral
- Establishes the pattern for every future infrastructure port (decoding, loudness, spectral): the
  protocol is domain-owned, the platform code and its error/type translation live only in
  `AudioInspectorMedia`.

## Follow-ups

Implemented in group 3 of `add-basic-audio-file-inspection`. The concrete per-property API choices and
their reliability live in ADR-0012 (extraction strategy) and the change's property matrix; native
sufficiency remains a hypothesis pending the ADR-0003 spike.
