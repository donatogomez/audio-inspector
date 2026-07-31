# Spike 0031 — Native audio property API validation (OpenSpec task 3.1)

- **Date**: 2026-07-31
- **Branch**: `spike/audio-property-api-validation`
- **Task**: 3.1 of change `add-basic-audio-file-inspection`
- **Related**: ADR-0003, ADR-0011, ADR-0012, `docs/audio-property-matrix.md`

## Objective

Determine, with compilable and runnable evidence, what **public** information Apple's native APIs
expose for local audio files — to de-risk the future `AVFoundationAudioFilePropertyReader` (groups
3.2–3.7) before writing production code. This is a throwaway exploratory spike, **not** the adapter.

## Environment

| Item | Value |
| --- | --- |
| macOS | 26.3 (build 25D125) |
| Xcode | 26.6 (17F113) |
| Swift | 6.3.3 (swiftlang-6.3.3.1.3) |
| SDK | MacOSX 26.5 |
| Host arch | arm64 (`arm64-apple-macosx26.0`) |
| Spike deployment target | **macOS 15** (matches the productive package; not lowered) |
| Language mode | Swift 6, built with `-Xswiftc -warnings-as-errors` |

> **SDK-dependence caveat**: all observations below are from **one** SDK/OS. Numeric error codes and
> some behaviors are SDK-dependent; the *semantic* conclusions are what carry forward, not the codes.

## APIs exercised (public only)

- `AVURLAsset`, `AVURLAsset.load(.duration)`, `AVURLAsset.loadTracks(withMediaType: .audio)`
- `AVAssetTrack.load(.formatDescriptions)`, `AVAssetTrack.load(.estimatedDataRate)`, `.trackID`
- CoreMedia: `CMAudioFormatDescriptionGetStreamBasicDescription`, `CMFormatDescriptionGetMediaSubType`,
  `AudioStreamBasicDescription`, `CMTime`
- `AVAudioFile(forWriting:settings:)` + `AVAudioPCMBuffer` (fixture generation)
- `URLResourceValues.contentType` (UTI), `.fileSize`
- **AudioToolbox was deliberately NOT used** (see Experiment I).
- No FFmpeg/ffprobe/third-party/private APIs/byte-parsing/new SPM deps.

## Fixtures (generated at runtime, not committed)

Both are generated in a temp dir with public `AVAudioFile` APIs and deleted on exit; no audio binaries
enter the repo.

| Fixture | Container | Channels | Sample rate | Bit depth | Duration | File size (observed) |
| --- | --- | --- | --- | --- | --- | --- |
| A | WAV/PCM | mono (1) | 22050 Hz | 16-bit | 0.5 s | 26146 B |
| B | AIFF/PCM | stereo (2) | 44100 Hz | 16-bit | 0.25 s | 48196 B |

Derived edge cases (also runtime-generated, then deleted): WAV bytes renamed `.aiff` and `.bin`; a
missing path; an empty `.wav`; a text file named `.wav`; the first 200 bytes of Fixture A.

## Commands

```bash
cd Spike/AudioPropertySpike
swift build -Xswiftc -warnings-as-errors
swift run  -Xswiftc -warnings-as-errors AudioPropertySpike            # full A–I suite (self-generated fixtures)
swift run  -Xswiftc -warnings-as-errors AudioPropertySpike file.wav … # diagnostic mode for given paths
```

## Results per experiment

Legend for **Confidence**: *observed* (measured here) · *inferred* (reasoned from observations) ·
*not tested* (couldn't be forced with these fixtures) · *format-dependent* · *SDK-dependent*.

### A — Track selection

| Hypothesis | Observation | Conclusion | Confidence |
| --- | --- | --- | --- |
| Audio tracks come from `loadTracks(withMediaType:.audio)` | Both fixtures → **1** audio track, `trackID=1`, 1 format description | The API is the right source; single-track PCM is trivial | observed |
| Multiple/alternate tracks change ordering | Could not be produced with single-stream PCM | Ordering rule unverified for N>1 | not tested |

**Proposed 3.2 policy:** select the **first** element of `loadTracks(withMediaType:.audio)`; 0 tracks →
stream fields `unavailable` (not a global failure); ≥1 → use `[0]`; multi-track handling deferred.

### B — Sample rate & channel count

| Hypothesis | Observation | Conclusion | Confidence |
| --- | --- | --- | --- |
| Both come from the track's ASBD | A: `mSampleRate=22050`, `mChannelsPerFrame=1`; B: `44100`, `2` — exact matches | ASBD is the reliable direct source | observed |

**Source:** ASBD `mSampleRate` / `mChannelsPerFrame`. **Confidence:** high for PCM. Absence (no track)
→ `unavailable`; disagreement across format descriptions → `uncertain` (not forced here).

### C — Codec token

| Hypothesis | Observation | Conclusion | Confidence |
| --- | --- | --- | --- |
| `mFormatID`/media subtype yields a stable token | Both: `mFormatID = 'lpcm'` (0x6c70636d); media subtype == format ID | FourCC → ASCII token works | observed |
| Non-printable IDs need a fallback | Not encountered with PCM | Hex fallback implemented, not exercised | not tested |

**Proposed token format:** ASCII `'abcd'` when all four FourCC bytes are printable (0x20–0x7E); else a
fixed-width `0x%08X` hex fallback. **Pros:** stable, non-localized, deterministic. **Cons:** raw
FourCC, not a friendly name; full normalization (e.g. `'lpcm'`→`pcm`) is out of scope for this slice.

### D — Bit depth

| Hypothesis | Observation | Conclusion | Confidence |
| --- | --- | --- | --- |
| `mBitsPerChannel` is bit depth for PCM | Both: `mBitsPerChannel=16` (matches) | Correct field **for lpcm** | observed |
| It is not interchangeable with byte fields | `mBytesPerFrame`=2 (A)/4 (B), `mBytesPerPacket`=2/4, `mFramesPerPacket`=1 | Byte/packet fields depend on channels; **not** bit depth | observed |
| Lossy formats differ | Not tested (no lossy fixture) | Expected `mBitsPerChannel=0` for lossy → `unsupported` | inferred / not tested |

**Policy:** `available` only when the codec is `lpcm` **and** `mBitsPerChannel > 0`. Lossy codec →
`unsupported`. `mBitsPerChannel == 0` on a format where it should exist → `unavailable`. **Never**
infer from byte/packet fields.

### E — Duration

| Hypothesis | Observation | Conclusion | Confidence |
| --- | --- | --- | --- |
| `load(.duration)` gives seconds | A: 0.5 s, B: 0.25 s (exact) | Works for well-formed files | observed |
| A public flag marks exact vs estimated | **No.** Truncated Fixture A → duration `value=0`, **valid+numeric+finite**, seconds `0.0` (wrong), no error | `CMTime` validity/numeric flags do **not** prove correctness or exactness | observed |

**What the adapter can assert:** a finite numeric duration is present. **What it cannot assert:** that
it is exact/correct — a damaged file yielded a "valid" 0.0. **Recommendation:** map to `available` for
a finite numeric duration, but keep `uncertain` available for indefinite durations and known-degraded
inputs; do **not** promise an exact-vs-estimated split the API does not support.

### F — Container vs extension (the key experiment)

| Case | UTI (`contentType`) | AVFoundation decode | Meaning |
| --- | --- | --- | --- |
| Real WAV, `.wav` | `com.microsoft.waveform-audio` | lpcm 22050/mono | UTI matches — but only by extension |
| **WAV bytes renamed `.aiff`** | `public.aiff-audio` (**wrong**) | lpcm 22050/mono (**real WAV content**) | UTI **lies**; AVFoundation reads the true content |
| WAV bytes renamed `.bin` | `com.apple.macbinary-archive` | **Cannot Open** (-11828) | Non-audio extension → demux refused |

**Conclusion:** `URLResourceValues.contentType` is **purely extension/type-driven and can be wrong**.
AVFoundation exposes the **codec** (`lpcm`) but **no public "real container detected" signal** (WAV vs
AIFF is indistinguishable via these APIs without byte parsing, which is out of scope). Therefore a
`container` value derived from UTI/extension is an **inference**.

**Recommended policy:** `container` from UTI/extension → **`uncertain`** with a reason (never
`available`); no type at all → `unavailable`. Direct-recognition `available` is **not achievable** for
the container with AVFoundation alone in this slice — this strengthens ADR-0012's stance and is the
main candidate use for an AudioToolbox fallback (Experiment I).

### G — Bitrates (declared vs estimated)

| Hypothesis | Observation | Conclusion | Confidence |
| --- | --- | --- | --- |
| `estimatedDataRate` gives a usable rate | **0.0 bit/s for PCM** on both fixtures (track-level) | Useless for PCM; API name is literally "estimated" | observed |
| A declared/nominal bitrate is exposed | None found via AVFoundation | No direct `declaredBitrate` source for PCM | observed / inferred |
| `fileSize*8/duration` approximates it | A: 418336 vs stream `22050*1*16=352800`; B: 1542272 vs `1411200` | File-based value is **higher** (container/header overhead) → always approximate | observed |

**`declaredBitrate`:** no direct AVFoundation source for PCM → **`unavailable`**. (`estimatedDataRate`
is named "estimated", so even when non-zero it must feed `estimatedBitrate`, never `declaredBitrate`.)
**`estimatedBitrate`:** always `uncertain`; candidate inputs are `estimatedDataRate` (when non-zero,
lossy) or the file-based `fileSize*8/duration`. The file-based number includes container overhead and
is **stream-bitrate ≠ file-bitrate**, which is exactly why it is `uncertain`; do **not** compute it
when size or a usable duration is missing.

### H — Errors

| Case | Result | Class |
| --- | --- | --- |
| Missing path | `loadTracks`/`load(.duration)` throw AVError -11800 | **global** |
| Empty `.wav` | throw AVError -11849 "media may be damaged" | **global** |
| Text as `.wav` | throw AVError -11800 (underlying FourCC `typ?`) | **global** |
| Truncated Fixture A | **no throw**; 1 track, correct ASBD (from intact header), but duration 0.0 | **partial** (structural fields present, duration degraded) |

**Semantic rule (not an SDK code table):** if `loadTracks(withMediaType:.audio)` (or the whole asset
load) throws → **global** `InspectionError` — no useful property set can be produced. If tracks load but
a *specific* later read throws while others succeed → **property-level** `Property.failed`. **Absence**
of a datum (e.g. `estimatedDataRate == 0`) is **not** an error → `unavailable`/`unsupported`. Note the
partial case: a damaged file can return structurally-valid fields plus a misleading duration with no
error — which is why duration keeps an `uncertain` path.

> A clean property-level `failed` (tracks OK, one description read throws) could **not** be forced with
> these fixtures; the path exists in the model but is rare. Left as an open item for 3.6.

### I — Is AudioToolbox needed?

After A–H, everything the **basic PCM slice** needs is available from **AVFoundation + CoreMedia**:
`sampleRate`, `channelCount`, `bitDepth` (PCM), `codec`, `duration`, and the error classification. Two
gaps remain, both non-blocking for group 3:

- **Real container** (WAV vs AIFF): AVFoundation cannot distinguish it; AudioToolbox
  `kAudioFilePropertyFileFormat` *could* return the container FourCC (e.g. `'WAVE'`/`'AIFF'`). Candidate
  fallback — **not exercised in this spike** (kept the AVFoundation container as `uncertain` instead).
- **Nominal/declared bitrate**: AudioToolbox `kAudioFilePropertyBitRate` *might* provide one for some
  formats. Candidate fallback, unverified.

**Decision:** do **not** adopt AudioToolbox for group 3. It buys only `uncertain`→`available` for
`container` and a possible `declaredBitrate` source — neither essential for the basic slice — at the
cost of a second media dependency and error surface. Keep it as a **documented, unexercised fallback**
to be validated in its own isolated experiment **only if** a later slice needs the real container or a
nominal bitrate.

## Limitations & open questions

- Single OS/SDK; single run; only PCM WAV/AIFF fixtures. Lossy/FLAC/ALAC/AAC/M4A behavior is
  **not tested** here (needs the broader fixture set / real files → later in 3.1's spirit or 3.3+).
- Multi-track ordering, multiple/empty format descriptions, and mid-track format changes were **not
  observable** with single-stream PCM → the track/discrepancy policy is proposed but unproven for N>1.
- A pure property-level `failed` was not forced (see H).
- AudioToolbox container/bitrate value is a hypothesis, not measured.

## Impact

- **ADR-0012**: stays **Proposed**. The spike validates the *shape* of the strategy for PCM but leaves
  lossy/discrepancy/multi-track and the AudioToolbox question open — insufficient to accept the full
  productive strategy. Documented what remains for acceptance (below).
- **`docs/audio-property-matrix.md`**: updated from *pre-spike hypothesis* to *partially validated by
  spike 0031*, per-property, preserving the original hypotheses.
- **ADR-0011**: no change — no architectural contradiction found (the boundary held: everything mapped
  to plain values; Apple errors are catchable `NSError`/`AVError` that the adapter can translate).

## Proposal for task 3.2

- **Track selection:** first audio track of `loadTracks(withMediaType:.audio)`; 0 → stream fields
  `unavailable`; multi-track deferred.
- **Reliable direct fields:** `sampleRate`, `channelCount`, `codec` (FourCC token), `bitDepth` (PCM
  `mBitsPerChannel>0`; lossy `unsupported`) from the selected track's ASBD.
- **`duration`:** finite numeric → `available`; indefinite/degraded → `uncertain`; no exact-vs-estimated
  promise.
- **`container`:** `uncertain` from UTI/extension (never `available` via AVFoundation alone);
  `unavailable` if no type.
- **`declaredBitrate`:** `unavailable` (no direct AVFoundation source for PCM).
- **`estimatedBitrate`:** always `uncertain`; input from `estimatedDataRate` (if >0) or
  `fileSize*8/duration` (prerequisites met), reason names the method.
- **Errors:** asset/tracks load throws → global `InspectionError`; per-field read throws → `failed`;
  absence → `unavailable`/`unsupported`.
- **AudioToolbox:** not a 3.2 dependency.

## Spike code: keep or delete

**KEEP** — the `Spike/AudioPropertySpike` package is fully isolated (sibling SwiftPM package, outside
`Sources/`, not linked by the app, not scanned by `check-boundaries.sh`, implements no domain type) and
lets 3.2 re-run the observations cheaply. It is clearly labelled a spike and safe to delete once 3.2
lands. Run it with the commands above.
