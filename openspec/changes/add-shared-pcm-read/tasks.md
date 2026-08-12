# Implementation Tasks

**Only group 1 is done: this change is the contract, written after the architecture was measured but
before any of it is built.** No `Sources/` and no `Tests/` file is touched by this change. Group 1's
evidence lives in `docs/spikes/2026-08-12-shared-pcm-analysis-architecture.md`.

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

- [ ] 2.1 Add the composition in `AudioInspectorApp`: one `AudioDecoding` call whose callback builds
      each consumer's accumulator from the first chunk's stream description and hands every chunk to
      each in turn. **A concrete type, not a protocol** — the three `finish()` results are unrelated
      (`design.md` §7). It opens no `URL` and no security scope; it runs inside the coordinator's
      existing window (ADR-0010).
- [ ] 2.2 Give each consumer its own recorded fault, so one consumer's failure is remembered without
      ending the read or touching another's state. **The `.stop` disposition is returned only when every
      consumer has finished or failed**, never when one has.
- [ ] 2.3 Map the results to the three existing outcome types unchanged, so nothing downstream —
      presentation, flow state, export — learns that the read is shared.
- [ ] 2.4 Replace the separate reads in `SourceInspectionCoordinator`, keeping the waveform's own read
      and keeping the report emitted before any sample is read.

## 3. Proving the isolation, not assuming it

- [ ] 3.1 Test that one consumer failing leaves every other consumer's result **identical** to what it
      produces alone — compared value for value, not merely "not nil".
- [ ] 3.2 Test that a decoder failure ends every unfinished consumer, each with its own outcome, and
      that this is distinguishable from a single consumer's failure.
- [ ] 3.3 Test that cancelling the inspection reports cancellation for every unfinished consumer and
      that **no partial model escapes**.
- [ ] 3.4 Test that a file with no audio frames yields each consumer's own complete empty answer rather
      than a failure.
- [ ] 3.5 Test chunk-size independence across the shared read, at the sizes each consumer's own tests
      already use, and confirm true peak stays **bit-exact** as its own accumulator guarantees.
- [ ] 3.6 **Rewrite the tests that assert the mechanism rather than the property.** Several today script
      two decoders by call order and assert that "the coordinator gives each operation its own decoder
      instance rather than passing one decoder to both". Rewrite them to assert isolation, and prove the
      rewrite still discriminates with a **negative control** — coupling two consumers deliberately must
      break named assertions — rather than merely still passing.

## 4. Confirming the saving against production code

- [ ] 4.1 Re-measure the end-to-end cost against the real composition, in the same form as the spike:
      10 min stereo, WAV/FLAC/AAC, Debug and Release, minimum of three runs after a warm-up. Publish the
      table beside the spike's own so the two can be compared directly.
- [ ] 4.2 Confirm the measured saving reproduces — 97–100 % of the redundant decode — and that memory
      still does not scale with duration. **If it does not reproduce, stop**: the honest outcome is to
      record the difference and reconsider, not to keep the architecture because the spike liked it.
- [ ] 4.3 Confirm the report is still emitted before any sample read, and that no analysis's result
      changed value as a result of sharing — compared against the pre-change results, file by file.

## 5. Gates and closure

- [ ] 5.1 Four gates green — `./Scripts/check-boundaries.sh`, `swift build -Xswiftc -warnings-as-errors`,
      `swift test`, `OPENSPEC_TELEMETRY=0 openspec validate --all --strict` — plus the Xcode app build
      and `git diff --check`.
- [ ] 5.2 Manual validation on a confirmed-fresh process instance: an inspection of a real compressed
      file still produces the same report, waveform, spectrogram and signal levels, and visibly sooner.
- [ ] 5.3 Decide **ADR-0020**'s status from what was actually measured against production code, update
      `CURRENT.md`, and archive through `openspec archive` **after merge**.

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
