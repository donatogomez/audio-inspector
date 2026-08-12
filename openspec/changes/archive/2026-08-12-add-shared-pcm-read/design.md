# Design — one PCM read for several analyses

## 1. What was measured, and what it decided

Every number here comes from `docs/spikes/2026-08-12-shared-pcm-analysis-architecture.md` and the
end-to-end cost spike that preceded it. Ten minutes of stereo, minimum of three runs after a warm-up.

| Release | current (3 reads) | + true peak (4 reads) | **shared (2 reads, incl. true peak)** |
| --- | --- | --- | --- |
| WAV | 0.698 s | 1.233 s | **1.138 s** |
| FLAC | 1.907 s | 2.848 s | **1.950 s** |
| AAC | 2.180 s | 3.194 s | **2.140 s** |

| Debug | current (3 reads) | + true peak (4 reads) | **shared** |
| --- | --- | --- | --- |
| WAV | 3.773 s | 4.905 s | **3.699 s** |
| FLAC | 4.927 s | 6.460 s | **4.439 s** |
| AAC | 4.643 s | 6.080 s | **4.253 s** |

**The saving is exactly the redundant decodes removed — 97–100 % of them, no more and no less.** The
DSP is additive and unchanged, and the fan-out itself costs nothing (measured shared-pass DSP 0.765 s
against a per-consumer sum of 0.764 s).

The consequence in one sentence: **for the compressed formats this product exists to examine, sharing
pays for the entire true-peak feature**, and in Debug every measured format is faster than today with
true peak included. Uncompressed files gain almost nothing, because their decode was already nearly
free — that is stated rather than averaged away.

## 2. The invariant, and the thing that was only a mechanism

ADR-0016 decision 15 required independent operations with independent cancellation and rejected a
shared pass. Reading it literally, its normative content is:

1. one analysis may not fail, cancel or delay another;
2. no analysis may depend on another having been requested;
3. results are delivered as each settles;
4. no operation becomes the place every future metric is added;
5. streaming, bounded memory, no framework type across a port.

**A decoder per analysis is none of those.** It was how they were met while a decode looked free, and
the same record wrote the condition for revisiting it. **ADR-0020** records the distinction:
*independent analyses* is the invariant; *independent decodes* was the implementation.

Point 4 deserves its own sentence, because it is the one a shared read could plausibly violate. It does
not: each analysis keeps its own accumulator, model, outcome and tests, and the composition knows what
none of them computes. **A new metric adds a consumer; it does not widen an existing operation.**

## 3. Semantics — the questions sharing actually raises

| Situation | What happens | Why |
| --- | --- | --- |
| **A consumer fails** (its accumulator cannot be built for the stream, or it sees a chunk that does not match) | It stops accumulating. **The read continues.** Its own outcome is `failed`; every other consumer settles exactly as it would have. | This *is* the property ADR-0016 protects, now held by construction instead of by separation. |
| **The decoder fails** | No more PCM will exist, so every consumer that had not finished ends without a result, **each reporting its own outcome**. | A caller reading one result must not have to learn why another is missing. The cause is shared; the outcomes are not. |
| **The inspection is cancelled** | The read stops and every consumer reports `cancelled`. **No partial model escapes.** | The rule each existing operation already follows, applied once instead of three times. |
| **A consumer no longer needs samples** | The read continues while **any** consumer still needs them, and stops when all are done. | Prevents one consumer starving another. Today none finishes early — all need every sample — so this is contract text, not a mechanism to build. |
| **The inspection is superseded** (stale) | Unchanged. The flow already discards a superseded inspection's results, and sharing returns one bundle to the same call. | Nothing about *when* results arrive changes. |
| **Backpressure** | Does not arise. Consumers are synchronous on the reader's own task, so a slow consumer slows the read directly rather than queueing behind it. | A property of the port's synchronous callback, which exists because ADR-0010 releases the security scope when the inspection returns. |

**Producer failure and consumer failure are different things and the contract names them separately.**
Collapsing them is the most likely way to get this wrong.

## 4. Sequential, not concurrent

Measured per-consumer DSP (ten minutes of stereo, Release): spectrogram 0.248 s, signal levels 0.029 s,
true peak 0.487 s — sum 0.764 s. Perfect parallelism would floor that at 0.487 s, **saving ~0.28 s**.

Rejected, on the minimum-architecture rule:

- all three accumulators are deliberately **not `Sendable`**, and `SpectrogramAccumulator` owns a
  transform that *cannot* be;
- the port's callback is **synchronous by contract**, because ADR-0010's security-scoped window is
  released when the inspection returns and an escaping consumer could outlive it;
- ~6 500 chunks per ten-minute file means ~6 500 task hops per consumer.

Three actors and a reopened port contract to gain 0.28 s, where sequential sharing already recovers
0.9 s, is not the minimum. Recorded as a measured ceiling so it can be reopened on evidence.

## 5. The waveform is out, and what that costs

Not because sharing four would be worse — because including it is a different change:

- it uses a **different port** (`WaveformGenerating`), implemented with its own read inside Media;
- its accumulator takes `(samples, ofChannel:, startingAtFrame:)` and **throws**, where the other three
  take a whole `PCMChunk` and cannot. It genuinely needs frame position; they do not;
- ADR-0016 left its migration deliberately undone, and `add-static-spectrogram-visualization`'s group 9
  carries a stop rule that permitted deferring it — which it did.

Migrating it is a prerequisite, and doing both at once is two risky things in one change. **Measured
cost of leaving it out**: its own read, 0.319 s (WAV), 0.724 s (FLAC), 0.628 s (AAC) in Release. That
is the remaining redundancy, named as a follow-up rather than hidden.

## 6. `AudioDecoding` and `PCMChunk` do not change

Audited against "do not modify without a demonstrated incapacity":

- `AudioDecoding` already yields **one** chunk sequence per call; the caller controls iteration through
  the returned disposition; the stream description arrives with every chunk, which is what three
  accumulators need to size themselves; and nothing in it names an analysis, so N consumers can receive
  each chunk without the decoder knowing they exist.
- `PCMChunk` holds `startFrame` and `channels: [[Float]]`, is immutable and `Sendable`, and Swift arrays
  are copy-on-write. Handing the same value to three consumers copies **a few words of struct, never
  the samples**.

No incapacity was found in either. Both are untouched.

## 7. No new protocol

Three types having `accumulate(_ chunk: PCMChunk)` is not a reason to write one. Against the bar:
common input **yes**; common `finish()` **no** — three unrelated return types with three different
optionality rules, so a protocol needs an associated type; common lifecycle **yes**; duplication
removed **small**; test benefit **none** (the existing fakes work at the port, not the accumulator).

**A concrete composition** owning the three accumulators and returning their three outcomes is smaller
and no less testable. If a fourth and fifth consumer of the same shape appear, that is when an
abstraction earns itself.

## 8. Where it lives

`AudioInspectorApp`, beside the `Generation` types it replaces — the layer that already composes ports
with consumers. Analysis owns DSP and must not learn about files; Media owns decoding and must not learn
about analyses; the domain knows none of it. **No dependency is inverted and no module boundary moves.**

## 9. What this change is allowed to break, and what it is not

**Allowed, and expected**: tests that assert the *mechanism*. Several script two decoders by call order
and state outright that "the coordinator gives each operation its own decoder instance rather than
passing one decoder to both". That sentence stops being true. Those tests must be rewritten to assert
the **property** — one consumer's failure or cancellation leaves the others untouched — and the
rewrite must be shown to still discriminate, by a negative control, rather than merely to still pass.

**Not allowed**: any change to `TruePeakMeasurement`, `TruePeakAccumulator`, `SignalLevelMetrics`,
`Spectrogram`, their accumulators, the report, the export, or any interface. If wiring a consumer
required changing an accumulator, that is evidence this architecture is wrong (ADR-0020 follow-ups) and
must be justified before proceeding rather than absorbed.

## 10. The success rule, written before the numbers were interpreted

The change is worth making only if it **recovers a material part of the redundant decode cost** —
material meaning comparable to the 0.47–0.53 s per extra decode that opened it — while:

- not delaying the report;
- not making memory scale with duration;
- not coupling consumers' errors;
- not making the decoder know that analyses exist;
- not breaking a module boundary;
- not adding an external dependency.

**Measured: 97–100 % of the redundant decode recovered, and every constraint held.** Had it not been,
the honest outcome of this change would have been *"do not share"*, and the design would have said so.
