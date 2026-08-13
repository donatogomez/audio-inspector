# ADR-0021: One PCM read per inspection — the waveform joins the shared read

- **Status**: **Proposed.** It stays Proposed until two things are true against production code: the
  saving is reproduced by the real pipeline (change `share-waveform-pcm-read`, group 7), and the
  equivalence and isolation properties are each demonstrated by a test that fails when the property is
  broken (groups 4 and 5). Partial evidence does not promote it.
- **Date**: 2026-08-13
- **Deciders**: Project maintainer
- **Related**: **ADR-0020** (whose decision 6 this revisits — *referenced, never edited*), **ADR-0016**
  (which scheduled this migration as conditional and last rather than prohibiting it), ADR-0010,
  ADR-0011, ADR-0015, change `share-waveform-pcm-read`,
  `docs/spikes/2026-08-12-shared-pcm-analysis-architecture.md` §7

## Context

ADR-0020 decision 6 reads: *"The waveform stays on its own read for now. It uses a different port, its
accumulator needs frame position and throws where the others do not, and ADR-0016 deliberately left its
migration undone. Including it means migrating it first — two risky things in one change."* Its
follow-ups then name the migration as *"the obvious next reduction once this lands, taking two reads to
one. Nothing here authorises it."*

**This record is that authorisation, and it is needed precisely because ADR-0020 is `Accepted`.**

Two things are worth stating plainly, because both are easy to get wrong from memory:

- **ADR-0016 did not reject this migration.** It rejected *a single pass producing waveform and
  spectrogram together* (decision 15) and made the waveform's move onto the seam *conditional and last*
  (its alternatives section, and `add-static-spectrogram-visualization` group 9's stop rule). The
  deferral being revisited here is ADR-0020's.
- **The recorded blocker was about a different shape.** `WaveformDecodingSeamMigrationTests` pins it as
  executable assertions: two `AudioDecodingErrorCode` values — `invalidStreamDescription` and
  `invalidChunk` — have no honest `WaveformErrorCode` counterpart, and group 9 required the waveform's
  error space to stay unchanged. That is a blocker for **reimplementing `WaveformGenerating` on top of
  `AudioDecoding`**, which is one shape among several.

## Decision

1. **The waveform becomes a consumer of the shared read, not an adapter over the port.** It is fed the
   same `PCMChunk`s as the spectrogram, the signal level metrics and true peak, and reports its own
   outcome exactly as they do. An inspection reads the file's samples **once**.

2. **This is why the recorded blocker dissolves rather than being argued around.** A consumer never
   translates `AudioDecodingError` into `WaveformError`: the shared composition already turns a producer
   failure into a per-consumer `.failed(message:)` carrying a human sentence, as it does for the other
   three. The waveform's error space is **not changed** — it stops being on the path between the decoder
   and the outcome. `WaveformError` remains the accumulator's own space.

3. **Nothing the audit could have justified changing is changed.** `AudioDecoding`, `PCMChunk` and
   `WaveformEnvelopeAccumulator` are untouched: `chunk.startFrame` is *already* the absolute frame the
   accumulator asks for, `chunk.channels[c]` is *already* a contiguous planar run, and
   `PCMStreamDescription` already carries the frame and channel counts it needs at construction. An
   audit that finds no incapacity is a reason to leave a port alone (ADR-0020 decision 4).

4. **`WaveformGenerating` and its AVFoundation adapter are retired.** Their only remaining purpose was
   owning a read that no longer happens. A port kept alive with no caller is worse than no port: it
   invites a second read to be reintroduced without a decision. This is the largest and riskiest part of
   the change, because several tests script that seam and assert an *arrangement* rather than a
   *property*.

5. **A throwing consumer does not become everyone's problem.** The waveform's accumulator is the only
   one that throws. With the two guards the composition already applies, three of its five errors are
   unreachable from a valid chunk — `channelOutOfBounds`, `frameRangeOutOfBounds` and `nonFiniteSample`,
   the last because `PCMChunk` refuses non-finite samples at construction. The reachable ones arise at
   `finish` and become the **waveform's own** failure, leaving the other three settling exactly as they
   would have.

6. **The absence/failure distinction is preserved explicitly.** A stream whose frame count cannot be
   mapped to buckets is reported as `.unavailable` — the file offered nothing to size an envelope
   against — and never as a failure. The legacy port expressed this by returning `nil`, and losing it
   in the move would be a silent regression.

7. **Equivalence is bit-exact for lossless containers and within a tolerance for lossy ones, and that
   asymmetry is measured rather than chosen.** Ten minutes of stereo, 2048 buckets: WAV and FLAC come
   out **bit-identical**; AAC differs in **1778 of 2048 buckets by about one ULP**. The fold is the same
   code in both cases, so the difference is in the decode — the legacy generator reads with
   `read(into:)`, the shared decoder with `read(into:frameCount:)`, and the platform's lossy decoder does
   not return identical samples for a different read granularity. A test demanding bit-exactness on AAC
   would assert something the platform does not offer.

8. **How the run is handed over is part of this decision, not an optimisation.** Passing
   `chunk.channels[c]` — the `[Float]` itself — to `accumulate(_:ofChannel:startingAtFrame:)` costs
   **3.79–3.81 s** for ten minutes of stereo, against **0.28–0.33 s** for an `UnsafeBufferPointer` view
   of the same array: a **12× penalty**, constant across all three formats and therefore per-sample
   rather than decoding-related. Written the obvious way, this migration would make the pipeline about
   **2.5× slower** rather than faster. The pointer form is what the legacy generator already used.

9. **No PCM is buffered and no abstraction is introduced.** Memory stays a function of chunk plus
   accumulator state. `SharedPCMAnalysisOutcome` gains a fourth field; there is no `PCMConsumer`
   protocol, for the reason ADR-0020 recorded and one more — a throwing consumer makes the
   associated-type machinery larger, not smaller.

## Alternatives considered

- **Keep the waveform's own read (ADR-0020's mechanism, unchanged).** Simplest, zero migration risk.
  Rejected on the measurement: it is the last redundant decode, worth 0.41 s on FLAC and 0.39 s on AAC
  for a ten-minute file, and the deferral's stated reason — "two risky things in one change" — no longer
  applies now that the shared read is in production and proven.
- **Reimplement `WaveformGenerating` over `AudioDecoding`.** The shape ADR-0016 originally imagined.
  Rejected: it must translate two decoding faults the waveform's error space cannot state honestly,
  which is exactly what `WaveformDecodingSeamMigrationTests` blocks — and it would keep a port whose
  only job was owning a read.
- **Give `WaveformEnvelopeAccumulator` a `PCMChunk`-shaped API.** Tempting because the other three take
  a chunk. Rejected: it would change a domain value type to suit one caller and discard the per-run
  generality its order-independence contract is built on, for no measured gain.
- **A generic `PCMConsumer` abstraction.** Rejected again, and more strongly than in ADR-0020: four
  unrelated `finish()` types, one of which throws.
- **Deleting `WaveformDecodingSeamMigrationTests` along with the blocker.** Rejected: the tests are the
  record of why the deferral happened. They are rewritten to assert what unblocked it, so the reasoning
  survives the change that ended it.

## Consequences

### Positive

- **One read of the file per inspection**, which is what the shared seam was built to reach. Adding a
  sample-based analysis has cost no extra read since ADR-0020; now no analysis keeps one either.
- Measured saving: **0.41 s (FLAC) and 0.39 s (AAC)** on ten minutes of stereo in Release, roughly a
  fifth of the two-read pipeline.
- One fewer file open inside the security-scoped window, and one fewer place that could reintroduce a
  private read.

### Negative / costs

- **WAV gains almost 0.02 s**, which is nothing. The saving is real exactly where decoding is expensive,
  and this record does not dress that up.
- **The test surface that scripts the waveform generator is large**, and several of those tests assert
  an arrangement rather than a property. Rewriting them is where a guarantee could quietly get weaker —
  the same risk ADR-0020 named for itself, and it is the main reason this change is not small.
- **A behaviour change on a malformed file.** Where the legacy loop silently trimmed frames delivered
  beyond the declared length, the shared read refuses them. Stricter on purpose, and recorded rather
  than smuggled in as equivalence.
- **AAC equivalence is a tolerance, not an identity**, so a future reduction bug of about one ULP would
  hide inside it on that format. Lossless formats keep the bit-exact assertion that would catch it.
- **One OS/SDK, one machine.** The timings do not carry forward; the semantic conclusions do.

### Neutral

- No module boundary moves, no port gains a method, no domain type changes, no export change, no visual
  change, and `schemaVersion` stays 1.
- ADR-0020 remains in force in every other respect, including its isolation properties, its rejection of
  buffering and its measured ceiling for concurrent fan-out.

## Follow-ups

- **Promotion criteria** (see Status): the saving reproduced against production code, and the
  equivalence and isolation properties each demonstrated by a test that fails when the property is
  broken.
- **Confirm the mechanism behind decision 8's 12× penalty.** Generic specialisation across the module
  boundary is the hypothesis; the mitigation is required either way, but the explanation should be
  recorded rather than left as folklore.
- **Concurrent fan-out** stays where ADR-0020 left it: available, with a measured ceiling, reopened only
  on evidence. A fourth consumer does not by itself change that arithmetic.
