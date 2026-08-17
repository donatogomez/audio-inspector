## Why

An inspection still decodes the file **twice**: once for the waveform, once for the shared pass that
feeds the spectrogram, the signal level metrics and true peak. The waveform's own read is the last
redundancy, named as a follow-up by ADR-0020 rather than as an oversight.

Measured against production code on this machine (ten minutes of stereo, Release, minimum of three
runs), removing it saves **0.41 s on FLAC and 0.39 s on AAC** — about a fifth of the two-read
pipeline — and **0.02 s on WAV**, where a decode was nearly free anyway.

The deferral was recorded as executable assertions rather than prose, and those assertions are about a
specific shape: reimplementing `WaveformGenerating` on top of `AudioDecoding` would have to translate
two decoding faults the waveform's error space cannot say honestly. That blocker does not apply to the
shape proposed here.

## What Changes

- **The waveform becomes the fourth consumer of the shared read**, exactly as true peak became the
  third: a field in the composition, a field in the outcome, and its own accumulator, failure and
  reported outcome. One read of the file per inspection, total.
- **The waveform's observable behaviour does not change.** Same envelope, same bucket count, same
  three-way distinction between an empty answer, an absence and a failure, same absence of any effect
  on the report, the export or the inspection status.
- **`WaveformGenerating` and its AVFoundation adapter are retired**, because the coordinator stops
  calling them and dead ports are worse than no ports. `WaveformEnvelopeAccumulator`, `WaveformEnvelope`,
  `WaveformBucketMapping` and `WaveformError` are untouched — the reduction's rules are exactly what
  this change keeps.
- **The deferral's own tests are rewritten to record what actually unblocked it**, rather than deleted.

## Impact

- Affected specs: `audio-sample-reading` (one requirement modified — the read serves *every*
  sample-consuming analysis, not only those that consume whole chunks).
- Affected code: `SharedPCMAnalysisGeneration`, `SourceInspectionCoordinator`, and the removal of
  `WaveformGenerating`/`AVFoundationWaveformGenerator`/`FakeWaveformGenerating`. No domain value type
  changes, no `AudioDecoding` change, no `PCMChunk` change, no export change, no UI change, and
  `schemaVersion` stays 1.
- **A new ADR is required.** ADR-0020 decision 6 is `Accepted` and says the waveform stays on its own
  read; revisiting it is a decision, not an implementation detail.
