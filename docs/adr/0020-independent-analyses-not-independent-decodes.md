# ADR-0020: Independent analyses, not independent decodes

- **Status**: **Accepted** (2026-08-12). Promoted on the two conditions this record set for itself and
  on nothing else — the shared read exists against production code and the saving was reproduced
  there, and each isolation property is demonstrated by a test that fails when the property is broken.
  The evidence, including where it falls short of what was promised, is in **Promotion** below.
- **Date**: 2026-08-12
- **Deciders**: Project maintainer
- **Related**: **ADR-0016** (whose decision 15 this revisits under the condition that record wrote for
  itself; *referenced, never edited*), ADR-0010 (the security-scoped window that shapes the port's
  synchronous callback), ADR-0011, ADR-0015, ADR-0019,
  `docs/spikes/2026-08-12-true-peak-end-to-end-cost.md` (**written on the `add-true-peak-measurement`
  branch and reaching `main` with it** — the figures it supplies are quoted inline wherever they are
  used here, so nothing below depends on being able to open it),
  `docs/spikes/2026-08-12-shared-pcm-analysis-architecture.md`, changes `add-shared-pcm-read` and
  `add-true-peak-measurement`

## Context

ADR-0016 decision 15 reads: *"Both consumers use the seam, but as independent operations with
independent cancellation. A single shared pass producing waveform and spectrogram together was
rejected: it couples their lifetimes, complicates progressive delivery, and makes one operation the
place every future metric must be added."* Its rejected-alternatives section adds the condition:
*"It remains possible **on top of** this seam if measurement ever justifies one."*

Three things have happened since.

**The number of readers grew.** What was two analyses is three today (waveform, spectrogram, signal
level metrics) and would be four with true peak.

**The measurement arrived, and it disagrees with the assumption underneath the original decision.**
`add-true-peak-measurement`'s group 5 drove the real pipeline: for a ten-minute stereo file in Release,
one more read of the file — computing nothing on it — costs **23.5 % of a FLAC inspection and 23.6 % of
an AAC one**. The same measurement showed the *existing* three-read baseline already spends most of a
compressed inspection decoding the same file three times. The design that accepted a fourth read had
done so on a cited figure of 0.035 s per decode, which describes the cheapest uncompressed case; against
the real port a compressed decode is an order of magnitude more.

**The condition ADR-0016 named has therefore been met**, and its own stop rule fired rather than being
argued around.

The question this record answers is narrow and easy to get wrong: ADR-0016 protected something real,
and it would be a mistake to discard it along with the mechanism it happened to choose.

## Decision

1. **"Independent analyses" is the invariant. "Independent decodes" was an implementation.** ADR-0016's
   normative content is that one analysis may not fail, cancel, delay, or depend on another, that each
   result is delivered when it settles, and that no operation becomes the place every future metric is
   added. **None of that requires a decoder per analysis.** A record that names the condition under
   which it may be revisited — and that record did — is stating an implementation, not an invariant.

2. **Several analyses may share one read of the file, and the properties are preserved by construction
   rather than by separation.** Concretely, for a shared pass:
   - a **consumer's** failure stops that consumer and nothing else: the read continues and every other
     consumer settles exactly as it would have;
   - a **producer's** failure (the decoder) ends every consumer that had not finished, each reporting
     its **own** outcome — the cause is shared, the results stay separate;
   - **global cancellation** cancels the read and every consumer, and no partial model escapes;
   - the read stops only when **every** consumer is done, so one finishing early cannot starve another;
   - results are still delivered per analysis, not as one merged blob.

3. **The distinction that keeps decision 15's real fear answered.** ADR-0016 rejected a shared pass
   partly because it "makes one operation the place every future metric must be added". That risk is
   about a *widening operation*, not about a shared read: each analysis keeps its own accumulator, its
   own model, its own outcome and its own tests, and the shared pass composes them without knowing what
   any of them computes. A new metric adds a consumer; it does not widen an existing one.

4. **Sharing is built on top of `AudioDecoding`, which does not change.** The port already yields one
   sequence of chunks per call, the caller already controls iteration, and nothing in it names an
   analysis. An audit found no incapacity, so it is untouched — which is literally the shape ADR-0016
   permitted.

5. **Sequential fan-out, not concurrent.** The three accumulators are deliberately not `Sendable` (one
   owns a transform that cannot be), and the port's callback is synchronous because ADR-0010's
   security-scoped window is released when the inspection returns. Measured, perfect parallelism would
   save ~0.28 s on a ten-minute stereo file where sequential sharing already recovers ~0.9 s.
   Three actors and a reopened port contract for that is not justified. Recorded as a measured ceiling
   so it can be revisited on evidence.

6. **The waveform stays on its own read for now.** It uses a different port, its accumulator needs frame
   position and throws where the others do not, and ADR-0016 deliberately left its migration undone.
   Including it means migrating it first — two risky things in one change. Its own read is the
   remaining redundancy and is a named follow-up, not an oversight.

7. **No PCM is buffered.** Decoding once into a retained buffer would make memory scale with duration
   (212 MB for ten minutes of stereo) and is rejected outright, as every accumulator in this project
   already refuses to do.

## Alternatives considered

- **Keep a decoder per analysis (ADR-0016's mechanism, unchanged).** Simplest, and correct while a
  decode was nearly free. Rejected on the measurement: it is now a quarter of a compressed inspection
  per redundant read, and the redundancy grows with every metric added.
- **Decode once into a PCM buffer and let consumers read it afterwards.** Preserves complete
  independence, including the ability to add a consumer later without touching the read. Rejected: it
  is the one alternative that breaks bounded memory, which is a harder invariant than the one it
  protects.
- **Concurrent fan-out.** Would use more of the machine. Rejected — see decision 5 — on a measured
  ceiling that does not pay for the machinery.
- **Share only some consumers** (signal levels and true peak, leaving the spectrogram separate).
  Smaller blast radius. Rejected as the primary shape: it removes one redundant decode instead of two,
  for the same architectural work, and the spectrogram was audited to consume the identical chunk. Kept
  as a fallback if implementation finds something the audit missed.
- **Introduce a `PCMConsumer` protocol.** Tempting because three types have an `accumulate(_:)`.
  Rejected: their `finish()` returns three unrelated types with three different optionality rules, so
  the protocol needs an associated type and buys generic machinery for three known consumers. A
  concrete composition is smaller and no less testable.
- **Change `AudioDecoding` to deliver to many consumers itself.** Would make sharing the port's job.
  Rejected: it would make the decoder know that analyses exist, which is the boundary ADR-0011 and
  ADR-0016 both keep, and no incapacity of the current port was found.

## Consequences

### Positive

- Removes the redundancy that grows with every new sample-based metric: adding one now costs its own
  DSP and **no additional read**.
- Measured, it recovers **97–100 %** of the redundant decode cost — 0.9 s on a ten-minute FLAC in
  Release — which pays for the entire true-peak feature on the formats this product exists to examine.
- In Debug, the build a developer runs, every measured format is **faster than today** with true peak
  included.
- The properties ADR-0016 protected become explicit contract text and tests, rather than being implied
  by a mechanism.

### Negative / costs

- **The tests that assert the mechanism must be rewritten.** Several today script two decoders by call
  order and assert outright that "the coordinator gives each operation its own decoder instance". Under
  this record that sentence is no longer true, and those tests must assert the *property* — one
  consumer's failure or cancellation leaves the others untouched — instead of the arrangement. That is
  real work and a real risk of weakening a test while rewriting it.
- **A shared pass is a place where a future contributor could couple things by accident.** The
  composition must be written so a consumer cannot observe another's state, and nothing but review and
  tests enforces that.
- **One slow consumer now slows the read directly**, because the fan-out is synchronous. Today none is
  slow enough for that to matter; it is a property to remember rather than a problem observed.
- **The waveform's own read remains**, so the redundancy is reduced from three reads to two rather than
  to one. Honest but incomplete.
- **Uncompressed files gain almost nothing**, because their decode was already nearly free. The saving
  is real precisely where decoding is expensive, and this record does not pretend otherwise.

### Neutral

- No module boundary moves, no port changes, no domain type changes, and no dependency is inverted.
- ADR-0016 remains in force in every other respect, including its port design, its module placement and
  its refusal to let the drawing interpret what it shows.

## Promotion — what was actually demonstrated, and what was not

Recorded when this moved from `Proposed` to `Accepted`, on `add-shared-pcm-read` groups 3 and 4. The
measurements are in `docs/spikes/2026-08-12-shared-pcm-analysis-architecture.md` §15, which is
appended to the spike rather than replacing it, so the pre-implementation evaluation and its
production confirmation can be read against each other.

**The saving reproduced against production code.** The real coordinator, the real AVFoundation
adapters and the real accumulators, ten minutes of stereo, six runs per cell, Debug and Release. The
pipeline went from three reads to two, so **one** redundant decode was removed, and one decode's worth
of time disappeared: Release 0.06 s (WAV) / 0.73 s (FLAC) / 0.56 s (AAC), Debug 0.69 / 1.39 / 1.10 s.
Expressed as this record's own criterion, the recovery lands between **98 % and 107 %** across the six
cells, averaging 103.6 % against a run-to-run spread of 1–7 %. **The figures above 100 % are noise, not
a second decode**: only one was removed, and claiming more would be reading the spread as signal.

Three further facts were checked rather than assumed: the shared result is **identical value for
value** to the pre-change result on real files of each format; the pipeline opens **exactly two**
sample reads, counted at the adapters; and the process footprint during the read grew from 17 MB to
22 MB when the audio grew ten-fold, against the 212 MB the rejected buffering alternative would have
needed.

**The isolation properties, and the one that has no reachable input.** Decision 2 lists five. Four are
demonstrated by tests that were shown to fail when the property is broken — three negative controls,
each reverted in full, each breaking exactly the tests that name its property: a consumer's failure
leaves the other's *whole outcome* identical to a control run and the read still finishes; a
producer's failure ends every consumer with its own outcome and publishes nothing partial; global
cancellation, forced deterministically with a handshake mid-read, cancels everything and lets no
partial model escape; results are still delivered per analysis.

The fifth — *the read stops only when every consumer is done, so one finishing early cannot starve
another* — **is not demonstrated by test, because it has no reachable input**: both consumers need
every sample, so none can finish early. Its reachable half (a consumer leaving the read does not end
it for the others) is tested. The rest remains contract text, exactly as `design.md` §3 declared
before implementation, and the asymmetry is pinned by a test that starts failing when it changes.
**This is the one respect in which the promotion is weaker than "every property demonstrated by
test", and it is recorded rather than glossed.**

**Not claimed.** The second redundant decode does not exist on this branch: true peak is not wired
here, so the four-reads-to-two figures in the spike's §8 remain a projection until
`add-true-peak-measurement` group 6 lands. Nothing was measured through the app's interface.

## Follow-ups

- **Promotion criteria** (see Status): the saving reproduced against production code, and each
  isolation property demonstrated by a test that fails when the property is broken.
- **The waveform's migration onto the seam** — already deferred by ADR-0016 and by
  `add-static-spectrogram-visualization`'s group 9 — becomes the obvious next reduction once this
  lands, taking two reads to one. Nothing here authorises it.
- **Concurrent fan-out** stays available with a measured ceiling attached (~0.28 s on a ten-minute
  stereo file). Reopening it requires evidence that the ceiling has grown, not a preference.
- **`add-true-peak-measurement`'s group 6** resumes once this lands, wiring true peak as a consumer of
  the shared read rather than as a fourth decode. Its model, accumulator, methodology and tests are
  finished and are not to be redesigned; if wiring them required changing `TruePeakAccumulator`, that
  would be evidence this architecture is wrong and would have to be justified before proceeding.
