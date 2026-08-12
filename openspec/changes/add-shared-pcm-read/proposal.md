## Why

An inspection decodes the same file **three times** today — once for the waveform, once for the
spectrogram, once for the signal level metrics — and would decode it a fourth time to add true peak.
Measured against the real pipeline, that fourth read costs **23.5 % of a FLAC inspection and 23.6 % of
an AAC one** (ten minutes of stereo, Release), and the existing three already spend most of a
compressed inspection decoding the same bytes over and over.

`add-true-peak-measurement`'s group-5 stop rule fired on exactly that number and blocked its own
wiring. ADR-0016 anticipated this moment: it rejected a shared pass at the time but wrote the condition
for revisiting it — *"It remains possible on top of this seam if measurement ever justifies one."* The
measurement now exists.

## What Changes

- **One read of the file feeds the spectrogram, the signal level metrics and true peak.** Each chunk is
  handed to every consumer in turn, on the same task, and each analysis keeps its own accumulator, its
  own model, its own outcome and its own tests.
- **The isolation ADR-0016 protects becomes contract text rather than a side effect of separate
  decoders**: a consumer's failure stops that consumer and nothing else; a decoder failure ends every
  consumer that had not finished, each reporting its own outcome; cancelling the inspection cancels
  everything and lets no partial model escape; the read ends only when every consumer is done.
- **The waveform keeps its own read.** It uses a different port, its accumulator needs frame position
  and throws where the others do not, and migrating it is a separate change (`design.md` §5). Total
  reads go from three — or four with true peak — to **two**.
- **`add-true-peak-measurement` is unblocked** by this change and resumes at its group 6, wiring true
  peak as a consumer of the shared read. Its model, accumulator, methodology and tests are finished and
  are not touched here.
- **ADR-0020** (`Proposed`) records the distinction this rests on: *independent analyses* is the
  invariant, *independent decodes* was the implementation.

## What This Deliberately Does Not Do

- **No change to `AudioDecoding`.** Audited against a "demonstrated incapacity" rule: the port already
  yields one chunk sequence per call, the caller already controls iteration, and nothing in it names an
  analysis. It is untouched, and the sharing is built *on top of* it — the shape ADR-0016 permitted.
- **No change to `PCMChunk`**, whose copy-on-write value semantics already make handing the same chunk
  to several consumers free of any sample copy.
- **No change to any accumulator, domain model or analysis result.** `SpectrogramAccumulator`,
  `SignalLevelMetricsAccumulator` and `TruePeakAccumulator` are consumed exactly as they are.
- **No `PCMConsumer` protocol and no pipeline abstraction.** Three types sharing an `accumulate(_:)`
  is not a reason to write one when their `finish()` returns three unrelated types (`design.md` §7).
- **No concurrency.** Measured, perfect parallelism would save ~0.28 s where sequential sharing already
  recovers ~0.9 s, and it would need actors around three deliberately non-`Sendable` accumulators plus
  a reopened synchronous-callback contract that exists for a sandbox reason (ADR-0010).
- **No PCM buffering.** Decoding once into a retained buffer would make memory scale with duration.
- **No waveform migration**, no new module, no new port, and no change to the report, the export or any
  interface.

## Impact

- Affected capability: a new **`audio-sample-reading`** — how a file's samples are read on behalf of
  several analyses, and what each one is guaranteed regardless of the others. No existing requirement
  is modified: `audio-file-inspection` covers metadata, `audio-signal-level-metrics` covers what a
  level metric is, and neither says anything about how many times the file is read.
- Affected code (when implemented, not in this change): a composition in `AudioInspectorApp` replacing
  `SpectrogramGeneration` and `SignalLevelMetricsGeneration`'s separate reads, and
  `SourceInspectionCoordinator`'s call sequence.
- **Tests that assert the mechanism must be rewritten.** Several script two decoders by call order and
  assert that each operation gets its own decoder instance; under this change they must assert the
  property — one consumer's failure or cancellation leaves the others untouched — instead of the
  arrangement.
