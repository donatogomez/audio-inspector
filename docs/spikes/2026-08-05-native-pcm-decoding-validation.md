# Spike — Native PCM decoding validation (`AVAudioFile`)

> **STATUS: GATES 1, 2, 2.5 AND 2.75 RUN. Experiments F–K NOT RUN.** Sections A to E and the two
> investigation gates carry observations; every other result section is still marked *not run* and
> nothing may be inferred from it. The matrix, the falsification criteria and the method were fixed
> **before** any measurement, so a result could not be chosen after the fact to fit a conclusion.
>
> Covered so far: five natively-writable formats (WAV, AIFF, ALAC, FLAC, AAC) with **well-formed**
> fixtures, a 4-channel PCM fixture, and a native-float fixture carrying values beyond ±1.
> **MP3, degenerate files (empty, truncated, corrupt, unreadable), chunk sizing, cancellation,
> memory and isolation were not exercised.**

- **Date prepared**: 2026-08-05
- **Branch**: `spike/validate-native-pcm-decoding`
- **OpenSpec change**: **none, deliberately.** OpenSpec requires at least one requirement delta per
  change (`Change must have at least one delta` — an error with *and* without `--strict`), and the
  evidence needed to write those deltas honestly is exactly what this spike must produce. Inventing a
  requirement to satisfy the validator would be writing a contract backwards. The waveform change is
  opened **after** this report exists.
- **Related**: ADR-0003 (native-first; its decoding hypothesis is what this resolves), ADR-0011
  (the port's semantic boundary), ADR-0005, `docs/architecture.md`, `docs/concurrency.md`,
  `docs/testing-strategy.md`, spike 0031.

## Objective

Determine, with compilable and runnable evidence, whether **`AVAudioFile`** is sufficient to read
decoded PCM for the project's target formats under Swift 6 strict concurrency — and at what cost —
**before** any port, adapter, domain type or UI is written.

ADR-0003 states its own limit plainly: native-first is the direction, but *"its technical sufficiency
is unproven"*, and it requires a spike over real and synthetic fixtures before committing MVP
decoding to native APIs. Spike 0031 did **not** do this: it covered *property* reading over two PCM
fixtures (WAV, AIFF) and records that decoding, lossy formats, FLAC/ALAC and large-file behaviour were
**not tested**.

**This spike decides nothing.** It produces evidence. The architecture is chosen afterwards, in
ADR-0015 and in the waveform change's design, citing what is written here.

## What is already verified (not from this spike)

Read directly from the SDK headers, so it needs no experiment:

| Observation | Source |
| --- | --- |
| `AVAudioFile` is annotated `NS_SWIFT_SENDABLE` | `MacOSX26.5.sdk/…/AVFAudio.framework/Headers/AVAudioFile.h:28` |
| `AVAssetReader` is annotated `NS_SWIFT_NONSENDABLE` | `MacOSX26.5.sdk/…/AVFoundation.framework/Headers/AVAssetReader.h:61` |

The `NS_SWIFT_SENDABLE` annotation removes the compiler's objection to sharing an `AVAudioFile`; it
does not remove the mutable read cursor (`framePosition`) that makes sharing wrong. Experiment J
exists to observe what that actually costs, not to assume it.

## Environment

| Item | Value |
| --- | --- |
| macOS | 26.3 (build 25D125) |
| Xcode | 26.6 (17F113) |
| Swift | 6.3.3 (swiftlang-6.3.3.1.3) |
| SDK | MacOSX 26.5 |
| Architecture | arm64 |
| Spike deployment target | **macOS 15** (`.macOS(.v15)`), matching the productive package — not lowered |
| Language mode | Swift 6, strict concurrency, built with `-Xswiftc -warnings-as-errors` |
| FFmpeg (MP3 fixture only) | 8.1.2, with `libmp3lame` present |

> **SDK-dependence caveat**, inherited from spike 0031: every observation will come from **one**
> OS/SDK. Numeric error codes and some behaviours are SDK-dependent; the *semantic* conclusions are
> what carry forward, never the codes.

## Fixture matrix

Generated at runtime into a temporary directory and removed on exit — no audio binary enters the
repository (`docs/testing-strategy.md`). The `.gitignore` already refuses `*.private.mp3` and
`/Fixtures/private/` as a second line of defence.

| # | Fixture | How it is produced | Purpose |
| --- | --- | --- | --- |
| 1 | WAV / LPCM | `AVAudioFile(forWriting:)` | baseline, uncompressed |
| 2 | AIFF / LPCM | `AVAudioFile(forWriting:)` | second uncompressed container |
| 3 | ALAC / M4A | `AVAudioFile(forWriting:)`, `kAudioFormatAppleLossless` | lossless compressed |
| 4 | FLAC | `AVAudioFile(forWriting:)`, `kAudioFormatFLAC` | third-party lossless |
| 5 | AAC / M4A | `AVAudioFile(forWriting:)`, `kAudioFormatMPEG4AAC` | lossy, Apple-encodable |
| 6 | **MP3** | **FFmpeg only — manual, see below** | lossy, **not encodable natively** |
| 7 | Multichannel (≥3 ch) | `AVAudioFile(forWriting:)` | experiment D |
| 8 | Float, out-of-range | `AVAudioFile(forWriting:)`, float PCM, samples beyond ±1 | experiment E |
| 9 | Empty file | zero-byte file with an audio extension | experiment H |
| 10 | Truncated | first N bytes of fixture 1 | experiment H |
| 11 | Corrupt | valid header, damaged payload | experiment H |
| 12 | Unreadable | existing path, permissions removed | experiment H |
| 13 | Long file | several minutes, generated | experiments F and I |

**A fixture that cannot be produced is recorded as *not tested*.** It is never inferred from another
format's result — the failure mode spike 0031 explicitly guarded against.

### MP3 — manual validation, explicitly **not** CI coverage

macOS has an MP3 **decoder** but no MP3 **encoder**: neither `AVAudioFile` nor `afconvert` can
produce one. `.github/workflows/ci.yml` runs on `macos-26` and does **not** install FFmpeg, so any
FFmpeg-gated test would skip on **every** CI run. Calling that "conditional coverage" would be
dishonest; it is **zero** coverage.

MP3 is therefore validated **by hand, once, on the development machine**, reproducibly:

```bash
# 1. Generate a deterministic synthetic source (no copyrighted material, no repository binary)
ffmpeg -hide_banner -y \
  -f lavfi -i "sine=frequency=440:sample_rate=44100:duration=5" \
  -ac 2 -c:a pcm_s16le /tmp/spike-mp3-source.wav

# 2. Encode to MP3 with a pinned encoder and pinned parameters
ffmpeg -hide_banner -y \
  -i /tmp/spike-mp3-source.wav \
  -c:a libmp3lame -b:a 192k /tmp/spike-fixture.private.mp3

# 3. Record identity
ffmpeg -version | head -1
shasum -a 256 /tmp/spike-fixture.private.mp3
```

To be recorded here when run: **FFmpeg version · exact commands · encoder and parameters ·
SHA-256 of the produced file · the observed result of reading it with `AVAudioFile`.**

> **Not run in this form.** The MP3 case was closed later, against the **production adapter** rather
> than by hand against `AVAudioFile` — change `add-waveform-visualization`, task 0.6, closed by its
> option 3: an FFmpeg-gated test (`MP3WaveformEvidenceTests`) that skips wherever FFmpeg is absent. The
> measurements, including three behaviours specific to MP3 that this spike never saw, are recorded in
> **ADR-0015 → *MP3, measured against the production adapter***. The warning below still holds in full:
> that evidence is local, it is **not** CI coverage, and nothing may cite it as such.

> **This is a manual observation on one machine. It is NOT CI coverage, it is NOT part of
> `swift test`, and no later document may cite it as either.** If MP3 support must be guaranteed
> against regressions, that requires a separate, approved decision — committing a small synthetic
> fixture (which would amend `docs/testing-strategy.md`) or installing FFmpeg in CI (which would
> promote a dev-only dependency, in tension with ADR-0003). **Neither is proposed here.**

## Falsification criteria

Written before the measurements. If any is met, `AVAudioFile` is **not** adopted, and the fallback
(`AVAssetReader`, whose entire non-`Sendable` lifecycle must live inside an actor) is designed with
this evidence rather than assumed.

1. A target format does not open, or does not decode to float PCM.
2. `length` (frame count) is absent, wrong, or unusable for a format that otherwise opens.
3. A degenerate file (empty, truncated, corrupt, unreadable) **crashes or hangs** rather than failing
   in a way the caller can handle.
4. Peak memory grows with the file's duration under chunked reading.
5. Cancellation does not stop the read at a chunk boundary.
6. Strict concurrency forces a per-chunk copy whose cost makes the chunked-port shape (experiment K)
   unusable — in which case that is an argument about *where the reduction lives*, recorded as such.

A criterion that cannot be evaluated is recorded as **not evaluated**, never as passed.

## Method

Legend for **Confidence**, as in spike 0031: *observed* (measured here) · *inferred* (reasoned from
observations) · *not tested* (could not be forced with these fixtures) · *format-dependent* ·
*SDK-dependent*.

```bash
cd Spike/validate-native-pcm-decoding
swift build -Xswiftc -warnings-as-errors
swift run  -Xswiftc -warnings-as-errors NativePCMDecodingSpike
```

## Results

### A — Open, processing format, frame length

**Run at gate 1.** Fixtures: 44 100 frames @ 44 100 Hz, 2 ch, generated with `AVAudioFile(forWriting:)`.
Every one of the five was generated **and** opened; the two are recorded separately, and neither was
inferred from the other.

Each row is self-contained on purpose — no cell refers to another row.

| Fixture | Generated | Opened | `fileFormat` | `processingFormat` | `length` |
| --- | --- | --- | --- | --- | ---: |
| WAV | yes | yes | `'lpcm'` int16, 44 100 Hz, 2 ch, 16 bits/ch, 1 frame/packet, **interleaved** | `'lpcm'` float32, 44 100 Hz, 2 ch, 32 bits/ch, 1 frame/packet, **planar** | 44 100 |
| AIFF | yes | yes | `'lpcm'` *other*, 44 100 Hz, 2 ch, 16 bits/ch, 1 frame/packet, **interleaved** | `'lpcm'` float32, 44 100 Hz, 2 ch, 32 bits/ch, 1 frame/packet, **planar** | 44 100 |
| ALAC | yes | yes | `'alac'` *other*, 44 100 Hz, 2 ch, 0 bits/ch, **4096** frames/packet, **interleaved** | `'lpcm'` float32, 44 100 Hz, 2 ch, 32 bits/ch, 1 frame/packet, **planar** | 44 100 |
| FLAC | yes | yes | `'flac'` *other*, 44 100 Hz, 2 ch, 0 bits/ch, **4608** frames/packet, **interleaved** | `'lpcm'` float32, 44 100 Hz, 2 ch, 32 bits/ch, 1 frame/packet, **planar** | 44 100 |
| AAC | yes | yes | `0x61616320` *other*, 44 100 Hz, 2 ch, 0 bits/ch, **1024** frames/packet, **interleaved** | `'lpcm'` float32, 44 100 Hz, 2 ch, 32 bits/ch, 1 frame/packet, **planar** | 44 100 |

| Hypothesis | Observation | Conclusion | Confidence |
| --- | --- | --- | --- |
| The five target formats open with `AVAudioFile` | All five opened, no error | `AVAudioFile` opens them **on this SDK, for well-formed fixtures it also wrote** | observed |
| `processingFormat` is uniform across formats | **Identical for all five**: `'lpcm'` float32, 44 100 Hz, 2 ch, 32 bits/ch, 1 frame/packet, **planar (non-interleaved)** | One read path can serve all five — the conversion normalises container and codec away | observed |
| `fileFormat` reflects the stored format | Differs per format; compressed formats report 0 bits/ch and a packet size (4096 / 4608 / 1024) | `fileFormat` describes the file, `processingFormat` describes what you get | observed |
| `length` is exact | Equals frames written (44 100) for all five, **including lossy AAC** | For these fixtures `length` is exact; encoder delay/padding did not surface in it | observed |

**Notes.** AAC's format ID renders as `0x61616320` because its FourCC is `'aac '` with a trailing
space, which spike 0031's rule deliberately excludes from ASCII rendering — the two spikes agree.
AIFF's `commonFormat` is *other* because big-endian int16 has no `AVAudioCommonFormat` case; this says
nothing about readability, and the file read fine.

**Not tested at this gate:** MP3, sample rates other than 44 100, channel counts other than 2, files
this spike did not itself write, and any format read on a different SDK.

### B — Incremental read and EOF

**Run at gate 1.** Chunk size 4 096 frames — a single value; experiment F varies it later, so **no
conclusion about chunk sizing may be drawn from this section.**

| Fixture | Chunks | First chunk | Last chunk | Frames read | `length` | read − declared |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| WAV | 11 | 4 096 | 3 140 | 44 100 | 44 100 | **0** |
| AIFF | 11 | 4 096 | 3 140 | 44 100 | 44 100 | **0** |
| ALAC | 11 | 4 096 | 3 140 | 44 100 | 44 100 | **0** |
| FLAC | 11 | 4 096 | 3 140 | 44 100 | 44 100 | **0** |
| AAC | 11 | 4 096 | 3 140 | 44 100 | 44 100 | **0** |

10 × 4 096 + 3 140 = 44 100. The final chunk is short, as expected, and `framePosition` at stop was
44 100 in every case.

#### The finding that matters: EOF is signalled by a **throw**, not by a zero-length read

The loop that deliberately ignores `length` and reads until the decoder stops **threw on the read
following the last data-bearing read**, in all five formats:

```
Foundation._GenericObjCError 0: The operation couldn't be completed.
(Foundation._GenericObjCError error 0.)
```

That is the Swift bridging of an Objective-C method returning `NO` **without populating an
`NSError`** — so it carries no domain, no code, and no message of its own.

Because attributing this to the API rather than to the loop matters, the same read was repeated on a
**freshly opened instance** using the `framePosition < length` idiom:

| Fixture | Frames read | Chunks | Threw | Final `framePosition` |
| --- | ---: | ---: | --- | ---: |
| WAV · AIFF · ALAC · FLAC · AAC | 44 100 | 11 | **no** | 44 100 |

| Hypothesis | Observation | Conclusion | Confidence |
| --- | --- | --- | --- |
| EOF returns `frameLength == 0` | **Never observed.** The unguarded loop always threw instead | The common expectation does not hold here | observed |
| The throw is a defect of the unguarded loop | The guarded control read the same 44 100 frames in the same 11 chunks **without throwing** | The throw belongs to reading **past** the end, not to the loop and not to the format | observed |
| An error can be told apart from EOF | The end-of-file throw carries **no `NSError`** — a bare bridged failure | **At this gate the two are not distinguishable from the error value alone** | observed, well-formed fixtures only |

#### The finding, stated with its scope

Exactly what was observed, and nothing wider:

- **For the five fixtures tested — WAV, AIFF, ALAC, FLAC and AAC — `length` matched the number of
  frames actually decoded** (44 100 in every case, delta 0).
- **Calling `read(into:)` after `framePosition` had reached `length` threw
  `Foundation._GenericObjCError 0`**, in all five.
- **Therefore, for this matrix, the safe rule observed is: do not read when
  `framePosition == length`.** The guarded control confirms this reads everything and never throws.

**This does not generalise yet.** MP3, multichannel files, damaged files (truncated, corrupt, empty)
and files this spike did not itself write were **not tested**. Whether `length` remains trustworthy
for them — and whether a genuine failure is distinguishable from the end-of-file throw — is open.

**Consequences to carry forward — stated as consequences, not decisions:**

- **`length` is load-bearing.** A reader cannot safely stream "until EOF"; it must bound the loop with
  the declared frame count. This raises the stakes on falsification criterion 2: a format whose
  `length` is unusable is not merely inconvenient, it has no safe stopping rule.
- **Error-versus-EOF classification cannot rest on the error value.** ADR-0011 requires classifying by
  *scope*; this observation says the SDK will not help distinguish "finished" from "failed" at the
  point of the read.
- **The open question for gate 3 (experiment H) is now sharper:** does a genuine mid-file failure on a
  truncated or corrupt file produce the *same* bare `Foundation._GenericObjCError 0`? If it does, a
  partial read cannot be told from a completed one by the error alone, and the reader must reason from
  frames-read versus `length` instead. **Not yet tested — do not assume either way.**

### C — Planar versus interleaved

**Run at gate 2**, over the same five fixtures, chunk capacity 4 096 frames. Channels carry
distinguishable signals (channel 0 at 440 Hz, channel 1 at 660 Hz) — never the same sine in both.

| Fixture | `fileFormat` layout | `processingFormat` layout | `mNumberBuffers` | Channels/buffer | Bytes/buffer | `floatChannelData` | Chunks | First → last `frameLength` |
| --- | --- | --- | ---: | --- | --- | --- | ---: | --- |
| WAV | interleaved | **planar** | 2 | 1, 1 | 12 560, 12 560 | available | 11 | 4 096 → 3 140 |
| AIFF | interleaved | **planar** | 2 | 1, 1 | 12 560, 12 560 | available | 11 | 4 096 → 3 140 |
| ALAC | interleaved | **planar** | 2 | 1, 1 | 12 560, 12 560 | available | 11 | 4 096 → 3 140 |
| FLAC | interleaved | **planar** | 2 | 1, 1 | 12 560, 12 560 | available | 11 | 4 096 → 3 140 |
| AAC | interleaved | **planar** | 2 | 1, 1 | 12 560, 12 560 | available | 11 | 4 096 → 3 140 |

`mDataByteSize` reflects the **last** read: 3 140 frames × 4 bytes = 12 560 per channel buffer. The
layout is one buffer per channel with one channel each — textbook planar float32 — and it is identical
across all five.

#### Does `frameLength` actually bound the valid data?

Two passes, because they answer different questions. **Sentinel pass:** the whole buffer is overwritten
with `-999.0` before every read; afterwards the region `[frameLength, frameCapacity)` is inspected.
**No-wipe pass:** the same read without wiping, comparing that region with what it held *before* the
read.

| Fixture | Decoder wrote beyond `frameLength` | Tail still holds the previous chunk |
| --- | --- | --- |
| WAV | no | **yes** |
| AIFF | no | **yes** |
| ALAC | no | **yes** |
| FLAC | no | **yes** |
| AAC | **yes** | no |

| Hypothesis | Observation | Conclusion | Confidence |
| --- | --- | --- | --- |
| `processingFormat` is planar for every format | Planar in all five; `fileFormat` interleaved in all five | The conversion normalises layout as well as sample format | observed |
| The region past `frameLength` is safe to ignore | It is **never** empty: four formats leave the previous chunk's samples there, AAC has the decoder write into it | **`frameLength` must be respected in every case** — reading past it yields plausible, wrong audio | observed |
| All formats behave the same past `frameLength` | **They do not.** AAC differs from the other four | The *reason* differs by format; the *rule* does not | observed |

**AAC's difference is not a defect and is not evidence of anything about AAC's quality.** A packet-based
decoder producing 1 024 frames per packet plausibly fills a whole packet even when fewer frames were
requested. What matters is the operational rule, which is identical for all five: **use `frameLength`,
never `frameCapacity`.**

**Not tested:** MP3, interleaved processing formats (none appeared), buffers not allocated by this
spike, and whether the AAC behaviour holds at other chunk sizes — chunk sizing is experiment F.

### D — Multichannel behaviour

**Run at gate 2.** Fixture: **4-channel** 16-bit LPCM WAV, 44 100 Hz, 10 000 frames, each channel a
distinct constant — channel 0 = 0.1, channel 1 = 0.2, channel 2 = 0.3, channel 3 = 0.4.

A constant per channel is deliberate: **mixing** would show as a value that is none of the four,
**duplication** as two channels reading the same value, **loss** as a channel reading zero. What this
does **not** test is frame ordering *within* a channel, and no conclusion about that may be drawn here.

| Property | Observed |
| --- | --- |
| Generated without an explicit channel layout | **yes** — plain settings accepted, no `AVChannelLayoutKey` needed |
| Opened | yes |
| `fileFormat` | `'lpcm'` int16, 44 100 Hz, **4 ch**, 16 bits/ch, 1 frame/packet |
| `processingFormat` | `'lpcm'` float32, 44 100 Hz, **4 ch**, 32 bits/ch, 1 frame/packet |
| `length` declared | 10 000 |
| Frames read | **10 000** (3 chunks) — delta 0 |
| Any two channels identical | **no** |

| Channel | Written | Min read | Max read | Mean read | Max abs error |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 0 | 0.100000 | 0.100006 | 0.100006 | 0.100006 | 0.00000610 |
| 1 | 0.200000 | 0.200012 | 0.200012 | 0.200012 | 0.00001220 |
| 2 | 0.300000 | 0.299988 | 0.299988 | 0.299988 | 0.00001222 |
| 3 | 0.400000 | 0.399994 | 0.399994 | 0.399994 | 0.00000611 |

| Hypothesis | Observation | Conclusion | Confidence |
| --- | --- | --- | --- |
| More than two channels are handled | 4 channels written, opened and read; count preserved | Beyond stereo works for this fixture | observed |
| Channels keep their identity and order | Each channel read back its own constant, in order; no pair identical | **No mixing, no duplication, no loss** | observed |
| The values survive the round trip | Max absolute error 1.22 × 10⁻⁵ per channel | Consistent with 16-bit quantisation, whose step is 1/32 768 ≈ 3.05 × 10⁻⁵ — the error is **below** it | observed |

**Not tested:** channel *layouts* and their semantic tags (only the count and order were checked),
more than four channels, compressed multichannel, and frame ordering within a channel.

### E — Sample values and out-of-range output

**Run at gate 2.** Fixture: **native float PCM**, 32-bit, 2 channels, 28 frames — four cycles of the
required pattern `[-1.5, -1, -0.25, 0, 0.25, 1, 1.5]`. Channel 0 walks it forwards, channel 1
backwards, so both signs are exercised at both ends of the buffer.

The fixture **could** be produced: `AVAudioFile(forWriting:)` accepted float settings and the file's
own format came back as float32, so nothing about this case is *not tested*.

| Property | Observed |
| --- | --- |
| `fileFormat` | `'lpcm'` **float32**, 44 100 Hz, 2 ch, 32 bits/ch |
| `processingFormat` | `'lpcm'` **float32**, 44 100 Hz, 2 ch, 32 bits/ch |
| `length` declared · frames read | 28 · 28 |
| Min per channel | −1.500000 · −1.500000 |
| Max per channel | +1.500000 · +1.500000 |
| **Max absolute error per channel** | **0.00000000 · 0.00000000** |

```
ch0 written  -1.5000  -1.0000  -0.2500   0.0000   0.2500   1.0000   1.5000
ch0 read     -1.5000  -1.0000  -0.2500   0.0000   0.2500   1.0000   1.5000
ch1 written   1.5000   1.0000   0.2500   0.0000  -0.2500  -1.0000  -1.5000
ch1 read      1.5000   1.0000   0.2500   0.0000  -0.2500  -1.0000  -1.5000
```

| Hypothesis | Observation | Conclusion | Confidence |
| --- | --- | --- | --- |
| Values beyond ±1 are clipped | **No.** ±1.5 read back as ±1.5 | Not clipped | observed |
| Values are normalised to the peak | **No.** Every sample matched bit-for-bit, error exactly 0 | Not normalised | observed |
| Values are preserved | Max absolute error **0.0** across all 56 samples | **Preserved exactly, including beyond the nominal range** | observed |

**Scope — this applies to the native float PCM tested and to nothing else.** It is **not** extrapolated
to integer PCM (which cannot represent values beyond ±1 in the first place) and **not** to any
compressed format, none of which were exercised here. Whether a *converted* read of an integer or
compressed source can ever emit values outside ±1 is **not tested** and remains open.

## Gate 2.5 — Buffer lifetime investigation

Gate 2 established **that** the region past `frameLength` is never empty, and that the reason appeared
to differ between AAC and the other four formats. This gate exists to find out what is *observable*
about that difference — experimentally, not from documentation. It adds **no** coverage: same
fixtures, same read flow.

**Language discipline used throughout.** A value that differs from what was placed there is recorded
as *"modifications were observed"*. Who or what performed them is a **hypothesis**, kept in its own
section below and never smuggled into a result.

### 1. Methodology

**C2 — storage reuse.** Same read flow, capacity 4 096, three conditions plus an address census:

| | Condition | What it isolates |
| --- | --- | --- |
| **1** | One buffer reused across reads, **nothing wiped** | whether the tail simply keeps what was there |
| **2** | One buffer reused, **whole capacity overwritten with `-999.0` before every read** | whether anything writes into the tail |
| **3** | **A brand-new `AVAudioPCMBuffer` allocated for every read**, nothing wiped | whether the tail survives a new allocation |

Address census per read: the address of every `floatChannelData` channel pointer, the address of every
`AudioBuffer.mData`, `frameCapacity` and `frameLength`; plus two buffers alive simultaneously, to see
whether distinct buffers get distinct storage.

**C3 — capacity sweep.** Experiment C repeated at capacities **1, 2, 3, 7, 31, 64, 127, 1 024, 4 096**,
recording per format and capacity: reads, total frames, minimum and maximum `frameLength`, short reads
*followed by another read*, the final read's length, whether a tail region ever existed, and the tail's
state under both the wiped and the un-wiped pass. **Functional behaviour only — no timing was
measured.**

### 2. Results

#### C2 — addresses (this run only; absolute values carry no meaning across runs)

Identical in shape for all five fixtures:

| Question | Observed |
| --- | --- |
| Two consecutive reads on one buffer use the same storage | **yes** — e.g. WAV: `0x…B094040`, `0x…B098040` on both reads |
| `floatChannelData[i]` and `AudioBuffer[i].mData` are the same address | **yes**, for all five |
| Two buffers alive at once get disjoint storage | **yes**, for all five |
| A freshly allocated buffer can land on an address already seen | **yes** — the same address recurred across all four sampled fresh allocations |

#### C2 — the three conditions

| Fixture | 1 · reused, no wipe: tail identical to pre-read | 2 · reused, wiped: tail modified | 3 · fresh buffer: tail all zero | 3 · fresh buffer: tail identical to previous read |
| --- | --- | --- | --- | --- |
| WAV | **true** | false | **true** | false |
| AIFF | **true** | false | **true** | false |
| ALAC | **true** | false | **true** | false |
| FLAC | **true** | false | **true** | false |
| AAC | **false** | **true** | **false** | false |

#### C3 — capacity sweep

Total frames read was **44 100 at every capacity for every format** — complete, and equal to `length`.
`shortMid` (a read shorter than capacity that was followed by another read) was **0 everywhere**: only
the final read was ever short.

| Capacity | Tail existed? | WAV · AIFF · ALAC · FLAC | AAC |
| ---: | --- | --- | --- |
| 1, 2, 3, 7 | **no** | *not evaluated* | *not evaluated* |
| 31 | yes (last read 18) | wiped: not modified · un-wiped: identical to pre-read | wiped: **modified** · un-wiped: **changed** |
| 64 | yes (last read 4) | wiped: not modified · un-wiped: identical to pre-read | wiped: **modified** · un-wiped: **changed** |
| 127 | yes (last read 31) | wiped: not modified · un-wiped: identical to pre-read | wiped: **modified** · un-wiped: **changed** |
| 1 024 | yes (last read 68) | wiped: not modified · un-wiped: identical to pre-read | wiped: **modified** · un-wiped: **changed** |
| 4 096 | yes (last read 3 140) | wiped: not modified · un-wiped: identical to pre-read | wiped: **modified** · un-wiped: **changed** |

Capacities 1, 2, 3 and 7 produced **no tail region at all**, because 44 100 = 2²·3²·5²·7² is divisible
by each of them, so every read filled its capacity exactly. Those cells are **not evaluated** — they
are not evidence that nothing happens.

### 3. Observations

Stated as observations only:

1. A single `AVAudioPCMBuffer` keeps the same storage addresses across consecutive reads.
2. `floatChannelData` and the `AudioBufferList`'s `mData` are the same storage; the two views are not
   separate copies.
3. Two buffers alive at the same time occupy disjoint storage.
4. A freshly allocated buffer may receive an address that a previously released buffer used, and its
   contents nevertheless read as all zero.
5. For WAV, AIFF, ALAC and FLAC, with the buffer wiped before every read, **no modification was
   observed** in `[frameLength, frameCapacity)` at any capacity where that region existed.
6. For WAV, AIFF, ALAC and FLAC, without wiping, that region held **exactly its pre-read contents**.
7. For AAC, with the buffer wiped before every read, **modifications were observed** in that region.
8. For AAC, with a **freshly allocated** buffer — whose equivalent region read as all zero for the
   other four formats — the region was **not** all zero.
9. The AAC observation held at every capacity where a tail existed: 31, 64, 127, 1 024 and 4 096.
10. Total frames read equalled `length` at every capacity for every format, and no read returned fewer
    frames than requested except the final one.

### 4. Compatible hypotheses

Consistent with the evidence; **this gate cannot separate them.**

- **H1 — For the four non-AAC formats, the tail content is entirely storage reuse.** Observations 5, 6
  and 8 fit together with nothing writing there: whatever the caller left behind stays.
- **H2 — For AAC, something in the read path produces samples into the supplied storage beyond the
  count reported in `frameLength`.** Observations 7 and 8 require *some* writer; storage reuse cannot
  put non-zero values into an allocation that reads as zero.
- **H2a — that writer is the packet-based decoder**, emitting a whole packet (1 024 frames for this
  file) regardless of how many frames were requested.
- **H2b — that writer is the internal format conversion**, filling the destination up to its capacity.
- **H2c — both, or an interaction between them.**

**H2a, H2b and H2c are indistinguishable from these observations.** Nothing here inspects the decoder
or the converter separately, and no attempt is made to guess between them. The observation that the
modification appears even at capacity 31 — far below the 1 024-frame packet — neither confirms nor
refutes H2a, because the inspected region is bounded by the capacity we allocated.

### 5. Discarded hypotheses

Each is ruled out by a specific observation, not by argument.

| Hypothesis | Ruled out by |
| --- | --- |
| The AAC tail is explained by **storage reuse** | Observation 8: a freshly allocated buffer, verified to read as all zero in the same condition for four other formats, was **not** all zero for AAC |
| The AAC tail is **residue from the previous read** | Observation 7 (wiped: modified anyway) and the "identical to previous read: false" column in condition 3 |
| The four non-AAC formats also write past `frameLength` | Observation 5: with the buffer wiped, no modification at any capacity where a tail existed |
| `AVAudioPCMBuffer` hands out **dirty memory** | Observation 4: the same address recurred and still read as all zero |
| The behaviour **depends on the chunk size** | Observation 9: per format, identical at 31, 64, 127, 1 024 and 4 096 |
| Allocating a new buffer per read **avoids** the problem | Observation 8: for AAC the fresh buffer's tail was still not zero |
| Reads may return short mid-stream, so `frameLength < frameCapacity` signals the end | Observation 10: `shortMid` was 0 for every format at every capacity — only the final read was short |

### 6. Architectural consequences

Consequences of the observations, not decisions:

- **`frameLength` is the only valid bound, and the reason it matters differs by format.** For four
  formats the tail is stale caller data; for AAC it is content the API did not report. Both are
  plausible-looking audio. A reader that used `frameCapacity` would be wrong in every case, and wrong
  *differently* depending on the file it was handed.
- **"Allocate a fresh buffer each time" is not a mitigation** — it does not clear the AAC case, and it
  would trade a bounded, reusable allocation for one per chunk. The only mitigation observed to work is
  respecting `frameLength`.
- **Reusing one buffer across reads is sound.** Its storage is stable, and distinct buffers do not
  share storage. This supports a single reused buffer as the shape for a bounded reader — relevant to
  experiment I, which has **not** been run.
- **This constrains experiment K before it is designed.** If a PCM chunk value is ever built from one
  of these buffers, it must be built from exactly `frameLength` frames. Copying the capacity would, for
  AAC, carry decoded audio that the API declined to report — silently, and only for some formats.
- **`frameLength < frameCapacity` is not an end-of-stream signal.** Only the final read was ever short,
  but that is an observation about these files, not a contract; combined with gate 1's finding, the
  stopping rule that was actually observed to work remains `framePosition < length`.

**Scope.** Five formats, well-formed fixtures this spike wrote itself, one OS/SDK, one machine, one run.
MP3, damaged files, multichannel and interleaved processing formats were **not** part of this gate.

## Gate 2.75 — Characterisation of post-`frameLength` samples

Gate 2.5 established that, for AAC, **modifications were observed** past `frameLength` and that storage
reuse cannot account for them. This gate characterises **what pattern those samples present** — how
they compare with the valid audio, whether they are reproducible, whether they move with the capacity,
and whether they depend on the audio content.

**No external documentation was consulted.** Every statement below comes from a measurement made here.
What the samples *are* is not asserted; only what they *look like* under objective comparison.

### 1. Methodology

All four experiments allocate a **fresh `AVAudioPCMBuffer` for every read**. Gate 2.5 observed that a
fresh buffer reads as all zero even when the allocator returns a recycled address, so "fresh" gives a
deterministic all-zero baseline. That is what makes a hash of the region meaningful: any non-zero byte
is a modification relative to a known starting state.

- **C4 — pattern.** On the final AAC chunk, take the last 64 valid samples (before `frameLength`) and
  the first 64 samples after it, per channel, and compare them: element-wise equality, maximum absolute
  difference, Pearson correlation, min/max/RMS of each window, the mean absolute step *inside* the
  valid window, and the step *across* the boundary. Classification is mechanical from those numbers,
  with thresholds fixed in advance and stated in the code.
- **C5 — determinism.** Read the same AAC file completely, five times, a fresh buffer every read;
  extract only `[frameLength, frameCapacity)`; serialise it as little-endian float32, channel by
  channel; SHA-256; compare.
- **C6 — capacity sensitivity.** Repeat the final chunk at capacities 31, 32, 33, 63, 64, 65, 127, 128,
  129, 255, 256, 257, 511, 512, 513, 1 023, 1 024, 1 025, recording `frameLength`, the region's length,
  whether modifications appear, its SHA-256, and the C4 classification. Looking for **discontinuities**,
  not performance.
- **C7 — content dependence.** Two AAC files of identical structure (44 100 Hz, 2 ch, 44 100 frames,
  128 kbit/s) and different audio — *alpha* 440/660 Hz at 0.25, *beta* 1 000/1 500 Hz at 0.50 — put
  through C4 and C5.

> **Added during the gate, and flagged as an addition:** C6's table showed *identical hashes whenever
> the region's length matched*, at capacities whose final chunks began at different absolute positions.
> A prefix check was added to settle that objectively rather than leave it as an inference.

### 2. Results

#### C4 — the final AAC chunk (capacity 4 096, `frameLength` 3 140, region 956 frames)

| Metric | Channel 0 | Channel 1 |
| --- | ---: | ---: |
| Region entirely zero | false | false |
| Element-wise identical to the valid window | false | false |
| Max absolute difference | 0.25195915 | 0.24950346 |
| Pearson correlation | −0.100314 | −0.380836 |
| Valid window min / max / **RMS** | −0.249505 / 0.191426 / **0.166783** | −0.248113 / 0.248767 / **0.179502** |
| Region min / max / **RMS** | −0.003204 / 0.002686 / **0.001986** | −0.005970 / 0.002569 / **0.001638** |
| Mean \|Δ\| inside the valid window | 0.01073388 | 0.01438765 |
| \|Δ\| across the boundary | 0.01317459 | 0.01820295 |
| Boundary ÷ mean \|Δ\| | 1.227 | 1.265 |
| **Classification** | **low correlation** | **low correlation** |

The region's RMS is **roughly 1 % of the valid signal's** (0.0020 vs 0.1668; 0.0016 vs 0.1795), while
the step across the boundary is only ≈1.2× the ordinary step inside the valid window.

#### C5 — determinism, five full reads of the same file

| Run | Region frames | Bytes | SHA-256 |
| ---: | ---: | ---: | --- |
| 0–4 | 956 | 7 648 | `82c3e518333fe29db897c61bbddcd5719cba0b7631f08830d20109cafc854360` |

**All five hashes identical.**

#### C6 — capacity sensitivity of the final chunk

| Capacity | `frameLength` | Region frames | Modifications | SHA-256 (first 16) | Classification |
| ---: | ---: | ---: | --- | --- | --- |
| 31 | 18 | 13 | true | `681646aae75cd656…` | low correlation |
| 32 | 4 | 28 | true | `cf9bca1e36be1bdc…` | low correlation |
| 33 | 12 | 21 | true | `f8c85cc5d0c2851f…` | low correlation |
| **63** | 63 | **0** | *not evaluated* | — | *no region existed* |
| 64 | 4 | **60** | true | **`f85c1e48535d8bd0…`** | low correlation |
| 65 | 30 | 35 | true | `181fd6e0f8ec0e6c…` | low correlation |
| 127 | 31 | 96 | true | `417515466565e92f…` | low correlation |
| 128 | 68 | **60** | true | **`f85c1e48535d8bd0…`** | completely different |
| 129 | 111 | **18** | true | **`abac9794967d6f2e…`** | low correlation |
| 255 | 240 | 15 | true | `c42b87bf2bdbc2ea…` | low correlation |
| 256 | 68 | 188 | true | `ed920b7e074dbbfc…` | low correlation |
| 257 | 153 | 104 | true | `7b6a67ec9ec1eb13…` | low correlation |
| 511 | 154 | 357 | true | `fab85a4b892c9530…` | low correlation |
| 512 | 68 | 444 | true | `1f59d8af3cd6dcf3…` | low correlation |
| 513 | 495 | **18** | true | **`abac9794967d6f2e…`** | low correlation |
| 1 023 | 111 | 912 | true | `aa2b28ae3b83bcb2…` | low correlation |
| 1 024 | 68 | 956 | true | `82c3e518333fe29d…` | low correlation |
| 1 025 | 25 | 1 000 | true | `14eb9c92d7310a70…` | high correlation |

Two hash collisions, bolded: **capacities 64 and 128 both produced 60 region frames with the same
hash**, and **capacities 129 and 513 both produced 18 with the same hash** — even though their final
chunks began at different absolute positions (44 096 vs 44 032, and 43 989 vs 43 605).

Capacity **63** divides 44 100 exactly (63 × 700), so no region existed and nothing could be observed.

**The classification column is small-sample noisy and should not be over-read.** The comparison window
is `min(64, frameLength)` wide, so at capacity 1 025 it is only 25 samples. The stable quantities are
the RMS ratio and the hashes, not the label.

#### C6 follow-up — prefix consistency

| Capacity | Region frames | Exact prefix of the longest region |
| ---: | ---: | --- |
| 31 · 32 · 33 · 64 · 65 · 127 · 128 · 129 · 255 · 256 · 257 · 511 · 512 · 513 · 1 023 · 1 024 · 1 025 | 13 · 28 · 21 · 60 · 35 · 96 · 60 · 18 · 15 · 188 · 104 · 357 · 444 · 18 · 912 · 956 · 1 000 | **true, all seventeen** |
| 63 | 0 | — (no region) |

Every region is an exact element-wise prefix of the 1 000-frame region obtained at capacity 1 025.

#### C7 — content dependence

| | SHA-256 of the region |
| --- | --- |
| alpha (440/660 Hz @ 0.25) | `82c3e518333fe29db897c61bbddcd5719cba0b7631f08830d20109cafc854360` |
| beta (1 000/1 500 Hz @ 0.50) | `9efcf0fd64d9ffb80f9b6835168fe616eb946405baa2873d14cac91c54966eeb` |
| **Equal across the two files** | **false** |

Both were deterministic over five runs each. Alpha's hash is **identical to the base fixture's** — a
separately written file carrying the same signal.

| Metric (channel 0) | alpha | beta |
| --- | ---: | ---: |
| Valid RMS | 0.166783 | 0.360356 |
| Region RMS | 0.001986 | 0.002723 |
| Correlation | −0.100314 | 0.463700 |
| Boundary ÷ mean \|Δ\| | 1.227 | 1.380 |

### 3. Observations

1. The region is not zero, and is not element-wise equal to the preceding valid samples.
2. Its RMS is about **1 %** of the valid window's, in both channels, in both content variants.
3. The step across the boundary is ≈1.2–1.4× the mean step inside the valid window — small.
4. Pearson correlation with the preceding window is low and **inconsistent in sign** across channels
   and content (−0.10, −0.38, +0.46, +0.01).
5. Five complete reads of the same file produced **byte-identical** regions.
6. Two separately written files carrying the **same** audio produced byte-identical regions.
7. Two files carrying **different** audio produced **different** regions.
8. Modifications were observed at **every** capacity that left a region — 17 of 18; the eighteenth left
   no region.
9. Regions of equal length taken at different capacities, from final chunks starting at different
   absolute positions, were **byte-identical**.
10. Every observed region is an **exact prefix** of the longest one.

### 4. Compatible hypotheses

Consistent with all ten observations. This gate does not separate them.

- **H1 — The region holds a fixed, content-derived sequence, exposed to whatever length the capacity
  leaves.** Observations 9 and 10 state this almost directly: the content is a function of the region's
  *length* and of the *file*, not of the reading position or the capacity.
- **H2 — That sequence is produced by the decode path from the same file.** Observations 6 and 7 require
  a dependence on the audio; observations 5 and 9 require it to be a function, not a residue.
- **H2a** the packet-based decoder producing frames beyond the count reported; **H2b** the internal
  conversion filling the destination; **H2c** both. **Still indistinguishable**, exactly as at gate 2.5.
- **H3 — The low amplitude is a property of the sequence itself**, not of truncation: ~1 % RMS held in
  both channels of both content variants, and at capacities from 13 to 1 000 frames.

What the sequence *is* — a tail, a decay, padding, overlap, or anything else — is **not** asserted.
Naming it would require evidence this gate does not have.

### 5. Discarded hypotheses

| Hypothesis | Ruled out by |
| --- | --- |
| The region is **random or uninitialised garbage** | Observation 5: five reads, byte-identical. Observation 9: identical across capacities |
| The region is a **repetition of the preceding samples** | Observation 1 (not element-wise equal) and observation 2 (RMS two orders of magnitude lower) |
| The region is **a continuation at the same level** | Observation 2: ~1 % RMS. The mechanical classification never returned *apparent continuation* |
| The region depends on the **capacity** | Observations 9 and 10: same length ⇒ same bytes; every region a prefix of the longest |
| The region depends on **where the final chunk starts** | Observation 9: capacities 64 and 128 begin 64 frames apart and produce identical regions |
| The region is **independent of the audio** (purely mechanical) | Observation 7: different content ⇒ different bytes |
| The region is **specific to one file instance** | Observation 6: two separately written files with identical content produced identical regions |
| The region **only appears at large capacities** | Observation 8: present from capacity 31 upward, wherever a region existed |

### 6. Implications for the design of the future PCM port

Implications of the evidence for a port that does not yet exist. **No architectural conclusion is drawn
here, and none of gate 2.5's consequences is revised.**

- **Determinism does not make the region usable.** It is reproducible, but it is content the API
  declined to report through `frameLength`. A reader that consumed it would be consuming decoded
  samples the file's declared length does not cover — consistently, which makes the error harder to
  notice, not easier.
- **A future chunk value must be built from exactly `frameLength` frames.** Gate 2.5 said this already;
  gate 2.75 sharpens why. The extra samples are not noise that would be visibly wrong in a waveform:
  they are low-level, deterministic and content-derived, so a bug that included them would produce a
  drawing that looks plausible.
- **`frameCapacity`-sized copies are the specific mistake to design against.** Copying a whole buffer
  is the natural, efficient-looking implementation, and it is the one that would silently include this
  region — for some formats only.
- **The region is a stable target for a regression test.** Because it is byte-identical across reads
  and across capacities of the same length, a test can assert that a reader's output is unaffected by
  chunk size, which would fail loudly if a `frameCapacity` copy were ever introduced.
- **Nothing here changes the reading rule.** `framePosition < length` to bound the loop, `frameLength`
  to bound the data.

**Scope.** One codec (AAC), one encoder (Apple's, at 128 kbit/s), one SDK, one machine, fixtures this
spike wrote itself, two content variants. MP3, damaged files, other encoders, other bitrates and other
SDK versions were **not** tested, and stability across any of them is unknown.

### F — Chunk sizes

*Not run.* Gates 2.5 and 2.75 swept capacities for **functional** behaviour only; F is about time and
allocation cost, and nothing about it may be inferred from those tables.

### G — Cancellation

*Not run.*

### H — Empty, truncated, corrupt and unreadable files

*Not run.*

### I — Memory versus duration

*Not run.*

### J — One instance per task (isolation)

*Not run.*

### K — Media → PCM chunks → Analysis: viability and cost

*Not run.* This experiment is an **input to a decision, not a decision.** It must produce: the shape a
`Sendable` chunk would have (planar or interleaved, frames × channels), how many copies and
allocations Swift 6 strict concurrency actually forces when a chunk crosses an isolation boundary,
whether ownership transfer removes them, and what the same reduction costs when it stays inside the
reading adapter instead.

**Nothing here presumes where a PCM type would live.** Whether such a type belongs in
`AudioInspectorDomain` at all is an open question, not an assumption: the domain has never carried a
buffer-shaped value, and that is a boundary decision for ADR-0015 and the waveform change's design.

## Limitations and open questions

*To be written from what the run actually shows.* Known in advance: a single OS/SDK, a single machine,
synthetic fixtures for every format except MP3, and MP3 observed manually rather than in the suite.

## Impact

*To be written after the results.* Expected to touch: **ADR-0003** — its decoding hypothesis is
**referenced, and the ADR is not edited** (ADRs are immutable once Accepted; this evidence resolves
only part of that hypothesis — decoding for an amplitude envelope, not loudness and not every
format); **ADR-0015** — written afterwards, in `Proposed`, citing sections of this report; and the
`add-waveform-visualization` change, which is re-opened afterwards with requirements written from
evidence rather than from a hypothesis.

## Spike code: lifecycle

Same rules as spike 0031. `Spike/validate-native-pcm-decoding` is a sibling SwiftPM package outside
`Sources/`, not linked by the app, not in the productive build graph, not scanned by
`check-boundaries.sh`, importing no domain type and adding no dependency. It must never move into the
productive package, implement a domain port, or import `AudioInspectorDomain`.

**Deletion criterion:** delete once ADR-0015 is written and the waveform change's own tests cover
these observations. Until then, the commands above reproduce the findings.
