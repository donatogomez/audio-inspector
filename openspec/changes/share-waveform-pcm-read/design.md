# Design — the waveform as the fourth consumer of the shared read

Everything below was established by reading the code and by measurement on this machine, before any
implementation. A temporary probe produced the figures and the equivalence result and was deleted.

## 1. What the waveform needs, and whether the shared read already supplies it

`WaveformEnvelopeAccumulator` needs three things per run — `samples`, `ofChannel:`, `startingAtFrame:` —
and two at construction: `totalFrameCount` and `channelCount`.

| It needs | The shared read already has |
| --- | --- |
| `totalFrameCount` | `PCMStreamDescription.frameCount`, handed to `prepare(for:)` |
| `channelCount` | `PCMStreamDescription.channelCount`, same place |
| `samples` per channel | `chunk.channels[c]` — planar by construction, contiguous, file order |
| `startingAtFrame` | `chunk.startFrame` — **absolute**, counted from the start of the file |

**`startFrame` is not an approximation of what the waveform wants; it is the same number.** The legacy
generator passes `framesRead`, a running count of consumed frames starting at 0; the decoder passes
`framesDelivered`, a running count of delivered frames starting at 0. On a file that reads as it
declares, they are equal at every step.

**Nothing needs adding to `PCMChunk`, `AudioDecoding` or `WaveformEnvelopeAccumulator.`** The audit
found no incapacity, which is the same finding `add-shared-pcm-read` made about the port.

## 2. The two differences that are real, and what each one costs

**a. An unusable frame count.** The legacy generator calls
`usableFrameCount(_:maximumBucketCount:)`, which also refuses a count the bucket mapping cannot be
built for, and returns `nil` → `.unavailable`. The decoder's `usableFrameCount(_:)` has no such clause.
So a stream whose frame count exceeds `Int.max / maximumBucketCount` would fail to build a waveform
accumulator inside the shared pass. **It must fault to `.unavailable`, not `.failed`** — an absence
caused by the file, which is the distinction the port's documentation exists to protect. Reachable only
for a frame count above ~9.2 × 10¹⁵, so it is a correctness detail rather than a practical one, and it
is cheap to preserve.

**b. Over-read.** The legacy loop clamps `usable = min(valid, frameCount - framesRead)` and silently
trims anything beyond the declared length; the decoder refuses it (`readFailed`). On such a file the
waveform would go from a quietly trimmed envelope to a failure. That is **stricter, deliberately**:
`AVFoundationAudioDecoder` already documents the clamp as the mistake that makes a wrong bound
unobservable. Recorded as an intended behaviour change, not smuggled in as equivalence.

## 3. Why the recorded blocker does not apply to this shape

`WaveformDecodingSeamMigrationTests` pins the reason the migration was deferred: two
`AudioDecodingErrorCode`s — `invalidStreamDescription` and `invalidChunk` — have no honest
`WaveformErrorCode` counterpart, and group 9's stop rule required the waveform's error space to stay
unchanged.

**That blocker is about reimplementing `WaveformGenerating` over `AudioDecoding`** — translating one
error space into another. The shape here does not translate anything: the waveform becomes a consumer
of the shared pass, and the shared pass already turns a producer failure into a per-consumer
`.failed(message:)` with a human sentence, exactly as it does for the other three. **No
`AudioDecodingError` ever needs a `WaveformErrorCode`, so the waveform's error space is not changed —
it simply stops being on the path between the decoder and the outcome.**

`WaveformError` remains the accumulator's own error space, thrown and handled inside the composition.

## 4. Error isolation

The waveform's accumulator is the only consumer that **throws**. Which of its errors are reachable from
a valid `PCMChunk`, given the two guards the composition already applies
(`chunk.channelCount == stream.channelCount` and `chunk.fits(stream)`)?

| Error | Reachable? |
| --- | --- |
| `channelOutOfBounds` | **No** — the accumulator is built with `stream.channelCount` and the chunk is guarded to match |
| `frameRangeOutOfBounds` | **No** — `chunk.fits(stream)` and `totalFrameCount == stream.frameCount` |
| `nonFiniteSample` | **No** — `PCMChunk` refuses non-finite samples at construction |
| `incompleteCoverage` (`finished()`) | **Yes** — a read that stopped early leaves buckets uncovered |
| `invalidConfiguration` (`finished()`) | **Yes** — defensive, on a bucket/frame mismatch |

So the reachable failures are at `finish` time, and they map to **the waveform's own `.failed`**,
leaving the other three untouched. A throw during accumulation faults the waveform alone and the read
continues — the property `SharedPCMAnalysisGeneration` already implements for its consumers, extended
to one that can throw.

## 5. Cancellation

Unchanged, and deliberately not reopened: global cancellation cancels the read and **every** consumer,
each reporting `.cancelled`, and no partial model escapes. The waveform already reports `.cancelled` as
its own outcome, so it joins the existing rule rather than adding a case to it.

## 6. The outcome

`SharedPCMAnalysisOutcome` gains a fourth field. Four fields on a struct the coordinator destructures
immediately is still a composition, not an aggregate: it carries no combined value and nothing
downstream can ask a question about the analyses together.

**No `PCMConsumer` protocol, no `AnyPCMConsumer`, no pipeline framework.** ADR-0020 already rejected the
protocol on the grounds that four `finish()` results are unrelated types with unrelated optionality
rules; the waveform is a fourth such type, and it *throws*, which makes the associated-type machinery
larger rather than smaller. Concrete composition stays.

## 7. Equivalence — measured, and it is not uniform

Ten minutes of stereo, 44.1 kHz, envelope of 2048 buckets, comparing the legacy generator's envelope
against one folded from `PCMChunk`s of the same file:

| format | result |
| --- | --- |
| WAV | **bit-identical**, 0 of 2048 buckets differ |
| FLAC | **bit-identical**, 0 of 2048 buckets differ |
| AAC | **1778 of 2048 buckets differ**, by about one ULP (e.g. −0.5088052 vs −0.50880533) |

The fold is the same code in both cases, so the difference is in the decode: the legacy generator reads
with `read(into:)` and the shared decoder with `read(into:frameCount:)`, and the platform's **lossy**
decoder does not return bit-identical samples for a different read granularity. Lossless formats do.

**So the equivalence criterion is derived, not chosen: bit-exact for lossless containers, and within a
stated tolerance for lossy ones.** A test demanding bit-exactness on AAC would be asserting a property
the platform does not offer. The tolerance must be tight enough to catch a real reduction bug — one ULP
is far below the envelope's own drawing resolution — and it must be justified in the test rather than
widened until it passes.

## 8. Performance — and the one result that changes the implementation

Ten minutes of stereo, Release, minimum of three runs on an otherwise idle machine, measured through
the real decoder and the real accumulators.

| format | decode only | waveform own read | shared (3) | **today (2 reads)** | **shared (4)** | **saving** |
| --- | --- | --- | --- | --- | --- | --- |
| WAV | 0.053 s | 0.330 s | 0.857 s | **1.187 s** | **1.169 s** | **0.018 s** |
| FLAC | 0.444 s | 0.719 s | 1.279 s | **1.998 s** | **1.589 s** | **0.409 s** |
| AAC | 0.532 s | 0.678 s | 1.608 s | **2.286 s** | **1.895 s** | **0.391 s** |

The saving is the eliminated decode, as predicted, and it is material exactly where decoding is
expensive. WAV gains almost nothing, and this design does not pretend otherwise.

**The result that matters most is not in that table.** How the chunk's samples are handed to
`accumulate(_:ofChannel:startingAtFrame:)` changes the cost by **12×**:

| how the run is passed | waveform fold, 10 min stereo |
| --- | --- |
| `chunk.channels[c]` — the `[Float]` itself | **3.79–3.81 s** |
| `withUnsafeBufferPointer` view of the same array | **0.28–0.33 s** |

The penalty is constant across all three formats, so it is per-sample and unrelated to decoding. Passed
the obvious way, migrating would make the pipeline roughly **2.5× slower**, not faster. The
`UnsafeBufferPointer` form is what the legacy generator already uses, and it is a requirement of this
design rather than an optimisation. The mechanism — most likely a generic that is not specialised
across the module boundary — is to be confirmed during implementation, not assumed.

## 9. Memory and the security scope

No PCM is retained: the waveform folds each chunk and keeps two `[Float]` of `bucketCount` (2048 by
default), independent of duration. Nothing is materialised, nothing is deep-copied — the same
`PCMChunk` value is handed to each consumer, and `withUnsafeBufferPointer` borrows rather than copies.
The security scope is unchanged and in fact **shortened**: one read instead of two, still entirely
inside the window `SourceInspectionCoordinator` holds, and the waveform stops being the thing that
opens the file a second time.

## 10. Alternatives

| | | |
| --- | --- | --- |
| **A** | Status quo, two reads | Rejected: it is the last redundant decode, worth ~0.4 s on the formats this product exists to examine. |
| **B** | **Waveform as a fourth consumer of the shared pass** | **Chosen.** Smallest change that removes the read: no port change, no domain change, no new abstraction, and it sidesteps the recorded error-space blocker entirely. |
| **C** | Make `WaveformGenerating` an adapter over `AudioDecoding` | Rejected: it keeps a port whose only purpose was owning a read, and it is precisely the shape the deferral's tests block — it must translate `invalidStreamDescription` and `invalidChunk` into a space that cannot say them. |
| **D** | Give `WaveformEnvelopeAccumulator` a `PCMChunk`-based API | Rejected: it changes a domain value type to suit one caller and discards the per-run generality its order-independence contract is built on. B needs none of it. |
| **E** | A generic `PCMConsumer` abstraction | Rejected, for the reason ADR-0020 already recorded, and more strongly: a throwing consumer makes the associated-type machinery worse. |

## 11. What this design does **not** decide

- Whether `WaveformGenerating` is deleted in this change or left unused for one release. The proposal
  says deleted; the risk is the test surface that scripts it, and that is sized in `tasks.md`.
- Whether the 12× fold penalty has the cause hypothesised in §8. The mitigation is required either way;
  the explanation is to be confirmed.
