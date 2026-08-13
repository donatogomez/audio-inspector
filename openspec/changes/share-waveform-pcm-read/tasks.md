# Implementation Tasks

Investigation is done and its results live in `design.md`. Everything below is implementation, and the
order is chosen so the risky part is provable before the irreversible part happens.

## 1. Decide the record before writing code

- [x] 1.1 **ADR-0021** written, revisiting **ADR-0020 decision 6** ("the waveform stays on its own read
      for now"). It is `Accepted`, so this is a decision and not an implementation detail; ADR-0020 is
      referenced, never edited. It carries the measured saving, the equivalence result including its AAC
      caveat, the 12× fold penalty, and why the recorded blocker was about a different shape.
- [x] 1.2 Recorded explicitly that **ADR-0016 did not prohibit this migration**: it scheduled it as
      conditional and last, and the deferral being revisited is ADR-0020's.
- [ ] 1.3 Promote ADR-0021 from `Proposed` once its own two criteria are met — the saving reproduced
      against production code (group 7) and each property demonstrated by a test that fails when broken
      (groups 4 and 5). Partial evidence does not promote it.

## 2. Feed the waveform from the shared read

- [ ] 2.1 Add `WaveformEnvelopeAccumulator` to `SharedPCMAnalysisGeneration.Consumers`: one stored
      property, one fault, one line in `prepare`, `accumulate`, `failAll` and `finish` — the same cost
      true peak paid as the third consumer. No protocol, no generic machinery.
- [ ] 2.2 Hand each channel's run through **`withUnsafeBufferPointer`**, not as the `[Float]` itself.
      Measured, the array form costs **3.79–3.81 s** against **0.28–0.33 s** for ten minutes of stereo —
      a 12× penalty that would make the migration a slowdown. Confirm the mechanism while doing it
      (generic specialisation across the module boundary is the hypothesis, not the finding).
- [ ] 2.3 Confine the accumulator's `throws` to the waveform: a throw during accumulation faults the
      waveform alone, the read continues, and the other three settle exactly as they would have.
- [ ] 2.4 Preserve the **absence/failure distinction**. A stream whose frame count cannot be mapped to
      buckets is `.unavailable`, never `.failed` — the legacy port returned `nil` there, and that means
      "the file offered nothing to size against".
- [ ] 2.5 Add the fourth field to `SharedPCMAnalysisOutcome` and destructure it in
      `SourceInspectionCoordinator` exactly as the other three are. The order of emitted updates stays
      as it is today unless a test says otherwise.

## 3. Retire the second read

- [ ] 3.1 Stop calling `makeWaveformGenerator` in `SourceInspectionCoordinator`, and remove the factory
      and its default.
- [ ] 3.2 Delete `WaveformGenerating`, `AVFoundationWaveformGenerator` and `FakeWaveformGenerating`
      once nothing calls them. `AVFoundationAudioDecoder.defaultChunkFrames` currently derives its value
      from `AVFoundationWaveformGenerator.defaultChunkFrames` — move the constant rather than duplicating
      it, and keep **4 096**, so chunking is unchanged.
- [ ] 3.3 Keep `WaveformEnvelope`, `WaveformBucket`, `WaveformBucketMapping`,
      `WaveformEnvelopeAccumulator` and `WaveformError` **untouched**. The reduction's rules are what
      this change preserves; only the thing that used to own a read goes.

## 4. Equivalence, proved rather than asserted

- [ ] 4.1 Prove the envelope is **bit-identical** to the pre-change one for WAV and FLAC, over: mono,
      stereo, silence, a peak above full scale, a very short file, and a file whose final chunk is
      short.
- [ ] 4.2 Prove chunk-size independence at several chunk sizes, using the guarantee
      `WaveformEnvelopeAccumulator` already documents — not a widened tolerance.
- [ ] 4.3 For **AAC**, assert equality within a stated tolerance and justify the number in the test.
      Measured: 1778 of 2048 buckets differ by about one ULP, because the platform's lossy decoder does
      not return identical samples for a different read granularity. A test demanding bit-exactness here
      would be asserting something the platform does not offer.
- [ ] 4.4 Record the deliberate behaviour change on a file that **over-reads** its declared length: the
      legacy loop trimmed silently, the shared read refuses. Stricter on purpose.

## 5. The properties, each with a negative control

- [ ] 5.1 The waveform failing leaves the spectrogram, the signal level metrics and true peak with the
      outcomes they would have had, and the read still finishes.
- [ ] 5.2 Another consumer failing leaves the waveform's envelope identical to a control run.
- [ ] 5.3 A producer failure ends all four, each with its own outcome, publishing nothing partial.
- [ ] 5.4 Cancellation cancels the read and all four, and no partial envelope escapes.
- [ ] 5.5 Exactly **one** sample read is opened per inspection, counted at the adapter — the successor
      to the existing two-read count test.
- [ ] 5.6 Each negative control is reverted in full, and `git diff` shows no residue.

## 6. The deferral's own tests

- [ ] 6.1 Rewrite `WaveformDecodingSeamMigrationTests` rather than deleting it. It currently asserts
      *why the migration is blocked*; it should assert *what unblocked it* — that the two untranslatable
      decoding faults never reach the waveform because no error-space translation happens in this shape,
      and that the waveform's error space is still exactly the ten codes it had.
- [ ] 6.2 Re-point every test that scripts a waveform generator seam (`EndToEndFlowTests`,
      `WaveformFlowTests`, `WaveformReportIsolationTests`, `SpectrogramFlowTests`,
      `SignalLevelMetricsFlowTests`, `SharedPCMDecodeCountTests`, `MP3WaveformEvidenceTests`,
      `AVFoundationWaveformGenerator*Tests`). This is the largest and riskiest part of the change:
      several assert an *arrangement* rather than a *property*, and rewriting a test is how a guarantee
      quietly gets weaker. Each rewrite states which property it now pins.

## 7. Performance, confirmed against production code

- [ ] 7.1 Re-measure the real pipeline before and after, ten minutes of stereo, Release, WAV/FLAC/AAC,
      minimum of three runs. Expected from the pre-implementation probe: **0.02 s (WAV), 0.41 s (FLAC),
      0.39 s (AAC)**. A saving materially below that means the fold is paying something the probe did
      not — investigate before proceeding rather than accepting it.
- [ ] 7.2 Confirm memory stays a function of chunk plus accumulator state, and that the process
      footprint during the read does not grow with duration.
- [ ] 7.3 Confirm the report is still emitted before any sample read, and that the waveform is still
      delivered as its own progressive update.

## 8. Gates and closure

- [ ] 8.1 Four gates green plus the Xcode build and `git diff --check`.
- [ ] 8.2 Update `CURRENT.md` and archive through `openspec archive` **after merge**.
