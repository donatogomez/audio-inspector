## Context

The waveform slice established a sample-reading seam, but deliberately kept the reduction inside
`AudioInspectorMedia`, because streaming PCM across a port with only one consumer would have been a
speculative abstraction. ADR-0015 wrote down exactly what would overturn that: a second consumer of the
same decoded stream. **This slice is that second consumer**, and the change it forces was designed in
advance rather than discovered now.

Unlike the waveform slice, the DSP here is not a fold that can hide inside a read. An STFT needs
overlapping windows, a transform setup, a window function and a reduction — the pure DSP that
`AudioInspectorAnalysis` was reserved for since `docs/architecture.md` was written.

**Nothing in this design is a hypothesis.** The spike in
`docs/spikes/2026-08-06-static-spectrogram-validation.md` measured every constant, and three of its
findings *changed* the design before it was written. Where a decision below cites a number, that number
came from a run, not from convention.

### What the spike established, and what each finding forces

| Evidence | Consequence for this design |
| --- | --- |
| `vDSP.DFT` is deprecated; `vDSP.DiscreteFourierTransform` is the current API | Use the current one; no deprecated call enters production |
| Neither it nor `vDSP.FFT` is `Sendable` | The setup **cannot** cross an isolation boundary. It is created and consumed inside one `nonisolated async` operation. No `@unchecked Sendable`, no shared cache |
| Recreating the setup per frame costs **10×** | One setup per operation, reused for every frame of every channel |
| Amplitude scale `1 / windowSum` reads a known tone with **0.000 dB** error | The scale is fixed and testable; `2 / windowSum` is the natural mistake and reads 6 dB high |
| Combining channels in the **time** domain invented **247 spurious bands** | Channels are transformed **separately** and combined by maximum **per bin**. Costs 1.6–1.7× for stereo, accepted |
| The **mean** buried a 20 ms transient by **8.74 dB** | Reduction is by **maximum** in both axes |
| Zero-padding the last frame read a 0.5 tone at **−12.47 dBFS** | The final incomplete frame is **discarded**. At most 46 ms at 44.1 kHz goes undrawn |
| Cutoffs at 16/18/19/20/22 kHz separable at 44.1–192 kHz, narrowest margin 5 bands | 1024 × 512 is sufficient; the resolution is fixed rather than adaptive |
| A single NaN silently collapsed **184 cells** to the floor | The **domain** rejects non-finite samples at the boundary; the clamp must not be the thing that hides them |
| WAV and FLAC of the same audio produce **identical** models | The container changes nothing the drawing observes — worth asserting as a test |

## Goals / Non-Goals

**Goals:** introduce the shared decoding seam that ADR-0015 anticipated; put real DSP in Analysis
behind it; produce a bounded, view-independent spectral model that misrepresents nothing; draw it once
beside the report; keep the report and the JSON untouched; make a spectral cutoff visible at a glance.

**Non-Goals:** deciding what a cutoff *means*; any verdict about quality or provenance; playback, zoom,
scrubbing, selection; normalisation; persistence; export of the model; loudness or level metrics;
batch.

## Decisions

### 1. `AudioDecoding`, a domain-owned chunked PCM seam

A small `Sendable` protocol in `AudioInspectorDomain/Ports/`, taking `AudioFileReference` and yielding
PCM in bounded chunks with per-channel samples, cancellable at chunk boundaries. No `AVAudioFile`,
`AVAudioPCMBuffer`, `AVAudioFormat`, `NSError` or `OSStatus` in its signature (ADR-0011). The `URL`
reaches the adapter through its constructor seam, because the domain reference carries no location
(ADR-0010).

**Why now and not before:** with one consumer it would have been an abstraction with a single user. With
two it is a seam, and ADR-0015 said so in writing.

**Exact shape deferred to group 2** — a closure-fed fold, an `AsyncSequence` of chunks, or a scoped
`withDecodedChunks` — because the choice depends on how cancellation and the security-scoped window
compose, and inventing it here would be guessing ahead of the code.

### 2. `vDSP.DiscreteFourierTransform`, confined

`vDSP.DFT` is deprecated in the current SDK. The replacement is used with `transformType: .complexReal`,
the right variant for real audio.

**The setup is not `Sendable`, so it is confined**: created inside the operation that uses it, reused
for every frame of every channel, dropped when the operation ends. Not a stored property of a
`Sendable` type, not a global, not a cache. The spike's package builds under Swift 6 with
`-warnings-as-errors` and no `@unchecked Sendable`, which is the proof that this shape works.

### 3. The STFT and the reduction live in Analysis

`AudioInspectorAnalysis` gains its first real contents. Unlike the waveform's min/max fold, this is a
transform over buffers — precisely what the module was reserved for.

**No Accelerate type crosses a port.** Analysis takes `[Float]` per channel and returns domain values;
`DSPSplitComplex`, `vDSP.*` and the setup never appear in a signature the domain or a feature can see.

### 4. The model

- **Bounded and fixed**: at most **1024 columns × 512 bands**, 2.00 MiB of `Float`, independent of
  duration. Measured, not estimated.
- **Absolute dBFS**, reference 1.0, magnitude scaled by `1 / windowSum`, floor **−120 dBFS**. **No
  normalisation, per file or otherwise** — the user compares copies of the same music, and scaling each
  file to its own peak makes two files incomparable. This is the same invariant the envelope carries.
- **Reduced by maximum in both axes.** The mean buries transients (8.74 dB, measured) and, in the
  frequency axis, lets a loud neighbour contaminate an empty band — which is exactly what would blur a
  cutoff.
- **Channels transformed separately, combined by maximum per bin.** A **combined** spectrogram across
  channels: never a mono mix, never a downmix, and not described as one anywhere.
- **The final incomplete frame is discarded.** Padding invents samples and understates level.
- **Non-finite samples are refused at the domain boundary**, not absorbed by the clamp.

### 5. Full Nyquist, linear

The vertical axis runs from 0 Hz to the file's own Nyquist, **always**, including 48, 96 and 192 kHz,
and the scale is **linear**.

**Linear** because the artefact being looked for is a horizontal wall at 16–20 kHz; on a logarithmic
axis that whole region compresses into the top sliver and stops being readable.

**Full Nyquist** because the empty space above 22 kHz in a file that claims 96 kHz **is the evidence** —
it is the "24/96 that came from a CD" case named in `vision.md`. Cropping the axis would be an
interpretive act that hides exactly what a collector is looking for.

The cost is accepted and stated: at 192 kHz the interesting region occupies the bottom tenth of the
drawing. **No axis modes, no zoom and no "audible band" crop in this slice.**

### 6. Colour

A perceptual ramp built by hand, no dependency: **strictly increasing in luminance**. Monotonic
luminance keeps it readable in greyscale and for colour vision deficiency, and makes intensity read as
intensity.

**Revised on 2026-08-07, after manual observation and measurement**
(`docs/spikes/2026-08-07-spectrogram-performance-presentation-diagnosis.md`, §F). The first ramp — dark
background → deep blue → cyan → pale yellow/white — was measured to be sound on luminance (0.023 →
0.974, with 57 % of the range across −90…−30 dBFS) but **weak on hue travel**: four of eight sampled
levels sat in the cyan-teal family, and between −60 and −15 dBFS the hue barely moved, so levels 45 dB
apart could read as similar colours. The ramp now runs **near-black → indigo → blue → teal → green →
yellow-green → near-white**, which keeps 53.8 % of the luminance range on −90…−30 dBFS while moving
through five distinguishable hues instead of one. The first ramp is not deleted from the record: it was
correct on the criterion it was designed against, and the criterion turned out to be incomplete.

**Not Spek's palette**, and the rejection is now measured rather than argued from principle alone.
Spek's ramp passes through green and red, and this project has a standing rule that colour never says
"good" or "bad" — but it is also **not monotonic in luminance**: sampled with the project's own Rec. 709
formula it rises to 0.757 at yellow, falls to 0.642 at orange and 0.399 at red, then jumps to white. A
loud red band would read as *quieter* than a mid-level yellow one in greyscale. The rule and the
measurement agree.

A numeric **−120…0 dBFS legend is mandatory**: without it a gradient means nothing. The legend samples
the **same** ramp function the cells use, so the two cannot drift. Loading, absence and failure are said
in **text**, never by colour alone.

### 7. Beside the report, never inside it

The spectrogram is neither a technical property nor a warning nor a status, so it does not enter
`InspectionReport` (ADR-0009) and never reaches the `schemaVersion` 1 export. It travels beside the
report exactly as the waveform does, with absence, failure and cancellation as first-class outcomes,
and a failure to produce it never degrades the inspection status or emits a warning.

### 8. Two consumers, one seam, independent operations

The waveform and the spectrogram both read through `AudioDecoding`, but as **separate operations with
separate cancellation**. A single shared pass producing both was considered and rejected: it couples
their lifetimes (cancelling one would cancel the other), complicates progressive delivery, and turns
one operation into the place every future metric has to be added. If a shared pass is ever justified by
measurement, it can be built on top of this seam later — the seam is what makes that possible, not the
other way round.

### 9. Migrating the waveform is conditional, last, and may be declined

The waveform currently reads for itself. Moving it onto the shared seam is the honest end state, and
group 9 does it — **but only if** it preserves the port's contract and every existing test without
coupling the two consumers, without weakening an assertion and without touching the UI. If it cannot,
it is **deferred to its own change and said so**, rather than forced to make this slice look tidy.
Leaving two reads temporarily is a declared cost, not an oversight.

### 10. What the drawing may and may not say

May: *there is little energy above about 16 kHz* · *there is an abrupt edge* · *there are bands or
gaps*.

May not: *this is an MP3* · *this FLAC is fake* · *this is a transcode* · *this is poor quality*.

Two measured limits back this up: **scalloping loss up to 1.42 dB** (Hann's theoretical maximum, hit
when a tone falls between bins) and an **edge uncertainty of about one reduced band** — ±43 Hz at
44.1 kHz, ±188 Hz at 192 kHz. The drawing is a picture of energy distribution, not a measurement, and
the surface must not present it as one.

A cutoff near 16.8 kHz is compatible with lossy encoding, with the master, and with deliberate
filtering. Separating those is the job of a later capability working with evidence, alternative
explanations and confidence.

## Risks / Trade-offs

- **Stereo costs 1.6–1.7×** and more channels cost proportionally more. Accepted; **no timing is
  promised for multichannel**. Sequential processing keeps transient memory bounded and avoids needing
  one transform setup per channel.
- **At 192 kHz most of the canvas is empty.** The consequence of showing full Nyquist, accepted for the
  evidence it preserves. Manual validation should look at it explicitly.
- **The maximum could, in principle, make sparse impulsive noise look like a surface.** Measured as
  bounded — an isolated click lights 3 of 1024 columns, the same as the mean — but a densely impulsive
  file was not tested and the limitation is recorded rather than hidden.
- **A NaN silently collapses cells to the floor** if the domain does not reject it first. The mitigation
  is a domain guard, not a UI check.
- **Migrating the waveform touches code that is closed and green.** Mitigated by making it last,
  conditional and separately committed, with an explicit stop rule.
- **Analysis gains Accelerate**, its first framework dependency. It is a system framework, already
  allowed by the boundary rules for this module alone, and enforced by `check-boundaries.sh` rule 7.

## Migration Plan

Additive. No stored data, no schema version, no wire-format change. A report produced before this
change presents identically afterwards with the spectrogram area simply absent. The only breaking edit
inside the package is the payload carried beside the report, internal to the flow and covered by
existing tests. If group 9 runs, the waveform's port implementation changes while its **contract** does
not.

## Open Questions

1. **The exact shape of `AudioDecoding`** — closure fold, `AsyncSequence`, or scoped accessor. Deferred
   to group 2, where cancellation and the security-scoped window decide it.
2. **Whether a separate `SpectrogramGenerating` port is needed at all**, or whether `AudioDecoding` plus
   a pure Analysis function is the whole seam. `docs/architecture.md` names the former, but introducing
   it "because the map says so" would be the speculative abstraction this project keeps refusing.
   Decided in group 2 with the code in hand.
3. **Whether a zero-frame file yields an empty model or no model**, mirroring how `WaveformEnvelope`
   settled the same question. Decided with the domain type in group 2.
