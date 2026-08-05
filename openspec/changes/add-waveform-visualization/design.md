## Context

Nothing in the codebase reads a sample. The pipeline — `AVFoundationAudioFilePropertyReader` →
`InspectAudioFileUseCase` → `InspectionReport` → `ReportView`/JSON — is metadata-level by construction,
and `AudioInspectorAnalysis` is an empty target waiting for a real seam.

Unlike every earlier attempt at this slice, the decoding strategy is **not** a hypothesis. The spike in
`docs/spikes/2026-08-05-native-pcm-decoding-validation.md` (merged in #24, reproducible from `main` —
a clean rebuild regenerates every recorded SHA-256) measured it. This design consumes that evidence
rather than re-deriving it, and its job is to turn each finding into something the **real adapter** can
be held to.

### What the spike established, and what each finding forces

| Evidence (report section) | Consequence for this design |
| --- | --- |
| `AVAudioFile` opened and fully decoded WAV, AIFF, ALAC, FLAC and AAC; `processingFormat` was **identical** for all five — `'lpcm'` float32, 44 100 Hz, planar, 1 frame/packet (A) | One read path serves every format; no per-codec branch |
| Frames read equalled the declared `length` in all five, delta 0, including lossy AAC (A, B) | `length` is usable as the loop bound for these formats |
| Reading past the end threw `Foundation._GenericObjCError 0` — a bridged failure carrying **no `NSError`** — in all five; the guarded `framePosition < length` loop read everything without throwing (B) | The loop **must** be bounded by `length`. EOF is not distinguishable from a real failure by the error value, so "read until it stops" is not implementable |
| The region past `frameLength` is **never** empty: four formats retain the caller's previous contents; for AAC, modifications were observed even in a freshly zeroed buffer (C, gate 2.5) | `frameLength` is the only valid data bound — an explicit invariant, not a convention |
| That region is deterministic, content-derived, ~1 % of the signal's RMS, and identical across capacities for the same length (gate 2.75) | A `frameCapacity`-sized copy would produce a **plausible and wrong** drawing, consistently, and only for some formats. This is the specific mistake to design against |
| A 4-channel fixture kept channel identity and order; no mixing, duplication or loss; error below the 16-bit quantisation step (D) | Per-channel access is sound for the combined envelope |
| Native float PCM round-tripped `-1.5 … +1.5` with **max absolute error 0.0** (E) | Nothing clips or normalises on the way in; the envelope can be honest about amplitude |

**The one thing the spike could not do: MP3.** macOS has an MP3 decoder but no MP3 encoder, so the
spike — which wrote its own fixtures — could not produce one. MP3 is a target format of the project and
the waveform must decode it. This slice closes that gap against the **real adapter**, and until it does,
ADR-0015 does not leave `Proposed`.

## Goals / Non-Goals

**Goals:** establish the sample-reading seam (bounded chunks, cancellation, honest failure); make the
`frameLength` invariant enforceable by tests rather than by discipline; produce a view-independent
amplitude envelope that misrepresents nothing; draw it once beside the report; never let a waveform
failure damage a correct report; close the MP3 evidence gap.

**Non-Goals:** playback, zoom, scrubbing, selection, a time axis, a spectrogram, an FFT, loudness,
peak/RMS or any level metric, persistence or caching, exporting the waveform, batch, and any statement
about what the drawn shape means.

## Decisions

### 1. `AVAudioFile`, behind a domain-owned port

`docs/architecture.md` already names `WaveformGenerating` among the planned ports. It is introduced here
as a small `Sendable` protocol in `AudioInspectorDomain/Ports/`, taking the safe `AudioFileReference`
and returning a domain value type, with a typed `throws` in the domain's own error space. No
`AVAudioFile`, `AVAudioPCMBuffer`, `AVAudioFormat`, `NSError` or `OSStatus` appears in its signature
(ADR-0011).

`AVAssetReader` was rejected: it is annotated `NS_SWIFT_NONSENDABLE`
(`AVFoundation.framework/Headers/AVAssetReader.h:61`), so its whole lifecycle would have to live inside
an actor, and the project forbids `@unchecked Sendable`. `AVAudioFile` is annotated `NS_SWIFT_SENDABLE`
(`AVFAudio.framework/Headers/AVAudioFile.h:28`) — **but that annotation removes the compiler's
objection, not the mutable read cursor.** Two concurrent readers of one instance would interleave and
silently produce a wrong envelope. Each instance is therefore confined to the task that opens it, reads
it and drops it, and is never shared. Like the property reader, the adapter receives the `URL` through
its constructor seam, because the domain reference carries no location (ADR-0010).

### 2. The `frameLength` invariant

**Every read consumes exactly `buffer.frameLength` frames. `frameCapacity` is never used as a data
bound.** This is the design's load-bearing rule, and it is stated here because the failure it prevents
is invisible: the extra samples are low-level, deterministic and content-derived, so including them
produces a drawing that looks entirely plausible.

It is enforced three ways, not one:

- the reduction takes the frame count from `frameLength` at the only place a buffer is read;
- a test asserts that the same file produces **identical** buckets at several chunk sizes — a
  `frameCapacity`-sized read cannot satisfy that, because the surplus differs with the capacity;
- a test reads a file whose final chunk is short and asserts the envelope is unchanged by what the
  buffer's tail happens to contain.

The loop is bounded by `framePosition < length`, never by watching for a zero-length read — the spike
showed a read past the end throws a bare error indistinguishable from a genuine failure.

### 3. Where the reduction lives — Media

`docs/architecture.md` reserves `AudioInspectorAnalysis` for pure DSP, and a per-bucket minimum and
maximum is, strictly, the simplest possible DSP. It goes in **Media** anyway: the alternative means
streaming raw PCM chunks across a domain port to be reduced elsewhere, which needs either a
chunk-shaped port whose only consumer is this reduction, or decoded buffers moving between targets. The
reduction is not a transform over a buffer — it is a **fold performed while reading**, inseparable from
the read. `AudioInspectorAnalysis` stays empty **because no real seam has appeared yet** (ADR-0005,
principle #12), not because the work was hidden elsewhere.

**What overturns this:** the moment a second consumer needs the same decoded stream — the first level
metric, the first FFT — the chunked-decode port becomes a real seam, `AudioDecoding` is introduced, and
the reduction moves to Analysis behind it. Written down so that change is a move, not a rewrite.

### 4. The envelope model

- **Buckets, not pixels.** `n` buckets, each carrying the **minimum** and the **maximum** observed in
  its slice of the file, across **all** channels. The view maps buckets onto whatever width it has;
  resizing never decodes again.
- **Combined across channels — never an average.** Averaging lets opposing phase cancel and draws a flat
  line for a file that is not flat. Not a mono mix, not a downmix, and not named as one anywhere in the
  code, the tests or the UI.
- **No normalisation.** Values stay on the sample scale `[-1, 1]`. Per-file normalisation would make
  amplitude incomparable between files and would quietly become a statement about the recording
  (invariant #4). Values outside the range — which the spike proved survive the read exactly — are
  **kept as read**, not clamped; clipping is a drawing concern.
- **Bucket count:** `min(2048, frameCount)`, so a file shorter than the cap produces no empty bucket.
  2048 is a cap, not a promised resolution: it is not exported, not persisted and not shown.
- **Deterministic mapping, independent of chunk size.** A frame belongs to bucket
  `frameIndex * bucketCount / frameLength` in integer arithmetic, so bucket boundaries are a function of
  the file alone (principle #7). Chunk and bucket boundaries need not align.
- **Unusable frame count ⇒ no envelope, stated.** Pre-sizing buckets needs a total frame count. The
  spike found `length` exact for all five formats it could write, but MP3 is untested; if a format
  reports an absent or non-positive length, this slice produces **no waveform and says so**, rather than
  guessing a duration or growing an unbounded buffer.

### 5. One pass, bounded, cancellable

One pass over the samples, in fixed-size chunks with a reused buffer — the spike observed that a single
`AVAudioPCMBuffer` keeps stable storage across reads and that distinct buffers do not share storage, so
reuse is sound. Peak memory is a function of the chunk size and the bucket count, never of the file
length. `Task.isCancelled` is honoured at chunk boundaries (`docs/concurrency.md`).

The waveform read is a **second open** of the file, separate from the property read. That is deliberate:
the property reader is `AVURLAsset`-based, accepted and in production, and merging the two would couple
a metadata contract to a decoding one for no benefit. **"One pass" is a statement about the samples, not
about the file handle.**

### 6. The security-scoped access window

`SourceInspectionCoordinator.inspect(_:)` acquires access and releases it in a `defer` when it returns
(ADR-0010). The waveform **must** be produced inside that same call; it cannot be produced lazily when
the view appears, because by then the access is gone. The coordinator gains the second read within its
existing window and returns both results. No bookmark, no retained URL, no entitlement change.

This also fixes the ordering: properties first, then samples. A file whose properties cannot be read at
all is not read again for a waveform.

### 7. Beside the report, and neutral on failure

`InspectionReport` is the metadata-level contract behind the JSON export (ADR-0009). A waveform is
neither a technical property nor a warning nor a status, so it does not go inside it — report and JSON
stay identical in meaning.

The consequence is a state change one layer up: `ImportFlowModel.State.report` carries the waveform
alongside the report. Absence is first-class:

| Outcome | What the user gets |
| --- | --- |
| Properties read, samples read | the report as today, plus the drawing |
| Properties read, samples not read | the report exactly as today, plus a plain statement that the waveform is unavailable |
| Global inspection failure | the failed report as today; no waveform attempted, no second error |

A waveform failure **never** emits an inspection warning and **never** degrades `InspectionStatus` —
those belong to the property contract and to the JSON, and a drawing that could not be produced says
nothing about the file's properties.

### 8. Presentation, and the accessibility debt this slice inherits

Drawn with SwiftUI from the bucket values — no bitmap, no image file, no dependency. `FeatureAnalysis`
receives the domain value type and knows nothing about how it was produced.

The accepted presentation requirement applies unchanged, and a waveform sharpens two parts of it:

- **It must not interpret.** No label calling the shape loud, quiet, clipped, dynamic, compressed,
  healthy or damaged; no presentation as a measurement or as evidence about bit depth, encoding or
  integrity.
- **It must not depend on sight.** A drawing cannot be read by an assistive reader, so it carries a
  textual alternative saying what it is — an amplitude envelope of the whole file — and nothing that
  characterises it. Absence is stated in words, not shown as an empty rectangle.

**The report's own manual accessibility validation is still open** — it was deliberately deferred when
`improve-report-presentation` was archived, and is **not** marked done anywhere. Because this slice adds
a new element to that same surface, the pass is done **once, at the end, over the whole report
including the waveform**. Group 7 lists both the waveform's own checks and the inherited ones
explicitly; nothing is pre-marked and no evidence is invented for either.

### 9. Closing the MP3 gap

MP3 is verified **against the real adapter**, not by extending the spike package, and not by asserting
support from `afconvert`, FFmpeg or documentation. The fixture is produced with FFmpeg — already a
declared dev/test-only dependency (ADR-0003) — and the assertion is that
`AVFoundationWaveformGenerator` decodes it and produces an envelope consistent with the signal encoded.

`.github/workflows/ci.yml` runs on `macos-26` and installs no FFmpeg, so a gated test would skip on
every CI run. Two honest outcomes, and the change must land on one of them:

- the fixture can be produced in-test on the development machine and the case is gated — then it is
  **local evidence, explicitly not CI coverage**, and the report and ADR say so; or
- it cannot be automated at all — then the reason is documented precisely and a **reproducible manual
  validation** is performed and recorded, with FFmpeg version, exact command, parameters, SHA-256 and
  observed result.

Either way, **ADR-0015 stays `Proposed` until one of them is actually done.** No claim of MP3 support is
made on any other basis.

### 10. The acceptance fixtures, and how each criterion will be verified

Group 0's criteria cannot pass before the adapter exists, but the **fixtures** they run against can be
built and verified now, and are (`Tests/AudioInspectorKitTests/AudioFixtureSupport.swift`, with its own
tests). Nothing in that support reduces samples or stands in for the adapter: a shadow implementation
would make the acceptance matrix test itself.

#### The format matrix, measured rather than assumed

| Format | Generating API | Works on this platform | External tool | Runs in GitHub Actions | Needs a versioned binary | Status |
| --- | --- | --- | --- | --- | --- | --- |
| WAV PCM | `AVAudioFile(forWriting:)`, `kAudioFormatLinearPCM` | ✅ verified in-test | no | ✅ | no | **automated** |
| AIFF PCM | idem, big-endian | ✅ verified in-test | no | ✅ | no | **automated** |
| ALAC | idem, `kAudioFormatAppleLossless` | ✅ verified in-test | no | ✅ | no | **automated** |
| FLAC | idem, `kAudioFormatFLAC` | ✅ verified in-test | no | ✅ | no | **automated** |
| AAC / M4A | idem, `kAudioFormatMPEG4AAC` | ✅ verified in-test | no | ✅ | no | **automated** |
| **MP3** | **none exists** | ❌ | FFmpeg | ❌ (CI installs none) | would have to | **manual — see below** |

The five automated rows are not a claim: `AudioFixtureSupportTests` writes each one and asserts the
sample rate, channel count and frame count it reads back.

#### MP3, with the evidence upgraded from assertion to measurement

Previous drafts stated that macOS has no MP3 encoder. That is now measured. `afconvert -hf` **does**
list `'MPG3' = MPEG Layer 3` among its file formats, which is easy to misread as encoder support, but
attempting to write one fails:

```
$ afconvert -f 'MPG3' -d '.mp3' src.aiff out.mp3
Error: ExtAudioFileSetProperty ('cfmt') failed ('fmt?')
```

CoreAudio **decodes** MP3 and does not **encode** it, so `AVAudioFile(forWriting:)` has no encoder to
reach either. The four options in order, and where each lands:

1. **Native reproducible generation** — impossible, per the measurement above.
2. **A small versioned fixture** — would put an audio binary in the repository, against
   `docs/testing-strategy.md`, and needs provenance, licence and explicit approval. **Not taken, not
   proposed.**
3. **Optional local generation, explicitly outside CI** — FFmpeg is already a declared dev/test-only
   dependency (ADR-0003) and CI installs none, so a gated test skips on **every** CI run. Viable as
   **local evidence that is not CI coverage**, and must be labelled so.
4. **Reproducible manual validation** — version, exact command, parameters, SHA-256, observed result.

**Task 0.6 keeps options 3 and 4 open and is not closed by this session.** No coverage of MP3 is
claimed anywhere, and FFmpeg becomes neither a production nor a CI dependency.

#### The `frameLength` test, defined precisely

The regression to make impossible is *consuming `frameCapacity` as if it were audio*. The test cannot
be written yet — there is no adapter to call — so what it will observe is fixed here instead:

- **What it observes:** the envelope the adapter returns. Nothing about buffers, no private bytes, and
  **no hash from the spike report**. Those hashes are evidence about one SDK on one machine; treating
  them as a contract would pin the product to an implementation detail of Apple's decoder.
- **How it proves only `frameLength` contributed:** the same file is read at several chunk sizes and the
  envelopes must be **identical**. A reader that consumed the capacity cannot satisfy this, because the
  surplus region differs with the capacity — the spike measured exactly that, and measured that regions
  of equal length are byte-identical while regions of different length are not.
- **How it reuses the AAC case:** AAC is the format where the surplus is not stale caller data but
  content produced by the read path, so it is the one case where a capacity-sized read yields a
  *different* envelope rather than merely an unstable one. The AAC row is therefore the sharp end of
  this criterion, which is why task 0.5 doubles as the regression test for 0.11.
- **Why the fixture size matters:** the frame count is prime
  (`framesWithShortFinalChunkAtAnyChunkSize`), so every chunk size above one leaves a short final
  chunk. With 44 100 frames, capacities 1, 2, 3 and 7 divide evenly and the surplus region never even
  exists — the test would pass while proving nothing.
- **Why it fails if the adapter walks the full capacity:** the last chunk's surplus contributes samples
  that are a function of the capacity, so at least two of the chunk sizes disagree.

#### Chunks, EOF and cancellation

The harness that runs one adapter at several chunk sizes needs the adapter's own signature, so it is
**not** written now — an abstraction over an API that does not exist would be fiction. What the
acceptance must demonstrate is fixed: identical envelopes across chunk sizes; the short final chunk
included; the loop bounded by `framePosition < length` rather than by watching for a zero-length read;
total frames consumed equal to the declared length; cancellation observed at a chunk boundary with no
envelope presented as complete; no file left open; and the source byte-identical afterwards.

The source-integrity helper is deliberately **not** added yet: before the adapter, "writing a fixture
does not modify it" is vacuous, and a helper whose only user is a vacuous test is dead code. It arrives
with the test that needs it.

#### Memory and timing

No benchmark with an absolute threshold on a shared runner. What the suite will assert is what it can
genuinely observe: that reading is chunked, that the full decoded track is never retained, and that the
envelope never exceeds the bucket cap regardless of the file's length — a bound that is a property of
the output, not of the machine. **No claim about resident memory is made from `swift test`.** Any
figure comes from a measured run and is labelled as such. A timing helper, if one is added, is
diagnostic output, never a gate.

## Risks / Trade-offs

- **`frameCapacity` is the natural, efficient-looking implementation, and it is the wrong one.**
  Mitigated by three independent enforcements (§2), because a comment would not survive a refactor.
- **`NS_SWIFT_SENDABLE` invites a race the compiler will not catch.** Mitigated by confining each
  `AVAudioFile` to one task and never sharing an instance.
- **The reduction sits in Media, not Analysis.** Accepted knowingly, with the overturning condition
  written down (§3).
- **A min/max envelope is not a measurement and could be read as one.** Mitigated by the presentation
  rules and by keeping the waveform out of the report and out of the JSON entirely.
- **MP3 may not be automatable.** Handled as an explicit fork in §9, both branches honest; neither
  permits asserting support without evidence.
- **The second read costs time on long files.** Bounded and cancellable; the long-file case is a group-0
  acceptance criterion rather than an estimate.
- **2048 buckets is a guess.** Mitigated by treating it as a cap: not exported, not persisted, not
  promised, so it can change without breaking anything.
- **Inherited accessibility debt is deferred once more.** Accepted deliberately, on the reasoning that
  one pass over the finished surface is better than two over a moving one — but it is now scoped work in
  group 7, not an open item drifting between slices.

## Migration Plan

Additive. No stored data, no schema version, no wire-format change; a report produced before this change
presents identically afterwards, with the waveform area simply absent. The only breaking edit inside the
package is the payload of `ImportFlowModel.State.report`, internal to the flow and covered by existing
tests.

## Open Questions

1. **The chunk size**, chosen from the group-0 measurements rather than from a round number.
2. **Whether MP3 exposes a usable `length`** — unknown, and the only formats measured are the five the
   spike could write.
3. **Whether the secondary technical detail beside the drawing adds value** — a density question left to
   implementation with the code in hand; either answer satisfies the requirement.

None blocks the port's shape, so groups 1 to 3 can be specified now and only their constants wait on
group 0.
