# ADR-0015: Native PCM sample reading — `AVAudioFile` behind a domain port, bounded by `frameLength`

- **Status**: **Proposed.** It stays Proposed until two things are true: the format matrix passes
  against the **production** adapter with **MP3 resolved** (change `add-waveform-visualization`, group 0,
  task 0.6), and the manual accessibility validation of the resulting surface is performed (group 7).
  Partial evidence does not promote it.
- **Date**: 2026-08-05
- **Deciders**: Project maintainer
- **Related**: **ADR-0003** (native-first strategy; its decoding hypothesis — *referenced, not edited*),
  ADR-0005, ADR-0009, ADR-0010, ADR-0011, `docs/spikes/2026-08-05-native-pcm-decoding-validation.md`,
  `docs/architecture.md`, `docs/concurrency.md`, change `add-waveform-visualization`

## Context

Everything the product promises beyond metadata — a waveform, levels, loudness, spectra — reads decoded
samples. Nothing in the codebase does yet, so the seam that reads them is about to be created once and
depended on by every later analysis. Getting it wrong is expensive to undo.

**ADR-0003** adopted a native-first strategy but recorded its own sufficiency as an open hypothesis:
*"its technical sufficiency is unproven"*, pending a spike over real and synthetic fixtures. That spike
has now been run and its evidence is in the repository, reproducible from `main`: a clean rebuild of
`Spike/validate-native-pcm-decoding` regenerates every SHA-256 recorded in the report.

Two candidate APIs exist, and the Swift 6 concurrency rules separate them sharply:

- `AVAudioFile` is annotated `NS_SWIFT_SENDABLE` (`AVFAudio.framework/Headers/AVAudioFile.h:28`) and
  converts automatically from the file's format to a requested processing format.
- `AVAssetReader` is annotated `NS_SWIFT_NONSENDABLE`
  (`AVFoundation.framework/Headers/AVAssetReader.h:61`), so its entire lifecycle would have to be
  encapsulated in an actor. The project builds under Swift 6 complete checking and forbids
  `@unchecked Sendable` (`docs/concurrency.md`).

The spike also produced a finding about `AVAudioPCMBuffer` that constrains any reader, whichever API it
uses (report sections C, gate 2.5, gate 2.75):

- The region between `frameLength` and `frameCapacity` is **never** empty. For WAV, AIFF, ALAC and FLAC
  it retains whatever the caller left there. For AAC, modifications were observed in that region **even
  in a freshly allocated, verified-zero buffer**, so storage reuse cannot account for them.
- That content is **deterministic** (five reads of one file produced byte-identical regions),
  **content-derived** (two files with different audio produced different regions; two files with
  identical audio produced identical ones), independent of the reading position, and roughly **1 % of
  the signal's RMS**. Every region observed is an exact prefix of the longest one.
- What mechanism produces it was **not** identified, and this ADR does not claim to know. The decoder
  and the internal conversion remain indistinguishable on the evidence available.

## Decision

**Read decoded PCM with `AVAudioFile`, behind a domain-owned port, consuming exactly `frameLength`
frames per read, and perform the reduction in `AudioInspectorMedia`.** Concretely:

1. **`AVAudioFile`, not `AVAssetReader`.** The uniform processing format it produced across every format
   measured — `'lpcm'` float32, planar — means one read path serves them all, and it carries no
   `Sendable` encapsulation cost.

2. **`NS_SWIFT_SENDABLE` is not a licence to share.** `AVAudioFile` owns a mutable read cursor
   (`framePosition`), so two concurrent readers of one instance would interleave and silently produce a
   wrong result — a race the compiler will no longer object to. **Each instance is confined to the task
   that opens it, reads it and drops it, and is never shared.**

3. **`frameLength` is the only valid data bound; `frameCapacity` is never used as one.** This is an
   explicit invariant, enforced by tests rather than by convention, because the failure it prevents is
   invisible: the surplus samples are low-level, deterministic and content-derived, so consuming them
   yields output that looks entirely plausible and is wrong — and wrong only for some formats.

4. **The loop is bounded by `framePosition < length`.** Reading past the end threw
   `Foundation._GenericObjCError 0` — a bridged failure carrying **no `NSError`** — in all five formats
   measured, so end-of-file is not distinguishable from a genuine failure by the error value. A
   "read until it stops" loop is not implementable against this API.

5. **The processing format is verified, never assumed.** Before reading a sample, the adapter checks
   that the format is native deinterleaved float (`AVAudioFormat.isStandard`, documented as *"whether
   the format is deinterleaved native-endian float"*), and fails in a controlled way if it is not.
   This is not defensive habit: `AVAudioBuffer.h:143-150` states that on an **interleaved** buffer the
   per-channel pointers *"refer into the same chunk of interleaved samples, each offset by 1 frame"*,
   with `stride` equal to the channel count. Treating such a pointer as one channel's contiguous run
   would read samples from every channel, cover a fraction of the frames, and produce a **wrong
   envelope while tripping none of the reduction's invariants** — every value is finite, the frame
   range still fits, and every bucket still receives samples. The spike measured planar for the five
   formats it could write; a measurement over five files is not an API guarantee, and this is the one
   place the mistake can be caught.

6. **The port belongs to the domain and no Apple type crosses it** (ADR-0011). The adapter translates
   platform shapes and errors into domain values, classifying by **scope**, never by SDK numeric code.
   The `URL` reaches the adapter through its constructor seam, because the domain reference carries no
   location (ADR-0010).

7. **The reduction lives in `AudioInspectorMedia`, not `AudioInspectorAnalysis`.** A per-bucket minimum
   and maximum is a fold performed *while reading*, inseparable from the read, not a transform over a
   buffer. `AudioInspectorAnalysis` stays empty because no real seam has appeared yet (ADR-0005,
   principle #12) — **not** because work was hidden elsewhere.

## Alternatives considered

- **`AVAssetReader` in an actor.** Gives explicit control over the output format and is the natural
  fallback if `AVAudioFile` were found insufficient. Rejected for now: `NS_SWIFT_NONSENDABLE` forces the
  whole lifecycle — `startReading`, `copyNextSampleBuffer`, `cancelReading` — inside an actor, and the
  ban on `@unchecked Sendable` leaves no cheap escape. It buys control this slice does not need. **It
  remains the designated fallback** if a format is later found that `AVAudioFile` cannot serve.
- **Trusting `frameCapacity` and clearing the buffer between reads.** Simpler, and it would work for
  four of the five formats measured. Rejected: for AAC the region was modified even in a
  freshly-zeroed buffer, so clearing does not make it safe — and the resulting error would be silent.
- **Allocating a fresh buffer per read.** Rejected on the same evidence, at a higher cost: it does not
  clear the AAC case and it trades one bounded, reusable allocation for one per chunk.
- **Streaming raw PCM chunks across a domain port and reducing in `AudioInspectorAnalysis`.** The
  architecturally "purer" placement. Rejected *now* because it requires either a chunk-shaped port whose
  only consumer is this reduction, or decoded buffers moving between targets — a seam with one user is
  a speculative abstraction (principle #12). **See Follow-ups for exactly what would overturn this.**
- **FFmpeg for decoding.** Rejected by ADR-0003 for the shipped binary; nothing here revisits that.
  FFmpeg's only role is producing an MP3 fixture that macOS cannot encode, as a dev/test-only tool.

## Consequences

### Positive

- One read path serves WAV, AIFF, ALAC, FLAC and AAC with no per-codec branch.
- No actor is needed for the reader, and no `@unchecked Sendable` anywhere.
- The pure core stays framework-free and fully testable with a fake port; the adapter is swappable.
- The `frameLength` invariant is stated once, enforced by tests, and its rationale is recorded — so a
  future refactor that "simplifies" it fails loudly instead of silently.

### Negative / costs

- **MP3 is unverified at the time of writing.** macOS cannot encode MP3, so the spike could not produce
  a fixture, and no claim of MP3 support is made here. This is the specific reason the ADR is Proposed.
- **The `frameLength` rule is easy to break and hard to notice.** The wrong implementation is the
  natural-looking one, and its output is plausible. It costs three separate test enforcements.
- **The reduction sits outside Analysis**, which will require a move once a second consumer appears.
- **One OS/SDK, one machine.** Numeric error codes are SDK-dependent; only the semantic conclusions carry
  forward. Damaged files, cancellation, bounded memory and multi-format long files were left to the
  slice's own tests rather than the spike, so they are asserted against real code — not yet asserted at
  the time of writing.
- **A second file open per inspection.** The property reader stays `AVURLAsset`-based; "one pass" is a
  statement about the samples, not about the file handle.

### Neutral

- Establishes the pattern for every future sample-reading capability: domain-owned port, platform code
  and error translation confined to `AudioInspectorMedia`, `frameLength` respected everywhere.
- ADR-0003's hypothesis is **partially** resolved — decoding to an amplitude envelope, for five formats,
  on one SDK. Loudness, spectral analysis and MP3 are not covered by this evidence.

## Follow-ups

- **Promotion criteria** (see Status): group 0 of `add-waveform-visualization` passing with MP3 resolved,
  plus the manual validation in group 7. Until then this ADR asserts a direction, not a proven result.
- **What overturns decision 7:** the first level metric or the first FFT needs the same decoded stream.
  At that point the chunked-decode port becomes a real seam, `AudioDecoding` is introduced, and the
  reduction moves to `AudioInspectorAnalysis` behind it. That change should be a move, not a rewrite.
- **`Spike/validate-native-pcm-decoding` is deleted** once this ADR is Accepted and the slice's own tests
  cover its observations; the deletion criterion is written into the spike report.
- ADR-0003 is **not** edited. If its sufficiency hypothesis is ever fully resolved, that belongs to a
  future ADR that supersedes it, per the immutability rule in `docs/adr/README.md`.
