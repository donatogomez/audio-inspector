# Implementation Tasks

Investigation is done and its results live in `design.md`. Everything below is implementation, and the
order is chosen so the risky part is provable before the irreversible part happens.

## 1. Decide the record before writing code

- [x] 1.1 **ADR-0021** written, revisiting **ADR-0020 decision 6** ("the waveform stays on its own read
      for now"). It is `Accepted`, so this is a decision and not an implementation detail; ADR-0020 is
      referenced, never edited. It carries the measured saving, the equivalence result, the 12× fold
      penalty, and why the recorded blocker was about a different shape. **Corrected on 2026-08-17**:
      its AAC tolerance did not survive measurement against production code — see 4.3.
- [x] 1.2 Recorded explicitly that **ADR-0016 did not prohibit this migration**: it scheduled it as
      conditional and last, and the deferral being revisited is ADR-0020's.
- [ ] 1.3 Promote ADR-0021 from `Proposed` once its own two criteria are met — the saving reproduced
      against production code (group 7) and each property demonstrated by a test that fails when broken
      (groups 4 and 5). Partial evidence does not promote it.

## 2. Feed the waveform from the shared read

- [x] 2.1 Add `WaveformEnvelopeAccumulator` to `SharedPCMAnalysisGeneration.Consumers`: one stored
      property, one fault, one line in `prepare`, `accumulate`, `failAll` and `finish` — the same cost
      true peak paid as the third consumer. No protocol, no generic machinery.
- [x] 2.2 Hand each channel's run through **`withUnsafeBufferPointer`**, not as the `[Float]` itself.
      Measured, the array form costs **3.79–3.81 s** against **0.28–0.33 s** for ten minutes of stereo —
      a 12× penalty that would make the migration a slowdown. Confirm the mechanism while doing it
      (generic specialisation across the module boundary is the hypothesis, not the finding).
      **Reproduced against production code**: the fold costs 0.29–0.34 s through the pointer and
      4.21–4.23 s through the array — ~13×, on all three formats. The mechanism is still a hypothesis.
- [x] 2.3 Confine the accumulator's `throws` to the waveform. A throw during accumulation is caught and
      faults the waveform alone; the read continues. **The reachable failure turned out to be at
      `finished()`**, not during accumulation — an incompletely covered read — and that is the input the
      isolation test uses.
- [x] 2.4 Preserve the **absence/failure distinction**. A stream whose frame count cannot be mapped to
      buckets is `.unavailable`, never `.failed` — the legacy port returned `nil` there, and that means
      "the file offered nothing to size against".
- [x] 2.5 Add the fourth field to `SharedPCMAnalysisOutcome` and destructure it in
      `SourceInspectionCoordinator` exactly as the other three are. Completed by group 3's cut: the
      coordinator now publishes `shared.waveform`, and the update order is unchanged.

## 3. Retire the second read

- [x] 3.1 Stop calling `makeWaveformGenerator` in `SourceInspectionCoordinator`, and remove the factory
      and its default. The typealias, the stored closure, the init parameter and the private
      `waveform(for:at:)` helper are gone, so the composition root has no way to open a second read.
- [x] 3.2 ~~Delete `WaveformGenerating`, `AVFoundationWaveformGenerator` and `FakeWaveformGenerating`
      once nothing calls them.~~ **The task's text conflated two different things and is corrected here
      rather than carried as a false debt.** What it was for — *retiring the legacy read from
      production* — happened in 3.1. What its wording asked for — deleting the types — turns out to cost
      a guarantee, and the audit is what showed it.
      **Decision: the port and its AVFoundation adapter are kept, as a test-only oracle.** They have no
      production consumer in any target, and the equivalence suites compare the shared fold against them
      — an implementation with its **own** read loop, its own frame accounting and its own AVFoundation
      calls. Delete them and those suites still pass while comparing the shared path with itself, which
      is not a retirement but a quiet loss of evidence. Folding against a bare
      `WaveformEnvelopeAccumulator` is not a substitute: it consumes the same chunks from the same
      decoder, so it can check the composition but never the transport.
      **Moving them to `AudioInspectorTesting` was evaluated and is architecturally blocked**:
      `check-boundaries.sh` rule 6 confines AVFoundation to `AudioInspectorMedia`, so the move would
      either break a build-enforced boundary or need an abstraction invented purely to relocate a test
      helper. Golden fixtures were rejected too — they would freeze one implementation's output and
      could not tell a regression from a platform change.
      **`FakeWaveformGenerating` is deleted**, and that one really was dead: its only consumer was its
      own test suite. Both are gone, and no guarantee went with them.
      ADR-0021 decision 4's concern — a port with no caller invites a second read back — is answered by
      the gate rather than by deletion: **no production target may name a waveform-reading port**, which
      is asserted over all of `Sources/` and fails on a reintroduced factory or a direct construction.
- [x] 3.3 Keep `WaveformEnvelope`, `WaveformBucket`, `WaveformBucketMapping`,
      `WaveformEnvelopeAccumulator` and `WaveformError` **untouched** — verified byte-identical. The reduction's rules are what
      this change preserves; only the thing that used to own a read goes.

## 4. Equivalence, proved rather than asserted

- [x] 4.1 Prove the envelope is **bit-identical** to the pre-change one for WAV and FLAC, over: mono,
      stereo, silence, a peak above full scale, a very short file, and a file whose final chunk is
      short. `SharedWaveformEquivalenceTests` compares the **whole `WaveformEnvelope` with `==`** against
      the legacy generator on the same file: 14 container/channel/signal rows (WAV 1/2/4 channels, FLAC
      1/2, AIFF, ALAC, AAC, float WAV), silence, zero frames, four very short files (1, 2, 7, 512
      frames) and the tail case. Every fixture is **44 101 frames** — prime, so a short final chunk and
      a length that divides no chunk size are properties of every row rather than of one.
      A peak above full scale needed a new fixture format: every existing container quantises to 16-bit
      integer and clamps it, so **32-bit float WAV** was added, and a 2.5 amplitude round-trips at
      2.4999995 and survives both paths unclamped.
- [x] 4.2 Prove chunk-size independence at several chunk sizes, using the guarantee
      `WaveformEnvelopeAccumulator` already documents — not a widened tolerance. Nine sizes from one
      frame to the whole file, each compared against the legacy read. **Resolution independence too**,
      which the task did not ask for and the mapping deserves: five `maximumBucketCount` values
      including 1, production's 2 048 and one larger than the file has frames.
- [x] 4.3 For **AAC**, assert equality **exactly**, like the lossless containers. ~~Within a stated
      tolerance~~ — **the hypothesis fell.** The pre-implementation probe reported 1778 of 2048 buckets
      differing by about one ULP; measured again through the production composition, on the same file,
      with the same decoder, accumulator and bucket count, and at the probe's own ten-minute length, the
      worst bucket error is **exactly zero** — for a pure sine and for a per-channel signal the encoder
      cannot fold together. The probe's finding does not reproduce and is recorded as an artefact of that
      throwaway harness. The test still computes and prints the worst error, so a future platform change
      reports its magnitude rather than only failing.
- [x] 4.4 Record the deliberate behaviour change on a file that **over-reads** its declared length: the
      legacy loop trimmed silently, the shared read refuses. Stricter on purpose.
      **Measured first: no writable container over-reads.** WAV, AIFF, ALAC, FLAC, AAC and float WAV
      were each read bounded by the declared length and unbounded past it, and every one delivered
      exactly what it declared in both directions. So the input that separates the two policies cannot
      be produced natively, and a legacy-versus-shared comparison for it would test a fixture that does
      not exist.
      `WaveformDeclaredLengthTests` therefore pins the **shared** policy where a misbehaving decoder is
      expressible — at the port: *the declared frame count sizes the reduction and bounds the read;
      frames delivered beyond it are a fault of the read, reported as one, never trimmed away and never
      folded in.* It also pins the boundary (a run ending exactly at the declared length is fine) and
      the opposite direction (a shortfall fails the waveform alone and invents nothing). The suite is
      deliberately **not** named for equivalence, and the legacy clamp is recorded from its source
      rather than exercised.

## 5. The properties, each with a negative control

- [x] 5.1 The waveform failing leaves the spectrogram, the signal level metrics and true peak with the
      outcomes they would have had, and the read still finishes. Each survivor is compared as a **whole
      outcome** against its own accumulator fed the identical chunks against the identical stream —
      sharing no line of the composition, which is a stronger reference than a second run of it. "The
      read still finishes" is **observed at the port**: a delivery log counts every chunk handed over and
      records that the decode returned normally.
      **A "control run without the failure" over the same input does not exist**, because that input
      always fails the waveform; the independent accumulators are what stands in for it, and the test
      says so.
- [x] 5.2 Another consumer failing leaves the waveform's envelope identical to a control run. **True
      peak is the one sibling with a reachable solo failure** — its 48-tap reconstruction overflows on
      finite-but-enormous samples of alternating sign, where a minimum and a maximum cannot. So this
      direction is *observed*, not assumed symmetric.
- [x] 5.3 A producer failure ends all four, each with its own outcome, publishing nothing partial. Two
      cases, and the second was added because a negative control exposed the first as insufficient:
      failing **partway** leaves incomplete coverage, which the accumulator would refuse to publish
      anyway, so it does not test the composition. Failing **after the last chunk** leaves a complete,
      publishable envelope — and that is the case where reaching for it would hand back a plausible
      model produced by a failed read.
- [x] 5.4 Cancellation cancels the read and all four, and no partial envelope escapes. Forced
      deterministically with a two-gate handshake — no sleep, no polling, no `Task.yield()` — both
      mid-read and before the first chunk. The port log confirms the read did **not** reach the end.
- [x] 5.5 Exactly **one** sample read is opened per inspection, counted at the adapter — the successor
      to the existing two-read count test. **Counting alone proved insufficient**: reintroducing the
      legacy read left every counter happy, because a directly constructed adapter passes through no
      injected seam. A source-level assertion that `AudioInspectorApp` names no waveform-reading port
      was added beside it, and that is the one the control fails.
- [x] 5.6 Each negative control is reverted in full, and `git diff` shows no residue. Six of them:
      coupling the waveform's failure to the spectrogram; coupling it to signal levels and true peak;
      stopping the read as soon as the waveform is out; publishing its partial envelope after a producer
      failure; ignoring cancellation for it; and collapsing its absence into a failure. Each failed the
      tests that name its property — **the fourth only after the suite was strengthened**, which is the
      point of running them.
      **One property has no reachable input and is not claimed as observed**: "the waveform stops
      receiving chunks once it has failed". Its only reachable failure arrives at `finished()`, after the
      last chunk, so there is nothing left to stop receiving. The three guards that make the
      accumulation path unreachable are asserted instead, as an alarm that fires if any of them weakens.

## 6. The deferral's own tests

- [x] 6.1 Rewrite `WaveformDecodingSeamMigrationTests` rather than deleting it. It now asserts that the
      two untranslatable decoding faults are *still* untranslatable and no longer need to be, that the
      waveform's error space is unchanged, and — newly — that `PCMChunk` already carries the absolute
      position the reduction asks for, which is the capability the deferral said was missing.
      **Verified against its literal text during group 6** rather than assumed from the earlier work:
      the suite asserts what unblocked the migration, not why it was blocked, and the waveform's error
      space is still exactly the ten codes it had.
- [x] 6.2 Re-point every test that scripts a waveform generator seam (`EndToEndFlowTests`,
      `WaveformFlowTests`, `WaveformReportIsolationTests`, `SpectrogramFlowTests`,
      `SignalLevelMetricsFlowTests`, `SharedPCMDecodeCountTests`, `MP3WaveformEvidenceTests`,
      `AVFoundationWaveformGenerator*Tests`). This is the largest and riskiest part of the change:
      several assert an *arrangement* rather than a *property*, and rewriting a test is how a guarantee
      quietly gets weaker. Each rewrite states which property it now pins.
      **Done for every suite the cutover broke** (14 tests across 6 files), scripting the decoding port
      where they used to script the waveform port. Two tests were **removed** rather than converted,
      each with a note in place: "a cancelled waveform leaves the spectrogram's result intact" and its
      signal-levels twin had no reachable input once cancellation became global, and a test with no
      reachable input is green for the wrong reason. `AVFoundationWaveformGenerator*Tests` and
      `MP3WaveformEvidenceTests` are untouched: they test the oracle, which still exists.
      **Re-audited in group 6 against the literal list.** Every named suite is accounted for: six were
      re-pointed onto the decoding port, and the two `AVFoundationWaveformGenerator*Tests` plus
      `MP3WaveformEvidenceTests` legitimately still exercise the oracle — they are what keeps it a
      trustworthy reference, and `MP3WaveformEvidenceTests` covers a format no fixture can write.

## 7. Performance, confirmed against production code

- [ ] 7.1 Re-measure the real pipeline before and after, ten minutes of stereo, Release, WAV/FLAC/AAC,
      minimum of three runs. Expected from the pre-implementation probe: **0.02 s (WAV), 0.41 s (FLAC),
      0.39 s (AAC)**. A saving materially below that means the fold is paying something the probe did
      not — investigate before proceeding rather than accepting it.
      **Measured during group 3**, whole `inspect` against a `main` worktree, three rounds of
      minimum-of-three each: **1.303 s → 1.264 s (WAV), 2.177 s → 1.640 s (FLAC), 2.418 s → 2.044 s
      (AAC)**. FLAC and AAC gain roughly the decode that was removed. **WAV's ~0.04 s is inside the
      measurement's own spread** and should not be reported as a gain; one early reading even came out
      slower. Left unchecked because 7.2 and 7.3 are still open and this wants the fuller treatment.
- [ ] 7.2 Confirm memory stays a function of chunk plus accumulator state, and that the process
      footprint during the read does not grow with duration.
- [ ] 7.3 Confirm the report is still emitted before any sample read, and that the waveform is still
      delivered as its own progressive update.

## 8. Gates and closure

- [ ] 8.1 Four gates green plus the Xcode build and `git diff --check`.
- [ ] 8.2 Update `CURRENT.md` and archive through `openspec archive` **after merge**.
