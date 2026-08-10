# Implementation Tasks

**Only group 1 is done: this change is the contract, written before any implementation.** No
`Sources/` or `Tests/` file is touched by this change. Every task from group 2 onward is a roadmap for a
future session, not work performed here.

Boundaries no future task may cross: `TechnicalProperties` gains **no DSP** field — `averageFileBitrate`
is arithmetic on metadata already read, nothing more. Any sample-level metric is a **new domain value
type** (`SignalLevelMetrics`), never a field of `TechnicalProperties`. `AudioInspectorDomain` gains no
framework import. `AudioInspectorAnalysis` is the only target where Accelerate/vDSP may appear, and only
if measurement shows it is needed — not by default. No aggregate, no score, no single "dynamic range"
field, no frequency-extent property without a named, versioned threshold, no user-configurable analysis
constant anywhere.

## 1. The contract

- [x] 1.1 Open the change with `proposal.md`, `design.md`, this task list, and the delta specs on
      `audio-file-inspection` (MODIFIED) and the new `audio-signal-level-metrics` capability (ADDED).
- [x] 1.2 Audit every existing property's exact source by reading
      `AVFoundationAudioFilePropertyReader.swift` line by line — no claim in `design.md` §2 is assumed.
- [x] 1.3 Investigate `declaredBitrate`/`estimatedBitrate` fully: what produces each, when each is
      absent, and whether a real average bitrate is computable from data already in the domain
      (`design.md` §3). Confirmed computable from `sizeBytes × 8 ÷ duration`, always `.uncertain`,
      consistent with ADR-0012's own already-rejected alternative. **Named `averageFileBitrate`**, not
      `calculatedAverageBitrate` — audited and corrected: the first draft understated how common and how
      large the embedded-artwork distortion is, and the final name keeps *File* directly beside *Bitrate*
      so the qualifier survives being read quickly (`design.md` §3).
- [x] 1.4 Evaluate each candidate new property against a full-sample-pass/FFT/format-dependence/
      objectivity test (`design.md` §6), reject two by name with reasons rather than silently, and
      classify every survivor as declared/calculated/DSP-derived (never interpretation).
- [x] 1.5 Write **ADR-0018** in `Proposed`, fixing where a DSP-derived property may live relative to
      `TechnicalProperties` and that a calculated bitrate is never conflated with a declared or a
      framework-estimated one. References ADR-0006, ADR-0008, ADR-0009, ADR-0012; edits none of them.
      Add its row to `docs/adr/README.md`.
- [x] 1.6 Audit, and close rather than defer, two naming/survival questions the first draft left open:
      whether `declaredBitrate` should be kept, renamed, or removed despite being permanently empty today
      (kept, unchanged — `design.md` §4), and whether `estimatedBitrate` should be renamed to
      `frameworkEstimatedBitrate` for symmetry (not renamed — the cost of breaking an already-shipped
      `schemaVersion` 1 wire key outweighs a cosmetic gain the new field's own name already delivers
      without it; `design.md` §5).

## 2. `averageFileBitrate` (metadata-only — no DSP, no port change)

- [x] 2.1 Add `averageFileBitrate: Property<Int>` to `TechnicalProperties`, defaulting to
      `.unavailable(reason: nil)` like every other field.
- [x] 2.2 Thread `AudioFileReference.sizeBytes` from `readProperties(of file:)` through to
      `technicalProperties(from:)` in `AVFoundationAudioFilePropertyReader` — the value is already in
      scope at the call site and is not currently passed further.
- [x] 2.3 Implement the pure mapping: `sizeBytes` present and `duration` a clean, positive, confirmed
      value → `.uncertain(value: sizeBytes*8/duration, reason: …)`; any other combination (missing size,
      unconfirmed/zero/unavailable/failed duration) → `.uncertain(value: nil, reason: …)`, mirroring
      `estimatedBitrate`'s own shape. **Never `.available`, by design, per ADR-0012 and ADR-0018.** The
      `reason` string SHALL name what the figure includes — headers, tags, and any embedded artwork, not
      only the audio payload — not just say "an estimate."
      Implemented as an instance mapper `averageFileBitrate(sizeBytes:duration:)`, beside
      `declaredBitrate`/`estimatedBitrate` in the same file (Option C of the location audit — pure
      arithmetic on values already domain-level, but kept in the established one-mapper-per-field seam
      rather than split into a new Domain-level location for no functional gain). Rounding: `Double`
      division, `.rounded(.toNearestOrAwayFromZero)`, guarded against overflow before the final `Int(_:)`
      conversion — never a silent truncation.
- [x] 2.4 Unit-test the pure mapping with controlled inputs (no real file): both facts present and
      confirmed; missing size; unconfirmed/zero/negative/failed duration; a value that would overflow
      `Int`. Also covers: a defensive non-zero-uncertain-duration case (the real reader never produces
      one today, but the guard is proven to check the case, not just non-nil); zero `sizeBytes` computes
      an honest `0` rather than being treated as absent; an exact rounding boundary (`0.5` rounds to `1`);
      that doubling `sizeBytes` (as embedded artwork would) doubles the result, proving nothing is
      excluded from the numerator; a consolidated "never `.available`" sweep across every input shape;
      and that `declaredBitrate`/`estimatedBitrate`/`averageFileBitrate` are independent fields.
- [x] 2.5 Confirm the addition changes no other field, warning, or the global status for any existing
      fixture — a byte-for-byte regression check against the current property-mapper tests.
      **757 → 772 tests, all green** after updating every fixture/assertion that literally enumerated the
      prior eight technical-property keys (JSON export, presentation rows/groups, the outcome sentence's
      property count) to nine. `InspectAudioFileUseCase`'s warning-generation list is **deliberately not
      touched** in this group: wiring `averageFileBitrate` into it would add a new, always-present warning
      to every fixture with a valid size and duration (mirroring `estimatedBitrate`'s own always-present
      warning), breaking numerous existing warning-count assertions that predate this field. Left as a
      named, open follow-up rather than done silently or forced through — see the note below.
      **One real regression was found and fixed, not merely worked around**: `ComparisonFormatter.rows(for:)`
      (in the already-merged two-file comparison feature) zips `ReportPropertyFormatter.displays(for:)`
      positionally against `FileComparison`'s own fixed eight outcomes, and required an *exact* count
      match — the new ninth row made every comparison render zero rows. Fixed by pairing only the leading
      rows that match the outcome count (comment added explaining why), which is also the correct
      behaviour per the group 7 decision to keep `averageFileBitrate` out of the two-file comparison.
      `FileComparison` itself is untouched.
      **Follow-up named, not resolved here:** should `averageFileBitrate` eventually generate a warning
      like its seven siblings? Doing so needs a deliberate pass over every affected fixture (primarily in
      `InspectAudioFileUseCaseTests`), not a silent addition alongside an unrelated field's own group.
- [x] 2.6 Give `declaredBitrate(from:)`'s `.unavailable` case a real `reason` string (was `nil`) explaining
      that no evaluated API declares a nominal bitrate directly, now that the reason is fully understood
      (`design.md` §4). Documentation-quality only — the field's semantics and its `Property` case are
      unchanged; the one integration test that pinned the old `nil` reason now checks the case instead.

## 3. `SignalLevelMetrics` domain type (arithmetic — no FFT)

- [x] 3.1 Add `SignalLevelMetrics` (peak, DC offset, RMS, clipped-sample count) as a sibling of the
      report, never a field of `TechnicalProperties`. Store **per channel** as the canonical
      representation; expose **overall** peak/RMS/DC-offset/clipped-count as values derived by a fixed
      formula from the per-channel data (`design.md` §8) — not a second measurement pass. Represent "not
      computable" (zero frames: division by zero, an undefined maximum) distinctly from "computed and the
      value is zero," mirroring `WaveformEnvelopeAccumulator`'s own silence-vs-absence distinction.
      Implemented in `Sources/AudioInspectorDomain/ValueObjects/SignalLevelMetrics.swift`, no import at
      all. `peakSample`/`rms`/`dcOffset` are `Float?`, `nil` iff `sampleCount == 0`;
      `clippedSampleCount` is a plain, always-defined `Int`. Linear amplitude, not dBFS — a presentation
      layer converts for display, matching how `TechnicalProperties` itself stores Hz rather than a
      rendered string.
- [x] 3.2 Add its accumulator, built on `WaveformEnvelopeAccumulator`'s own proven shape: samples arrive
      as any `Collection<Float>`, the result is independent of feed order and chunk size, and the fold
      is a pure, commutative accumulation per channel — one running max, one running sum, one running
      sum-of-squares, one running clip count, per channel.
      **One deliberate deviation from the literal wording, stated rather than silent:** this accumulates
      `PCMChunk`, not `some Collection<Float>` — mirroring `SpectrogramAccumulator.accumulate(_:)`'s own
      shape instead of `WaveformEnvelopeAccumulator`'s. Two reasons: peak/RMS/DC/clipping need no frame
      **position** the way waveform buckets do, so the position-aware generic signature buys nothing; and
      vDSP (3.4) needs contiguous, pointer-accessible storage, which a fully generic `Collection` cannot
      promise without an intermediate copy that would defeat the point of accepting one. Feed order and
      chunk size independence hold exactly as asked — see 3.5's own caveat on what "independent" means
      once vDSP is in the loop.
- [x] 3.3 Fix the clipping threshold at `|sample| ≥ 1.0` (full scale on the domain's normalized
      amplitude), as a **named constant tied to the analysis engine version** (ADR-0006's own pattern),
      **never user-configurable** — a configurable analysis threshold would make identical files produce
      different results across runs, which this project's reproducibility principle rules out. The
      "near-0 dBFS run" refinement `analysis-methodology.md` also names is explicitly **not** part of this
      slice (`design.md` §8).
      `SignalLevelMetricsAccumulator.clippingThreshold: Float = 1.0`, inclusive (`≥`, confirmed by a
      negative control below), documented as engine-versioned, no configuration surface anywhere.
- [x] 3.4 Measure before choosing Accelerate: run the accumulator against a real ten-minute file in an
      unoptimised build first, exactly as group 12 did for the spectrogram, and let the number decide
      whether it stays pure Swift in `AudioInspectorDomain` or moves to `AudioInspectorAnalysis`.
      **Measured with a disposable harness (a real 10 min/44.1 kHz/stereo WAV, deleted after use), four
      implementations, Debug (`-Onone`) and Release (`-O`):**

      | Implementation | Debug | Release |
      | --- | --- | --- |
      | Decode only, no accumulation | 0.035 s | 0.035 s |
      | Naive scalar Swift (Domain, no import) | 9.15 s | 0.227 s |
      | `SIMD8<Float>` Swift (Domain, matching `isProvablyAllFinite`) | 6.6 s | 0.102 s |
      | vDSP for peak/sum/sumSq + scalar clip | 7.2 s | 0.077 s |
      | **vDSP for peak/sum/sumSq + `SIMD8<Int32>` for clip (chosen)** | **0.69 s** | **0.071 s** |

      Debug stayed a "brutal `-Onone` penalty" (per this task's own rule) under every pure-Swift
      variant, including the domain's own established SIMD8 technique — vDSP alone was not enough
      either, because it has no primitive for the clip count and the remaining scalar loop dominated.
      Only combining vDSP with `SIMD8` for the one operation vDSP cannot do closed the gap to something
      genuinely insignificant next to the rest of an inspection. **Decision: `AudioInspectorAnalysis`,
      with Accelerate**, per the rule's own "document the measured reason" branch — implemented in
      `Sources/AudioInspectorAnalysis/SignalLevelMetricsAccumulator.swift`.
- [x] 3.5 Unit-test the accumulator directly, with no file and no framework: known signals with known
      peak/DC-offset/RMS/clipping counts; silence (zero peak/RMS/DC-offset, zero clip count — not
      absent); a single full-scale sample; a sample beyond `|1|` (kept, not clamped, and can yield a
      positive dBFS peak); zero frames (metrics reported as not computable, not as zero); order- and
      chunk-size-independence; the overall/per-channel combination formulas against hand-computed values.
      **19 tests, `Tests/AudioInspectorKitTests/SignalLevelMetricsAccumulatorTests.swift`** — every case
      above, plus a sine wave's standard RMS/peak ratio, stereo channel independence, opposite-polarity
      non-cancellation, a mismatched-channel-count chunk changing nothing, determinism across two runs,
      and two precision cases: a ten-million-sample accumulation staying accurate to a bound derived from
      `Double`'s own error model (not an arbitrary tolerance), and exact cancellation of balanced
      positive/negative samples. **A real, measured caveat found by actually running these, not assumed:**
      `rms`/`dcOffset` are identical across chunk sizes only up to ~10⁻⁵ absolute, not bit-for-bit —
      `vDSP_sve`/`vDSP_svesq` compute each chunk's own partial sum in `Float32` internally, and different
      chunk boundaries hand vDSP different pairings that round differently in the last bit or two. `peak`,
      `clippedSampleCount` and `sampleCount` stay bit-exact, since a maximum and a count have no
      arithmetic combination for a grouping to change. Documented in the accumulator's own doc comment,
      not only in the test. **Two temporary negative controls, both reverted in full:** (1) computing
      `overallRMS` as the naive mean of per-channel RMS broke 2 assertions in
      `overallRMSIsNotTheAverageOfPerChannelRMS`; (2) using strict `>`/`<` instead of `≥`/`≤` for clipping
      broke 4 assertions across two tests. Both confirmed the tests discriminate, then were fully reverted
      (`diff` against a pre-mutation copy showed no residue).

## 4. Wiring the new pass into the flow

**Done — implemented and demonstrated, not merely composed.** `SignalLevelMetricsAccumulator.accumulate(_
chunk: PCMChunk)` (3.2) had the exact shape this group's own `SignalLevelMetricsGeneration.run(for:)`
needed, mirroring `SpectrogramGeneration.run(for:)` line for line as anticipated — the same fault/
cancellation/absence/empty-answer handling, the same two-guard fault check (`chunk.channelCount ==
stream.channelCount, chunk.fits(stream)`), adapted only where the two compositions genuinely differ
(`SignalLevelMetricsAccumulator.init?(channelCount:)` needs no `sampleRate`/`frameCount`, since level
metrics carry no frame position). Implemented in
`Sources/AudioInspectorApp/Import/SignalLevelMetricsGeneration.swift`.

Wiring it into `SourceInspectionCoordinator` required extending `SourceInspectionOutcome.inspected` and
`InspectionUpdate` with a fourth case (`signalLevelMetrics`), exactly as `SpectrogramOutcome`/
`SpectrogramState` were added beside the waveform's own in commit `8459553` — the same architectural
precedent, not a new one. `SignalLevelMetricsOutcome`/`SignalLevelMetricsState` (mirroring
`WaveformOutcome`/`SpectrogramOutcome` and their `State` counterparts, including the `loading` case and
the `cancelled`-drops-to-`nil` rule) were added to `Sources/FeatureImport/InspectionPresentation.swift`,
and `InspectionPresentation` gained a third field, `signalLevelMetrics: SignalLevelMetricsState`. This
ripple mechanically touched `ImportFlowModel` (both `apply` methods, plus the comparison path's
discarding of the third value exactly as it already discards the other two) and ~13 test files that
construct or pattern-match `.inspected(...)` — none of that is new design, all of it is the same shape
group by group already established for the waveform and the spectrogram.

- [x] 4.1 `SignalLevelMetrics` is produced by a **third independent operation** over the existing,
      shared `AudioDecoding` port — the same port the spectrogram already consumes — with its own
      cancellation, per ADR-0016's already-decided "separate operations, separate cancellation" rule.
      **Decided, not merely considered:** it does **not** hook into the waveform's own generator, which
      remains deliberately un-migrated onto the shared seam for its own, separate, already-declared
      reasons (`design.md` §10) — coupling a new consumer to that debt would make the eventual migration
      harder, not easier, and would reopen a shared-pass question ADR-0016 already closed.
      **Demonstrated, not assumed:** `SignalLevelMetricsGeneration` imports no `WaveformGenerating` type
      at all, and `SourceInspectionCoordinator.signalLevelMetrics(for:at:)` calls `makeDecoder(url)`
      independently of `spectrogram(for:at:)`'s own call — a fresh decoder instance per operation in
      production, proven by a call-order-scripted fake in
      `SignalLevelMetricsFlowTests.aCancelledSpectrogramLeavesTheOperationAlone` (cancelling the
      spectrogram's decoder leaves signal level metrics' real result intact) and its mirror,
      `aCancelledOperationLeavesTheWaveformAlone`/`aCancelledWaveformLeavesTheOperationAlone`. Its own
      cancellation is proven directly by `SignalLevelMetricsGenerationTests.cancellationBeforeStarting`
      and `cancellationDuringAccumulationYieldsNoMetrics` (no partial metrics ever escape). **Negative
      control run and reverted** (not merely asserted): artificially forcing
      `signalLevelMetricsOutcome` to mirror `waveformOutcome`'s cancelled/failed cases in the coordinator
      made exactly the two waveform-independence tests fail
      (`aFailingWaveformDoesNotStopSignalLevelMetrics`, `aCancelledWaveformLeavesTheOperationAlone`) and
      nothing else — confirming the independence tests discriminate rather than passing vacuously. Fully
      reverted; `git diff` against the pre-mutation file showed no residue.
- [x] 4.2 Confirm the new metrics do not delay, block, or get blocked by the report, the waveform, or the
      spectrogram — each stays independently cancellable and independently presentable.
      **Demonstrated for delay/block/cancellation**, by both a positive and a negative test: a failing or
      cancelled signal level metrics operation leaves the report's status, the waveform's result and the
      spectrogram's result untouched (`SignalLevelMetricsFlowTests.aFailingOperationChangesNothingElse`,
      `aCancelledOperationLeavesTheWaveformAlone`), and the reverse direction holds too
      (`aFailingWaveformDoesNotStopSignalLevelMetrics`, `aCancelledWaveformLeavesTheOperationAlone`,
      `aCancelledSpectrogramLeavesTheOperationAlone`). A first negative control (Control 1: temporarily
      making the coordinator never run or emit the third operation) was caught by
      `SignalLevelMetricsFlowTests` and `SignalLevelMetricsReportIsolationTests` failing outright — proof
      the wiring, not just the isolated composition, is what the tests exercise. **"Independently
      presentable" is demonstrated only at the flow-state layer, not the human-facing one**: the outcome
      reaches `InspectionUpdate`/`SourceInspectionOutcome` and settles into its own
      `SignalLevelMetricsState` (`loading`/`available`/`unavailable`/`failed`) inside
      `InspectionPresentation`, independently of the other two states — but no words, units, or dBFS
      conversion exist yet, because that is group 5's own scope and was not started here. Also
      demonstrated: the operation reads the file only inside the coordinator's existing security-scoped
      window (`SignalLevelMetricsFlowTests.theDecoderRunsInsideTheWindow`,
      `theMetricsSettleBeforeTheCoordinatorReturns`), and never touches the source file
      (`theSourceIsUntouched`). `Sources/`: no new port, no new use case, `Waveform*` files untouched.

## 5. Presentation

- [ ] 5.1 Present peak, DC offset, RMS and clipping **in words**, with units stated explicitly: peak and
      RMS in dBFS (reusing the spectrogram's existing −120 dBFS floor convention, and allowing a positive
      value for a genuinely out-of-range sample, explained rather than hidden); DC offset as a plain
      linear value; clipped-sample count as a plain integer.
- [ ] 5.2 No colour-only meaning, no verdict, no "this file clips too much" characterisation — the
      numbers and a plain statement of what was counted, nothing evaluative.
- [ ] 5.3 `averageFileBitrate` reads beside `declaredBitrate` and `estimatedBitrate` with its own label
      naming what it covers (the whole file, not the audio stream), so a reader is never left guessing
      which of three numbers means what or conflating this one with a stream-only figure.

## 6. Export

- [ ] 6.1 Add `averageFileBitrate` to the `technicalProperties` object in the `schemaVersion` 1
      JSON — additive, no version bump, per `docs/json-schema-v1.md`'s own stated evolution rule.
- [ ] 6.2 Add `SignalLevelMetrics` under the schema's already-anticipated, still-unused `measurements`
      object (`docs/json-schema-v1.md`: "Future (additive, still v1): measurements, findings — only once
      DSP slices land") — this is that slice.
- [ ] 6.3 Confirm the export change is isolated: a report without level metrics (or without the new
      bitrate field populated) exports byte-identically to today, following the same isolation-test
      pattern `add-two-file-technical-comparison` group 6.18 already established.

## 7. Deferred, and named so it is not quietly dropped

- [ ] 7.1 **True peak** — ADR-0006 already governs the methodology (≥4× oversampling, ITU-R BS.1770/EBU
      R128). Not designed here; implementation belongs to a change of its own.
- [ ] 7.2 **Significant max frequency** — needs its own noise-floor/persistence methodology, comparable
      in weight to what ADR-0006 already did for true peak, not a one-line reduction (`design.md` §11).
      When designed, it is a **pure post-processing step over the already-produced `Spectrogram` model**
      — no new file read. Not designed here.
- [ ] 7.3 **Crest factor** — mathematically free once peak and RMS both exist, and unlike "dynamic range"
      it has exactly one standard definition, so ADR-0006's "never a single truth" objection does not
      apply directly. Deferred anyway: exposed alone, ahead of the roadmap's own Phase 3 loudness suite,
      it invites the same out-of-context "how dynamic/compressed is this" reading that suite is meant to
      contextualize properly (`design.md` §12). Not designed here.
- [ ] 7.4 **Any named, single dynamic-range metric** (e.g. EBU LRA specifically) — only once the loudness
      suite is designed with multiple named metrics presented side by side, per ADR-0006. A generic
      `dynamicRange` field is rejected outright, not deferred (see `design.md` §7).

## 8. Gates and closure

- [ ] 8.1 Four gates green — `./Scripts/check-boundaries.sh`, `swift build -Xswiftc -warnings-as-errors`,
      `swift test`, `OPENSPEC_TELEMETRY=0 openspec validate --all --strict` — plus the Xcode app build.
- [ ] 8.2 Confirm `averageFileBitrate` never becomes `.available` in any test, and that `SignalLevelMetrics`
      never gains a Codable conformance that would let it leak into an unrelated export path.
- [ ] 8.3 Decide ADR-0018's status from what was actually implemented, update `CURRENT.md`, and archive
      through `openspec archive` after merge.
