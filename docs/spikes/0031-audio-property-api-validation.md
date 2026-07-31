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
| Architecture | arm64 |
| Swift driver **default host** triple | `arm64-apple-macosx26.0` (from `swift --version`; the compiler's host default, **not** the package's target) |
| Spike **deployment target** | **macOS 15**, declared in `Spike/AudioPropertySpike/Package.swift` (`.macOS(.v15)`); matches the productive package, not lowered |
| Effective **compilation** triple for the spike module | `arm64-apple-macosx15.0` (observed in `swift build -v`; i.e. the package builds against its macOS 15 deployment target, independent of the host default above) |
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
| Audio tracks come from `loadTracks(withMediaType:.audio)` | Both fixtures → **1** audio track, `trackID=1`, 1 format description | The API returns the audio tracks; single-track PCM is trivial | observed |
| The array order is meaningful for N>1 | Only 1 track present; N>1 not produced | The framework-provided order is **observable but its semantics are not guaranteed** | not tested |

**Proposed 3.2 policy (provisional, revisable):** as a deterministic initial rule, take `[0]` of
`loadTracks(withMediaType:.audio)` — **not** claimed to be a "primary/preferred/main" track (Apple does
not guarantee that; the term is left undefined here). 0 tracks → stream fields `unavailable` (not a
global failure); ≥1 → use `[0]`. Multi-track ordering and selection semantics were **not validated**
and are deferred; 3.2 may adopt `[0]` provisionally and revisit.

### B — Sample rate & channel count

| Hypothesis | Observation | Conclusion | Confidence |
| --- | --- | --- | --- |
| Both come from the track's ASBD | A: `mSampleRate=22050`, `mChannelsPerFrame=1`; B: `44100`, `2` — exact matches | ASBD is the reliable direct source | observed |

**Source:** ASBD `mSampleRate` / `mChannelsPerFrame`. **Confidence:** high for PCM. Absence (no track)
→ `unavailable`; disagreement across format descriptions → `uncertain` (not forced here).

### C — Codec token

| Hypothesis | Observation | Conclusion | Confidence |
| --- | --- | --- | --- |
| `mFormatID`/media subtype yields a stable token | Both real fixtures: `mFormatID = 'lpcm'` (0x6c70636d); media subtype == format ID | FourCC → ASCII token works for real PCM | observed |
| A fallback is needed for non-printable / space-padded IDs | Exercised with **synthetic** codes: `0x61616320` (`'aac '`, trailing space) → `0x61616320`; `0x6D730000` (nulls) → `0x6D730000`; `0x00000001` → `0x00000001` | Hex fallback works; space/NUL/control excluded from ASCII | observed (synthetic) |

**Proposed token format:** ASCII `'abcd'` only when all four FourCC bytes are **unambiguously** printable
`0x21–0x7E` (**space `0x20`, NUL and control bytes are excluded** so a padded/empty FourCC never yields a
visually ambiguous token); otherwise a fixed-width uppercase `0x%08X` hex fallback. The FourCharCode is
read **big-endian** (MSB = first char). **Pros:** stable, non-localized, deterministic, unambiguous.
**Cons:** raw FourCC, not a friendly name; some real space-padded codecs will render as hex. Full
normalization (e.g. `'lpcm'`→`pcm`) and the final serialization are **out of scope — deferred to 3.2/the
ADR**.

### D — Bit depth

| Hypothesis | Observation | Conclusion | Confidence |
| --- | --- | --- | --- |
| `mBitsPerChannel` is bit depth for PCM | Both: `mBitsPerChannel=16` (matches) | Correct field **for lpcm** | observed |
| It is not interchangeable with byte fields | `mBytesPerFrame`=2 (A)/4 (B), `mBytesPerPacket`=2/4, `mFramesPerPacket`=1 | Byte/packet fields depend on channels; **not** bit depth | observed |
| Lossy formats differ | **Not tested** (no lossy fixture) | *Hypothesis*: `mBitsPerChannel` likely 0/inapplicable for lossy | not tested |

**Policy (candidate):** `available` only when the codec is PCM (`lpcm`) **and** `mBitsPerChannel > 0`
(observed). For **lossy codecs**, bit depth has no PCM sample-depth meaning, so the *semantic* mapping is
`unsupported` — this is a **domain/semantic decision, not an empirical spike observation** (no lossy
fixture was tested; whether `mBitsPerChannel==0` empirically is an open item). `mBitsPerChannel == 0`
where a value should exist → `unavailable`; ambiguous semantics → `uncertain`. **Never** infer bit depth
from byte/packet fields (validated: `mBytesPerFrame`/`mBytesPerPacket` track channel count, not depth).

### E — Duration

| Hypothesis | Observation | Conclusion | Confidence |
| --- | --- | --- | --- |
| `load(.duration)` gives seconds | A: 0.5 s, B: 0.25 s (exact for these fixtures) | Works for these well-formed files | observed |
| A public flag marks exact vs estimated | **None observed.** In *this truncated copy*, duration came back `value=0` (`valid`, `numeric`, finite → `0.0`) with no error | No observed public signal distinguished this `0.0` from a legitimate duration; a finite value does not prove exactness | observed (single case) |

**What the adapter can assert:** a numeric, finite duration was returned. **What it cannot assert:** that
it is exact/correct — in this one truncated copy a `0.0` came back "valid". This is *this* fixture's
behavior, **not** a universal claim that truncation always yields a wrong duration.

**Recommended (conservative) policy — zero must not be blindly `available`:**
- positive, finite, numeric, no error → candidate `available` for the slice contract;
- **`0.0`** → `available` only if the file can legitimately be zero-length *and* there is sufficient
  evidence; otherwise `uncertain`/`unavailable` (a bare "finite+numeric → available" rule is
  **insufficient**, as `0.0` here proves);
- indefinite / non-numeric → `unavailable` or `uncertain` (if a candidate value exists);
- concrete load error → `failed` (property-level) or global by scope.
Do **not** promise an exact-vs-estimated split the API does not expose.

### F — Container vs extension (the key experiment)

| Case | UTI (`contentType`) | AVFoundation decode | Meaning |
| --- | --- | --- | --- |
| Real WAV, `.wav` | `com.microsoft.waveform-audio` | loaded: 1 track, duration 0.5 s, 1 format desc, lpcm 22050/mono | UTI matches — but that only reflects the extension |
| **WAV bytes renamed `.aiff`** | `public.aiff-audio` (**does not match the bytes**) | **loaded successfully**: 1 track, duration 0.5 s, 1 format desc, lpcm 22050/mono (the real WAV content) | UTI reflects the extension, not the bytes; AVFoundation decoded the true content, but exposed **no container token** |
| WAV bytes renamed `.bin` | `com.apple.macbinary-archive` | **Cannot Open** (-11828, "media format not supported") | Failed at the **type-discovery** step (non-audio UTI), not necessarily because the bytes are unreadable |

**Conclusion (scoped to what was evaluated):** among the **AVFoundation/CoreMedia APIs exercised in this
spike**, no direct, reliable *container* signal was found — AVFoundation surfaced the **codec** (`lpcm`)
but no container token (WAV vs AIFF). `URLResourceValues.contentType` is a `UTType` derived from the
**extension** (`UTType(filenameExtension:)`-style inference) and was demonstrably wrong for the renamed
copy. This does **not** prove that no public API in any context can expose the container — only that the
evaluated ones did not. The `.bin` failure appears to be the type-discovery mechanism refusing a
non-audio UTI, not proof the bytes were unreadable.

**Recommended policy:** `container` inferred from UTI/extension → **`uncertain`** with a reason (never
`available` on this evidence); no type at all → `unavailable`; a direct-recognition `available` awaits a
*validated* source. This is the main **candidate** use for an AudioToolbox fallback (Experiment I) —
**not adopted here**.

### G — Bitrates (declared vs estimated)

| Hypothesis | Observation | Conclusion | Confidence |
| --- | --- | --- | --- |
| `estimatedDataRate` gives a usable rate | `estimatedDataRate` = **0.0 bit/s** for PCM on both fixtures (track-level, unit = bit/s) | For PCM it is **absent** (0.0 = no data, not "0 bitrate"); its API name is literally "estimated" | observed (PCM only) |
| A declared/nominal bitrate is exposed | None found among the evaluated APIs | No direct `declaredBitrate` source **in these APIs / for these PCM fixtures** | observed / inferred |
| `fileSize*8/duration` approximates it | A: **418336** (file-based) vs **352800** stream (`sampleRate 22050 × ch 1 × bits 16`); B: 1542272 vs 1411200 | File-based value is **higher** (WAV/AIFF header overhead) → always approximate; for short fixtures the overhead is large | observed |

**Units/safety:** `estimatedDataRate` is bit/s; the file estimate uses `Double(fileSize) * 8 / seconds`
(no integer overflow), computed **only** when `fileSize` is known and duration is positive & finite.

**`declaredBitrate`:** no direct source found among the evaluated AVFoundation APIs for these PCM
fixtures → **`unavailable`** here. (This is *not* a claim that no metadata/API for any format could ever
declare one; `estimatedDataRate` is named "estimated" so, even when non-zero, it feeds `estimatedBitrate`,
never `declaredBitrate`.) **`estimatedBitrate`:** always `uncertain`; candidate inputs are
`estimatedDataRate` **when > 0** (untested for compressed formats — a candidate there) or the file-based
`fileSize*8/duration`. The file number is **file-bitrate ≠ stream-bitrate** (includes container
overhead) — exactly why it is `uncertain`; do **not** compute it when size or a usable duration is
missing. The theoretical PCM stream bitrate (`sampleRate × channels × bitsPerChannel`) is used **only as
an exploratory contrast**, not as a productive/declared value and not a universal formula.

### H — Errors

| Case | Result | Class |
| --- | --- | --- |
| Missing path | `loadTracks`/`load(.duration)` throw AVError -11800 | **global** |
| Empty `.wav` | throw AVError -11849 "media may be damaged" | **global** |
| Text as `.wav` | throw AVError -11800 (underlying FourCC `typ?`) | **global** |
| Truncated Fixture A | **no throw**; 1 track, correct ASBD (from intact header), but duration 0.0 | **partial** (structural fields present, duration degraded) |

**Semantic rule (ADR-0011: classify by scope/effect, not by which API threw, and not an SDK code
table):** if the asset/`loadTracks` cannot open or recognize the file at all → **global**
`InspectionError` (no useful property set can be produced). But a throw from `load(.duration)` is **not
automatically global**: if tracks and format descriptions still loaded, a duration-only failure is a
**property-level** `Property.failed` (or `uncertain`) for `duration`, with the other properties still
reported. Likewise any single later read that throws while others succeed → property-level. **Absence**
of a datum (e.g. `estimatedDataRate == 0`) is **not** an error → `unavailable`/`unsupported`. In the
observed cases missing/empty/text failed at the *whole-file* level (both `loadTracks` and duration
threw), hence global; the future adapter must still decide per-scope, not by the throwing API's name.

> A clean property-level `failed` (tracks OK, one description read throws) could **not** be forced with
> these fixtures; the path exists in the model but is rare. Left as an open item for 3.6.

### I — Is AudioToolbox needed?

After A–H, the fields the **basic PCM slice can determine** came from **AVFoundation + CoreMedia**:
`sampleRate`, `channelCount`, `bitDepth` (PCM), `codec`, `duration`, and the error classification.
AudioToolbox was **not exercised**. This is **not** a claim that AVFoundation covers *all* fields: on
this evidence `container` stays `uncertain` and `declaredBitrate` `unavailable` **by design/limitation,
not for lack of AudioToolbox**, and compressed formats were **not tested**. Two gaps remain, both
non-blocking for starting group 3:

- **Real container** (WAV vs AIFF): not found among evaluated AVFoundation APIs; AudioToolbox
  `kAudioFilePropertyFileFormat` *could* return the container FourCC (e.g. `'WAVE'`/`'AIFF'`). Candidate
  fallback — **unverified**.
- **Nominal/declared bitrate**: AudioToolbox `kAudioFilePropertyBitRate` *might* provide one for some
  formats. Candidate fallback — **unverified**.

**Decision (current evidence):** AudioToolbox was **not necessary** to extract the validated PCM
properties and was **not exercised**; its usefulness for the real container, compressed formats, or
extra metadata is **not validated**. So **3.2 can begin without adopting it**. It buys only
`uncertain`→`available` for `container` and a possible `declaredBitrate` source — neither essential for
the basic slice — at the cost of a second media dependency and error surface. Keep it as a **documented,
unexercised fallback**, and **revisit the decision at 3.5 or once compressed-format fixtures exist**;
adopt it only if a later slice needs the real container or a nominal bitrate.

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
- **Reliable direct fields:** `sampleRate`, `channelCount`, `codec` (FourCC token) from the selected
  track's ASBD; `bitDepth` `available` for PCM (`mBitsPerChannel>0`), `unsupported` for lossy (semantic).
- **`duration`:** **positive** finite numeric → candidate `available`; **`0.0`** → `uncertain`/
  `unavailable` unless a legitimate zero-length is evidenced (a bare finite→available rule is
  insufficient); indefinite/non-numeric → `unavailable`/`uncertain`; no exact-vs-estimated promise.
- **`container`:** `uncertain` from UTI/extension inference (never `available` on current evidence);
  `unavailable` if no type.
- **`declaredBitrate`:** `unavailable` (no direct source found among evaluated APIs for PCM).
- **`estimatedBitrate`:** always `uncertain`; input from `estimatedDataRate` (only if >0) or
  `fileSize*8/duration` (prerequisites met), reason names the method.
- **Errors:** classify by **scope** (ADR-0011): whole-file open/recognition failure → global
  `InspectionError`; a single property's read failing while others load → property-level `failed`;
  absence → `unavailable`/`unsupported`.
- **AudioToolbox:** not a 3.2 dependency.

## Spike code: keep or delete, and lifecycle

**Decision: KEEP (for now).** The `Spike/AudioPropertySpike` package is fully isolated — a sibling
SwiftPM package outside `Sources/`, not linked by the app, not part of the productive build graph, not
scanned by `check-boundaries.sh`, importing no domain type and no external dependency — and it lets 3.2
re-run the observations cheaply.

**Lifecycle:**
- **Nature / owner:** an exploratory tool, **not product**. It must never move into the productive
  package, implement `AudioFilePropertyReading`, or import `AudioInspectorDomain`.
- **Deletion criterion:** delete (or archive) it once **3.2–3.7 are stabilized** and the adapter's own
  unit/integration tests cover these observations — at that point the tool no longer adds reproducible
  value. If deleted, the commands and the synthetic snippets in this report remain sufficient to
  reproduce the findings.
- **While kept:** run only via the documented commands below; it writes solely to a temp dir it removes
  on exit, so it never dirties the repo.

Run it with the commands in the "Commands" section above.
