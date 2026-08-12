# Spike report — one PCM read for several analyses: architecture, semantics and measured saving

> **What this is.** The architecture evaluation that `add-true-peak-measurement`'s group-5 stop rule
> demanded. It reconstructs what happens today, separates what ADR-0016 actually protects from how it
> protected it, enumerates the alternatives, and measures the surviving ones against the real pipeline.
>
> **What it is not.** No production code changed. No decision here modifies the true-peak measurement,
> its model or its accumulator, all of which are finished.

- **Date prepared**: 2026-08-12
- **Harness**: temporary, in the test target, **created, measured, deleted** — never committed. Real
  coordinator, real files, real AVFoundation decode, real `SpectrogramAccumulator`,
  `SignalLevelMetricsAccumulator` and `TruePeakAccumulator`.
- **Related**: **ADR-0016** (decision 15 — the one this revisits; *referenced, never edited*), ADR-0010
  (the security-scoped window that shapes the port), ADR-0011, ADR-0018, ADR-0019,
  `docs/spikes/2026-08-12-true-peak-end-to-end-cost.md` — the measurement that opened this. It is
  written on the `add-true-peak-measurement` branch and arrives in `main` with that change; every
  figure taken from it is quoted inline below, so this report stands on its own until then.

## 1. The architecture as it is today, read from the code

```
FILE
 └─ report          InspectAudioFileUseCase + AVFoundationAudioFilePropertyReader   (metadata only,
                                                                                     no samples)
 ├─ read #1 ──────► waveform      AVFoundationWaveformGenerator  →  WaveformEnvelopeAccumulator
 ├─ read #2 ──────► spectrogram   SpectrogramGeneration          →  SpectrogramAccumulator
 └─ read #3 ──────► signal levels SignalLevelMetricsGeneration   →  SignalLevelMetricsAccumulator

 (blocked candidate)
 └─ read #4 ──────► true peak     [not wired]                    →  TruePeakAccumulator
```

`SourceInspectionCoordinator.inspect(_:onUpdate:)` runs them **sequentially on one task**, inside one
security-scoped window, emitting `onUpdate` as each settles. The report is emitted *before* any sample
read begins.

| | waveform | spectrogram | signal levels | true peak |
| --- | --- | --- | --- | --- |
| Port | `WaveformGenerating` | `AudioDecoding` | `AudioDecoding` | (would be `AudioDecoding`) |
| Decoder created by | the coordinator, via `makeWaveformGenerator` | the coordinator, via `makeDecoder` | the coordinator, via `makeDecoder` | — |
| Owned by | the generator, inside Media | the `Generation` struct | the `Generation` struct | — |
| Consumes | `[Float]` per channel **+ start frame** | `PCMChunk` | `PCMChunk` | `PCMChunk` |
| Accumulator API | `accumulate(_:ofChannel:startingAtFrame:) throws` | `accumulate(_ chunk:)` | `accumulate(_ chunk:)` | `accumulate(_ chunk:)` |
| Error type | `WaveformError` (thrown) | remembered fault → `.failed` | remembered fault → `.failed` | — |
| Cancellation | `WaveformErrorCode.cancelled` | `Task.isCancelled` at chunk boundaries | same | same |
| Needs every sample | yes | yes | yes | yes |
| Needs frame position | **yes** (bucket mapping) | window boundaries counted from 0 | no | no |
| Look-ahead / behind | no | keeps `fftSize` of pending | no | **47 samples across boundaries** |
| Retained between chunks | bucket extremes, `O(buckets)` | pending window, `O(fftSize × channels)` | 5 totals per channel | 47 samples per channel |

**The finding that shapes everything below**: three of the four consume *exactly* the same thing — a
`PCMChunk` and the stream description — through the same port, with the same non-throwing
`accumulate` shape. The waveform is a different seam entirely.

## 2. What ADR-0016 actually protects

Reading decision 15 and its rejected alternative literally, and separating the properties from the
mechanism:

**Normative properties (must survive any change):**

1. **Independent failure** — one analysis failing must not fail another.
2. **Independent cancellation** — "cancelling one must not cancel the other".
3. **No analysis may depend on another having been requested.**
4. **Progressive delivery** — each result is shown when it settles; none waits on another.
5. **No analysis becomes a catch-all** — the rejected alternative's stated risk was "every future metric
   would widen the same operation".
6. Streaming, bounded memory, no framework type across a port, Analysis knows no AVFoundation.

**Mechanism chosen at the time**: one decoder instance per analysis.

**Was "a decoder per analysis" an invariant or an implementation?** ADR-0016 answers this itself, in the
same paragraph that rejected the shared pass:

> *"A single shared pass producing several results was considered and rejected… It remains possible
> **on top of** this seam if measurement ever justifies one."*

A decision that names the condition under which it may be revisited is stating an implementation, not
an invariant. The condition was *measurement*, and the measurement now exists. **"Independent analyses"
was the requirement; "independent decodes" was how it was met when a decode looked free.**

## 3. The cost that opened this

From `docs/spikes/2026-08-12-true-peak-end-to-end-cost.md`, ten minutes of stereo, Release: a fourth
read costs 23.5 % of a FLAC inspection and 23.6 % of an AAC one. The same measurement showed the
*existing* baseline already spends most of a compressed inspection decoding the same file three times.

## 4. Alternatives

| | Option | Verdict |
| --- | --- | --- |
| **A** | Status quo, one decoder per analysis | **Rejected** by the group-5 measurement. |
| **B** | **Shared sequential fan-out** — one read; each `PCMChunk` handed to every consumer in turn, same task | **Chosen.** Measured below. |
| **C** | Shared concurrent fan-out | **Rejected.** See §6. |
| **D** | Decode once into a PCM buffer, then let consumers read it independently | **Rejected outright.** Ten minutes of 44.1 kHz stereo is 212 MB of `Float`; memory would scale with duration, which every accumulator in this project is built to avoid. |
| **E** | Share only some consumers (e.g. levels + true peak, spectrogram separate) | **Rejected as the primary shape**, kept as a fallback. It removes one redundant decode instead of two — half the benefit for the same architectural work — and the spectrogram was audited to take the identical `PCMChunk`, so there is no reason to exclude it. |
| **F** | Migrate the waveform onto the seam and share all four | **Out of scope.** See §7. |

## 5. Is `PCMChunk` cheap to hand to several consumers?

Audited rather than assumed. `PCMChunk` is a `struct` holding `startFrame: Int` and
`channels: [[Float]]`. Swift arrays are copy-on-write and nothing here mutates a chunk, so passing the
same value to three consumers copies **a few words of struct**, never the samples. It is already
`Sendable`, already immutable (`let` throughout), and its lifetime is the callback's — no consumer may
retain it, and none does.

**No change to `PCMChunk` is needed, and none is proposed.**

## 6. Sequential or concurrent?

Measured DSP cost per consumer, ten minutes of stereo, Release, isolated from decode:

| consumer | DSP |
| --- | --- |
| spectrogram | 0.248 s |
| signal levels | 0.029 s |
| true peak | 0.487 s |
| **sum** | **0.764 s** |
| **measured shared-pass DSP** | **0.765 s** |

The shared pass costs exactly the sum — fan-out itself is free. Perfect parallelism could in principle
reduce 0.764 s to 0.487 s (the slowest consumer), **saving about 0.28 s** on a ten-minute stereo file.

**Rejected anyway, on the "minimum architecture" rule:**

- The three accumulators are **deliberately not `Sendable`** — each owns unsynchronised state, and
  `SpectrogramAccumulator` holds a `vDSP.DiscreteFourierTransform` that *cannot* be made `Sendable`.
  Concurrency would require actors around all three.
- `AudioDecoding`'s callback is **synchronous by contract**, and that is not stylistic: ADR-0010's
  security-scoped window is released when `inspect` returns, and an escaping/async consumer could
  outlive it. That contract would have to be reopened.
- ~6 500 chunks for a ten-minute file means ~6 500 task hops per consumer.

Paying three actors, a reopened port contract and per-chunk hops for 0.28 s — when sequential sharing
already recovers 0.9 s on the same file — is not the minimum architecture. **Recorded as a measured
ceiling, not as a plan.**

## 7. Is the waveform in or out? — **Out**

Not because sharing four would be worse, but because including it is a *different* change:

- It uses a **different port** (`WaveformGenerating`), whose implementation performs its own read inside
  Media.
- Its accumulator takes `(samples, ofChannel:, startingAtFrame:)` and **throws**, where the other three
  take a whole `PCMChunk` and cannot throw. It genuinely needs frame position; they do not.
- ADR-0016 left the migration deliberately un-done and conditional, and
  `add-static-spectrogram-visualization`'s group 9 carries its own stop rule permitting it to be
  deferred — which it was.

Migrating it is a prerequisite for including it, and doing both at once is two risky things in one
change. **Cost of leaving it out, measured**: the waveform keeps its own read — 0.319 s (WAV), 0.724 s
(FLAC), 0.628 s (AAC) in Release. That is the remaining redundancy, and it is a named follow-up rather
than an oversight.

Total reads therefore go from **3 today (or 4 with true peak) to 2**.

## 8. Measurements

Ten minutes of stereo, 44.1 kHz, minimum of three runs after a warm-up, on an otherwise idle machine.
"Current 3" is the real coordinator today; "current + TP" adds a fourth read; "shared" is report +
waveform (own read) + **one** read feeding spectrogram, signal levels and true peak.

### Release (`-O`)

| format | current 3 reads | current + TP (4 reads) | **shared (2 reads, incl. true peak)** | vs 4 reads | vs today |
| --- | --- | --- | --- | --- | --- |
| WAV | 0.698 s | 1.233 s | **1.138 s** | **−0.095 s** | +0.441 s |
| FLAC | 1.907 s | 2.848 s | **1.950 s** | **−0.898 s** | +0.044 s |
| AAC | 2.180 s | 3.194 s | **2.140 s** | **−1.054 s** | **−0.040 s** |

### Debug (`-Onone`)

| format | current 3 reads | current + TP (4 reads) | **shared** | vs 4 reads | vs today |
| --- | --- | --- | --- | --- | --- |
| WAV | 3.773 s | 4.905 s | **3.699 s** | **−1.206 s** | **−0.074 s** |
| FLAC | 4.927 s | 6.460 s | **4.439 s** | **−2.021 s** | **−0.488 s** |
| AAC | 4.643 s | 6.080 s | **4.253 s** | **−1.827 s** | **−0.390 s** |

### What the saving is, exactly

| format (Release) | one decode | two redundant decodes | measured saving vs 4 reads | recovered |
| --- | --- | --- | --- | --- |
| WAV | 0.049 s | 0.098 s | 0.095 s | **97 %** |
| FLAC | 0.448 s | 0.896 s | 0.898 s | **100 %** |
| AAC | 0.526 s | 1.052 s | 1.054 s | **100 %** |

**The saving is precisely the redundant decodes removed — no more, no less.** No hidden gain, no hidden
cost: the DSP is additive and unchanged, and fan-out costs nothing.

The consequence worth stating plainly: **for the compressed formats this product exists to examine,
sharing pays for the entire true-peak feature.** FLAC goes from 1.907 s to 1.950 s while *gaining* a
measurement; AAC gets slightly faster. In Debug — the build a developer runs — every format is faster
than today *with* true peak included.

WAV is the exception and is honest about it: its decode is nearly free, so there is little redundancy to
recover and true peak's own 0.49 s of DSP is visible. That cost is the feature's, not the
architecture's, and no amount of sharing removes it.

### Memory

Structural, not RSS. Nothing buffers: each accumulator's retained state is what it already was
(`O(buckets)`, `O(fftSize × channels)`, five totals per channel, 47 samples per channel), the chunk is
handed over and dropped, and no consumer retains one. Option D was rejected precisely because it is the
only alternative that would have broken this.

### The report

Unchanged and unaffected: it is emitted before any sample read (measured at ~1 ms in the previous
spike), and sharing changes only what happens after it.

## 9. Semantics the contract must fix

These are the questions sharing actually raises. Answers are the minimum that preserves §2's properties.

**Producer failure (the decoder).** No more PCM will exist, so every consumer that had not finished
ends without a result. Each reports **its own** failure outcome — the cause is shared but the outcomes
stay separate, because a caller reading one result must not have to know why another is missing.

**Consumer failure.** A consumer that cannot continue (its accumulator cannot be built for the stream,
or it detects a chunk that does not match) **stops accumulating and the read continues** for the
others. Its own outcome is `.failed`; every other consumer settles exactly as it would have. **This is
the property ADR-0016 protects, and it is preserved by construction rather than by separate decoders.**

**Global cancellation.** The user replacing the inspection cancels the read; every consumer reports
`.cancelled`, and no partial model escapes — the rule each `Generation` already follows.

**A consumer that no longer needs samples.** The read stops only when **every** consumer is done.
Today none finishes early — all three need every sample — so this is a rule stated in the contract, not
a mechanism to build.

**Stale results.** Unchanged. The flow already discards results from a superseded inspection, and
sharing returns one bundle to the same coordinator call rather than changing when results arrive.

**Backpressure.** Does not arise: the consumers are synchronous, on the reader's own task, so a slow
consumer slows the read directly rather than queueing behind it. That is a property of the port's
synchronous callback, and it is why option C would have had to introduce backpressure that does not
exist today.

## 10. Do we need a new abstraction?

Three structs having `accumulate(_ chunk: PCMChunk)` is **not** a reason to write a protocol. Tested
against the bar the change sets for itself:

- *Common need?* Yes — all three take the same input.
- *Common semantics?* Yes for `accumulate`; **no** for `finish()`, which returns three unrelated types
  with three different optionality rules.
- *Common lifecycle?* Yes.
- *Demonstrable reduction in duplication?* Small — one composition either way.
- *Benefit to tests?* None identified; the existing fakes work at the port, not at the accumulator.

A protocol would need an associated result type and would buy generic machinery for three known
consumers. **The proposal is a concrete composition** that owns the three accumulators and returns
their three outcomes — no protocol, no `PCMConsumer`, no pipeline abstraction. If a fourth and fifth
consumer with the same shape ever appear, that is when the abstraction earns itself.

## 11. Where it lives

`AudioInspectorApp`, beside `SpectrogramGeneration` and `SignalLevelMetricsGeneration` — the layer that
already composes ports with consumers. Analysis owns the DSP and must not learn about files; Media owns
decoding and must not learn about analyses; the domain knows none of it. **No dependency is inverted
and no module boundary moves.**

## 12. Does `AudioDecoding` change? — **No**

Audited against the rule "do not modify the port without a demonstrated incapacity":

- It already yields **one** sequence of `PCMChunk` per call, and the caller controls iteration through
  the returned disposition.
- Nothing in it names an analysis, and N consumers can receive each chunk without it knowing they
  exist — the callback is a closure the caller owns.
- The stream description arrives with every chunk, which is exactly what three accumulators need to
  size themselves.

No incapacity was found. **The port is untouched, and this change is built *on top of* it — the shape
ADR-0016 explicitly permitted.**

## 13. Decision

**Adopt option B: one read of the file feeding spectrogram, signal level metrics and true peak,
sequentially, in the same task, composed in `AudioInspectorApp`.** The waveform keeps its own read. The
port, `PCMChunk`, the domain models and all three accumulators are unchanged.

It recovers 97–100 % of the redundant decode cost, preserves every property ADR-0016 was protecting,
requires no new protocol, no new module, no concurrency and no port change — and is therefore the
minimum architecture that answers the measurement.

## 14. Limits of this evaluation

- One machine, one SDK, 44.1 kHz stereo, ten-minute files. Ratios carry forward; seconds do not.
- MP3 is absent — the fixture writer cannot produce one natively (a documented gap). FLAC and AAC stand
  in, and agree closely.
- The harness composed the shared pass by hand; the real change may differ in error plumbing, which
  cannot change the decode count but could add small constant costs.
- The concurrent ceiling (~0.28 s) is arithmetic from measured per-consumer DSP, not a measured
  implementation. It is stated so the option can be revisited on evidence rather than reopened on
  taste.
- **Nothing here was measured through the app's interface**, so no claim is made about perceived
  responsiveness beyond the report timing already measured.
