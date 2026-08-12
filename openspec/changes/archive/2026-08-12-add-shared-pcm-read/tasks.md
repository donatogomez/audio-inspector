# Implementation Tasks

**Groups 1–4 are done: the contract, the composition, the proof that it keeps its guarantees, and the
saving measured against production code.**
Group 1's evidence lives in `docs/spikes/2026-08-12-shared-pcm-analysis-architecture.md`. Group 2 added
one production file and changed one call sequence; group 3 proved the isolation with a deterministic
cancellation harness and three negative controls, and needed **no change to the composition** — no
defect was found. Group 4 confirms the saving against production code in the spike's own form.

Boundaries no future task may cross: **`AudioDecoding` and `PCMChunk` are not modified** (audited — no
incapacity found); no accumulator, domain model or analysis result is modified; the composition lives
in `AudioInspectorApp` and nothing inverts a dependency; no protocol is introduced for three known
consumers; **no concurrency** and **no PCM buffering**; the waveform keeps its own read; the report, the
export and every interface are untouched. If wiring a consumer required changing its accumulator, that
is evidence the architecture is wrong (ADR-0020 follow-ups) and must be justified before proceeding.

## 1. The contract

- [x] 1.1 Open the change with `proposal.md`, `design.md`, this task list, and a delta spec adding the
      new `audio-sample-reading` capability — **ADDED only**, duplicating no existing requirement:
      `audio-file-inspection` covers metadata and `audio-signal-level-metrics` covers what a level
      metric is, and neither says anything about how many times a file is read.
- [x] 1.2 Reconstruct the current architecture from the code rather than from memory: who creates each
      decoder, who owns it, what each consumer needs, what it retains between chunks, how each cancels
      and fails (`design.md` §1 and the spike's table). Established the finding the whole design rests
      on: three of the four consumers take *exactly* the same `PCMChunk` through the same port with the
      same non-throwing `accumulate` shape, and the waveform does not.
- [x] 1.3 Separate what ADR-0016 protects from how it protected it, and record the distinction in
      **ADR-0020** (`Proposed`): *independent analyses* is the invariant, *independent decodes* was the
      implementation — a conclusion ADR-0016 itself licensed by naming the condition for revisiting it.
      ADR-0016 is **referenced, never edited**. Row added to `docs/adr/README.md`.
- [x] 1.4 Audit `AudioDecoding` and `PCMChunk` against a "demonstrated incapacity" rule and conclude
      **neither changes** (`design.md` §6).
- [x] 1.5 Evaluate six alternatives — status quo, sequential fan-out, concurrent fan-out, PCM buffering,
      partial sharing, waveform migration — and measure the surviving ones against the real pipeline.
      Sequential fan-out chosen; each rejection recorded with its reason and, where relevant, its
      measured ceiling (`design.md` §4–5, ADR-0020 Alternatives).
- [x] 1.6 Fix the success rule **before** interpreting the numbers, and check it after
      (`design.md` §10): 97–100 % of the redundant decode recovered, with every constraint held.

## 2. The shared read

**Done.** `Sources/AudioInspectorApp/Import/SharedPCMAnalysisGeneration.swift` — one new production
file, plus the coordinator's call sequence. **Domain, Media, Analysis, the features, the JSON contract
and the waveform are untouched**, `AudioDecoding` and `PCMChunk` are byte-identical, and nothing named
or reserved for a consumer that does not exist on this branch.

- [x] 2.1 Added `SharedPCMAnalysisGeneration` in `AudioInspectorApp`: one `AudioDecoding` call whose
      callback builds each accumulator from the first chunk's stream description — **one description, so
      two consumers can never disagree about the file they are reading** — and hands every chunk to each
      in turn. A **concrete** type: the consumers are held as their own stored properties, not behind a
      `PCMConsumer` abstraction, because their `finish()` results are unrelated types with unrelated
      optionality rules. It opens no `URL` and no security scope, and its callback stays synchronous, so
      no chunk or accumulator outlives the coordinator's window (ADR-0010).
- [x] 2.2 Each consumer carries its **own** recorded fault in a private `Consumers` value. A faulted
      consumer stops being fed and its accumulator is never read again, while the read continues for the
      others; `.stop` is returned **only** when every consumer has faulted, or on cancellation. The one
      case that faults all of them at once is audio that does not match the stream it claims to come
      from — a fault in what they all just received, not in any of them.
- [x] 2.3 Results map to the two **existing** outcome types unchanged, with each analysis keeping the
      exact wording it had when it read the file alone. `SharedPCMAnalysisOutcome` carries no combined
      status and no shared error, so nothing downstream can ask a question about the analyses together;
      the coordinator reads it apart immediately. Presentation, flow state and export are untouched and
      cannot tell the read is shared.
- [x] 2.4 `SourceInspectionCoordinator` now makes **one** decoder where it made two. The report is still
      emitted before any sample is read, the waveform still runs on its own read first, and the same two
      updates — `.spectrogram(…)` then `.signalLevelMetrics(…)` — are emitted in the same order.
      `SpectrogramGeneration` and `SignalLevelMetricsGeneration` are **retained deliberately** and each
      says why in its own documentation: they are the reference implementations the equivalence test
      compares the shared read against. Deleting them would remove that oracle, so it is a separate
      decision rather than a side effect of this one.

## 3. Proving the isolation, not assuming it

**Done, and mostly with tests rather than code**: the composition needed no change, so this group added
one test file and consolidated another. Four superseded tests were **removed** rather than left beside
their stronger replacements — one of them had a flawed comparison (it measured the shared read at chunk
size *N* against separate reads at 4 096, which conflates "sharing changed something" with "chunking
changed something").

- [x] 3.1 `failedConsumerLeavesTheOtherIdentical` compares the surviving analysis's **whole outcome**
      against a control run where nothing failed — value for value, not "not nil" and not "available".
      `theReadContinuesAfterAConsumerFails` adds what that alone would miss: the read really did run to
      the end, counted at the port rather than inferred from an outcome.
      The mirror direction is still unreachable and is **not fabricated**:
      `signalLevelMetricsHaveNoReachableSoloFailure` pins that `SignalLevelMetricsAccumulator` refuses
      only what `PCMStreamDescription` already refuses, so it starts failing the day that accumulator
      gains a second failure mode — which is the moment symmetric coverage becomes owed.
- [x] 3.2 Producer and consumer failures are tested **separately, with different fixtures**, and their
      difference is asserted directly. `producerFailurePartwayPublishesNothingPartial` uses a decoder
      that fails *after* eight chunks — proving the composition holds real partial state at that moment
      — and neither analysis publishes it; each still answers in its own words.
      `consumerAndProducerFailuresAreDistinguishable` states the difference that matters: a consumer
      failure leaves the other analysis `available`, a producer failure does not.
- [x] 3.3 **Deterministic, with a handshake rather than a hope.** A scripted decoder suspends inside the
      read at a chunk the test chooses, signals that it has arrived, and continues only once released —
      so the test cancels while the read is provably mid-flight. No sleep, no polling, no `Task.yield()`.
      `cancellingMidReadCancelsEverything` (cancelled four chunks in) and
      `cancellingBeforeTheFirstChunk` (cancelled before any audio is accumulated) both assert every
      analysis reports `cancelled`, that **no partial or empty model escapes**, and — counted at the port
      — that the read stopped instead of finishing the file.
- [x] 3.4 The four ways a read can produce nothing are tested **apart**: a stream that hands over no
      chunks, a valid stream of zero frames, no usable frame count, and a real decoder failure.
      `theFourEmptyOutcomesAreDistinct` asserts they do not collapse into one another. The first two are
      compared against the separate reads' own results, so the shared read is shown to have **inherited**
      that semantics rather than invented a new common one.
- [x] 3.5 `sharedMatchesSeparateAtEveryChunkSize` runs 1, 3, 127, 512, 1 024, 2 048, 4 096, 8 192 and
      65 536 frames per chunk, plus `sharedMatchesSeparateInASingleChunk` for the whole file at once.
      Each compares the shared read against separate reads **fed the identical chunk sequence**, which
      is what isolates this task's question from the accumulators' own chunking guarantees — and lets
      the comparison be **full equality with no tolerance**, for both analyses.
      **The task's true-peak clause is not satisfiable here and is not pretended to be**: that consumer
      does not exist on this branch. It moves to `add-true-peak-measurement` group 6, which adds it.
- [x] 3.6 Three tests asserted the mechanism and were rewritten in group 2; this group audited what each
      had protected and confirmed the guarantee now has its **own** test rather than riding on the
      rewrite. `decoder.spy.callCount == 1` protects deduplication and **nothing else** — isolation,
      cancellation and failure semantics are proved by the tests above, not by it.
      **Three negative controls, each reverted in full** (`diff` against a pre-mutation copy showed no
      residue): coupling a spectrogram fault to the signal level metrics broke exactly the three
      isolation tests; ignoring `Task.isCancelled` broke exactly the two deterministic cancellation
      tests; publishing a partial model after a producer failure broke exactly the two producer-failure
      tests. Each control broke the tests that name that property and no others.

## 4. Confirming the saving against production code

**Done, and the stop rule did not fire.** The measurements live in the spike's **§15**, appended
rather than overwriting §§1–14, so the pre-implementation evaluation and its production confirmation
can be read against each other. The harness was temporary, in the test target, and is deleted.

- [x] 4.1 Measured against the **real** coordinator, property reader, waveform generator, decoder,
      `SharedPCMAnalysisGeneration` and accumulators — no fake on the critical path, and production not
      instrumented. 10 min stereo 44.1 kHz WAV/FLAC/AAC, Debug and Release, **six runs per cell** (two
      independent passes of three, each after a discarded warm-up). Published as §15 beside §8's own
      tables. **What is comparable is stated first**: this branch has no true peak, so the pipeline
      goes from three reads to two and removes **one** redundant decode where §8 removed two — the
      claim carried forward is §8's finding about what the saving *is*, not its absolute seconds.
- [x] 4.2 **It reproduces.** Release saves 0.06 s (WAV), 0.73 s (FLAC), 0.56 s (AAC); Debug saves
      0.69 / 1.39 / 1.10 s — between **98 % and 107 %** of one measured decode across the six cells,
      averaging 103.6 % against a 1–7 % run-to-run spread. **The figures above 100 % are noise and are
      named as such**, not banked as extra saving: only one decode was removed. The decomposition
      reconciles to ≤ 0.09 s everywhere, so no cost appeared elsewhere, and the fan-out is free — the
      shared pass costs the sum of its parts, reproducing §6's finding against production code.
      Memory: peak footprint **17 MB for one minute against 22 MB for ten**, sampled at every chunk,
      versus the 212 MB option D would have needed.
- [x] 4.3 The report is emitted at **1.5–2.0 ms**, two to three orders of magnitude before the first
      sample analysis settles, and sharing did not move it. Results are **identical value for value**
      to the pre-change results on real files of each format — the whole outcome compared with `==`,
      spectrogram and signal level metrics, WAV/FLAC/AAC. Also counted rather than assumed: the real
      pipeline opens **exactly two** sample reads. **One limit is recorded rather than glossed**: the
      report's *ordering* is guaranteed structurally and confirmed by measurement, but no test pins it
      — a gap that predates this change and is unchanged by it.

## 5. Gates and closure

- [x] 5.1 All six green, run twice over the final tree: `./Scripts/check-boundaries.sh`,
      `swift build -Xswiftc -warnings-as-errors`, `swift test` (889 tests / 98 suites, no flake),
      `OPENSPEC_TELEMETRY=0 openspec validate --all --strict` (7/7), the Xcode `AudioInspector` Debug
      build, and `git diff --check`.
- [x] 5.2 **Passed**, and on a genuinely fresh instance rather than a hopefully fresh one: the stale
      process this project has been caught by before is *still* alive and unkillable, so the build was
      launched with `open -n` and its identity confirmed before anything was observed
      (`docs/manual-validation-mvp.md`). Two **real** files — a 44.1 kHz WAV and a 64 kHz FLAC — each
      produced report, waveform, spectrogram and signal levels, all present, all in unchanged wording,
      with each spectrogram spanning its own true Nyquist. Replacing the first file with the second in
      the same window changed all four sections and left nothing of the first behind. The report
      appeared immediately and nothing felt slower — **recorded at exactly that strength**, since the
      pass was not timed and the timings belong to §15 of the spike. One cosmetic defect was seen and
      **not** fixed here: on the 64 kHz file the spectrogram's axis draws `32 kHz` over `30 kHz`. It
      lives in presentation, which this change does not touch, and would occur on `main`.
- [x] 5.3 ADR-0020 was decided from what was measured against production code and is **Accepted**, with
      its `Promotion` section recording the evidence and the one respect in which it is weaker than
      promised; `CURRENT.md` was updated. The third action waited for the condition it names —
      `openspec archive` runs **after** the merge — and this task was left open on two thirds of its
      content until that happened rather than marked early. It is marked here, on `main`, in the same
      commit that archives the change.

## 6. Deferred, and named so it is not quietly dropped

- [ ] 6.1 **The waveform's migration onto the shared seam** — already deferred by ADR-0016 and by
      `add-static-spectrogram-visualization`'s group 9. It would take two reads to one, and it is the
      obvious next reduction. Not started here: it needs its own port migration first.
- [ ] 6.2 **Concurrent fan-out** — measured ceiling ~0.28 s on a ten-minute stereo file, against three
      deliberately non-`Sendable` accumulators and a synchronous callback contract that exists for a
      sandbox reason. Reopening it requires evidence the ceiling has grown, not a preference.
- [ ] 6.3 **`add-true-peak-measurement` group 6** resumes once this merges, wiring true peak as a
      consumer of the shared read. Its model, accumulator, methodology and tests are finished and are
      **not** redesigned. Tracked there, not here.
- [ ] 6.4 **`SpectrogramGeneration` and `SignalLevelMetricsGeneration` are no longer wired into an
      inspection** — the coordinator produces both analyses through the shared read — and they are
      **kept on purpose**, not forgotten: they are the oracle `sharedMatchesSeparate…` compares the
      shared read against, and deleting them would remove the only independent implementation that
      proves sharing changed the transport rather than the analysis. Each says so in its own
      documentation. **Removing them is a separate decision**, and it is the wrong one while the
      equivalence tests are the strongest evidence this change has; the moment to revisit it is when
      true peak makes the shared pass the only composition anyone reads. Not done here: deleting live
      code at the end of a change is exactly the kind of widening this task list refuses.
