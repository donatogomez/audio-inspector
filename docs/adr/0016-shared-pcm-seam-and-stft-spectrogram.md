# ADR-0016: Shared chunked PCM decoding seam and the STFT spectrogram model

- **Status**: **Proposed.** It stays Proposed until two things are true: the format matrix passes
  against the production code (change `add-static-spectrogram-visualization`, group 8, with MP3 gated
  and not counted as CI coverage), and the manual validation of the resulting surface is performed
  (group 10). Partial evidence does not promote it.
- **Date**: 2026-08-06
- **Deciders**: Project maintainer
- **Related**: **ADR-0015** (native PCM sample reading — this ADR executes the reversal condition it
  wrote for itself; *referenced, not edited*), ADR-0003, ADR-0005, ADR-0009, ADR-0010, ADR-0011,
  `docs/spikes/2026-08-06-static-spectrogram-validation.md`, `docs/architecture.md`,
  `docs/concurrency.md`, change `add-static-spectrogram-visualization`

## Context

The product's central question — *is this "lossless" file really lossless?* — is answered in practice by
looking at where a file's energy stops. Nothing in the app can show that today: the technical properties
are metadata, and the amplitude envelope collapses frequency entirely.

ADR-0015 deliberately kept the waveform's reduction inside `AudioInspectorMedia` and recorded exactly
what would overturn that:

> *"the first level metric or the first FFT needs the same decoded stream. At that point the
> chunked-decode port becomes a real seam, `AudioDecoding` is introduced, and the reduction moves to
> `AudioInspectorAnalysis` behind it. That change should be a move, not a rewrite."*

**This is that first FFT.** The condition was written in advance precisely so this moment would not be
argued about, and `docs/architecture.md` has named `AudioDecoding` among the intended ports since the
beginning.

The spike in `docs/spikes/2026-08-06-static-spectrogram-validation.md` ran **before** this record — 67
checks, 0 failures — and three of its findings changed the design rather than confirming it.

## Decision

**Introduce a shared chunked PCM decoding seam owned by the domain, put the STFT and its reduction in
`AudioInspectorAnalysis` behind it, and derive a bounded, absolutely-scaled spectral model that
interprets nothing.** Concretely:

1. **`AudioDecoding` belongs to the domain.** A small `Sendable` port taking `AudioFileReference` and
   yielding PCM in bounded, cancellable chunks. No `AVAudioFile`, `AVAudioPCMBuffer`, `AVAudioFormat`,
   `NSError` or `OSStatus` in its signature (ADR-0011). The `URL` reaches the adapter through its
   constructor seam, because the domain reference carries no location (ADR-0010).

2. **Media owns AVFoundation and hands out chunks.** One adapter, the only place `AVAudioFile` appears,
   consuming exactly `buffer.frameLength` and never `frameCapacity` — the invariant ADR-0015 exists for.

3. **Analysis owns the STFT and the reduction.** `AudioInspectorAnalysis` stops being empty because a
   real seam finally exists, not because a module was waiting to be filled (ADR-0005, principle #12).
   **No Accelerate type crosses a port**: `DSPSplitComplex`, `vDSP.*` and the transform setup never
   appear in a signature the domain or a feature can see. `FeatureAnalysis` draws, and knows only the
   domain model.

4. **`vDSP.DiscreteFourierTransform`, not `vDSP.DFT`.** The latter is deprecated in the current SDK,
   which says so in a compiler warning naming its replacement. `.complexReal` is the variant for real
   audio.

5. **The transform setup is not `Sendable`, so it is confined.** Measured: neither
   `vDSP.DiscreteFourierTransform<Float>` nor `vDSP.FFT<DSPSplitComplex>` conforms, and the compiler
   rejects the attempt under Swift 6. It is therefore created and consumed **inside one `nonisolated
   async` operation**, reused for every frame of every channel, and never stored on a `Sendable` type,
   cached globally or shared across an isolation boundary. **No `@unchecked Sendable`.** Recreating it
   per frame was measured at **10×** the cost, so reuse within the operation is part of the decision,
   not an optimisation left to taste.

6. **FFT 2048, hop 512, Hann denormalised.** 2048 gives a 21.5 Hz bin at 44.1 kHz — far finer than
   needed to separate a 19 kHz cutoff from a 20 kHz one — and hop 512 leaves no audio unexamined
   between windows. Hann keeps spectral leakage low, without which an abrupt edge smears and stops being
   readable.

7. **Absolute scale, never normalised.** Magnitude scaled by `1 / windowSum` (verified to read a known
   tone with **0.000 dB** error; `2 / windowSum` is the natural mistake and reads 6 dB high), referenced
   to full scale, converted with 20·log10, floored at **−120 dBFS**. **No per-file normalisation**: the
   user compares copies of the same music, and scaling each file to its own peak makes two files
   incomparable. Same invariant as the amplitude envelope.

8. **At most 1024 columns × 512 bands, reduced by maximum in both axes.** 2.00 MiB of `Float`,
   independent of duration. **Maximum, not mean**: the mean buried a 20 ms transient by **8.74 dB**, and
   in the frequency axis an average lets a loud neighbour contaminate an empty band — which is exactly
   what would blur the cutoff being looked for.

9. **Linear frequency, full Nyquist, always.** Linear because the artefact is a horizontal wall at
   16–20 kHz, which a logarithmic axis compresses into an unreadable sliver. Full Nyquist — including
   48, 96 and 192 kHz — because the empty space above 22 kHz in a file claiming 96 kHz **is the
   evidence**; cropping it would hide the "24/96 that came from a CD" case `vision.md` names.

10. **Channels are transformed separately and combined by maximum per bin, in the frequency domain.**
    The first proposal said "maximum" without naming the domain. Combining **samples** was measured to
    invent **247 spurious bands** with two pure tones, shifting peaks by up to 4.25 dB. For an instrument
    whose whole job is to show where energy stops, invented energy high up could conceal a real cutoff.
    The result is a **combined** spectrogram: **not a mono mix, not a downmix**, and not described as one
    anywhere in code, tests or UI.

11. **Channels are processed sequentially**, sharing the one setup. Parallelism would need a setup per
    channel — the type is not `Sendable` — for a gain not demonstrated. Measured cost: **1.6–1.7× for
    stereo**. **No timing is promised for multichannel.**

12. **The final incomplete window is discarded, never zero-padded.** Padding read a 0.5 tone at
    **−12.47 dBFS** instead of −6.02. At most `fftSize - 1` frames — 46 ms at 44.1 kHz — go undrawn,
    which is preferable to drawing something the file does not contain.

13. **Non-finite samples are refused at the domain boundary.** A single NaN did not leak a non-finite
    value into the model but **silently collapsed 184 cells to the floor**, so a corrupted region would
    read as an absence of energy. The clamp must not be what hides it.

14. **The spectrogram travels beside `InspectionReport`, never inside it** (ADR-0009), and never reaches
    the `schemaVersion` 1 export. Failure or absence is a first-class outcome that emits no inspection
    warning and never degrades the inspection status.

15. **Both consumers use the seam, but as independent operations** with independent cancellation. A
    single shared pass producing waveform and spectrogram together was rejected: it couples their
    lifetimes, complicates progressive delivery, and makes one operation the place every future metric
    must be added.

16. **What the drawing may say is bounded by what it can support.** It may state that energy is present
    or absent above a frequency, that an edge is abrupt, that bands or gaps appear. It may **not** state
    or imply that a file is lossy, transcoded, fake or poor, name a probable encoder or bitrate, or be
    presented as a measurement. Two measured limits back this: **scalloping loss up to 1.42 dB** and an
    **edge uncertainty of about one reduced band** (±43 Hz at 44.1 kHz, ±188 Hz at 192 kHz).

17. **Automatic detection of lossy origin is out of scope**, and belongs to a later capability working
    with observable reasons, alternative explanations and confidence — never a verdict.

## Alternatives considered

- **Keeping the waveform's private read and giving the spectrogram its own.** Simplest, no migration
  risk. Rejected: it decodes the same file twice for no reason and contradicts the reversal condition
  ADR-0015 wrote down. The migration is nonetheless made **conditional and last** (group 9), because
  breaking working code to satisfy tidiness would be its own mistake.
- **One pass producing both representations.** Looks efficient. Rejected: cancelling one would cancel the
  other, progressive delivery becomes awkward, and every future metric would widen the same operation
  into a catch-all. It remains possible *on top of* this seam if measurement ever justifies it.
- **`vDSP.DFT`.** Deprecated in the current SDK. Rejected on that alone.
- **Combining channels in the time domain.** Cheaper — one transform instead of one per channel — and
  wrong. Kept as a reproducible negative control in the spike rather than as an option.
- **Mean reduction.** Smoother-looking. Rejected: it buries transients by 8.74 dB and blurs the edge the
  whole feature exists to show.
- **Logarithmic frequency axis.** Conventional in music software and better for pitch. Rejected: it
  compresses 15–22 kHz into a sliver, and that band is the one being examined.
- **Cropping the axis to the audible band at high sample rates.** Would use the canvas better. Rejected:
  the empty upper range is evidence, and hiding it would be an interpretive act.
- **Spek's colour palette.** Familiar to the audience. Rejected: it passes through green and red, and
  colour in this product never means good or bad. **Measured on 2026-08-07 and rejected a second time
  on independent grounds** (`docs/spikes/2026-08-07-spectrogram-performance-presentation-diagnosis.md`,
  §F): that ramp is **not monotonic in luminance**. Sampled with this project's own Rec. 709 formula it
  rises to 0.757 at yellow, falls to 0.642 at orange and 0.399 at red, then jumps to white — so a loud
  red band would read as *quieter* than a mid-level yellow one in greyscale, and for a reader with
  colour vision deficiency. The standing rule and the measurement reach the same answer for different
  reasons, which is the strongest form this record can take.
- **Normalising per file.** Would make every spectrogram look well-exposed. Rejected outright: it
  destroys comparability between copies, which is the user's actual task.

## Consequences

### Positive

- One decoding path serves every future sample-based analysis; the next metric adds a consumer rather
  than another read.
- `AudioInspectorAnalysis` gains real contents behind a real seam, as designed.
- The model is bounded and view-independent: 2.00 MiB whatever the duration, and resizing never decodes
  or transforms again.
- The absolute scale makes two files directly comparable, which is what the user is actually doing.
- A spectral cutoff is visible at a glance, and the container does not change what is observed — WAV and
  FLAC of the same audio produce identical models.

### Negative / costs

- **Stereo costs 1.6–1.7×**, and more channels cost proportionally more. No timing is promised for
  multichannel.
- **At 192 kHz most of the canvas is empty.** The accepted price of showing full Nyquist.
- **The maximum could make dense impulsive noise look like a surface.** Bounded in the case measured —
  an isolated click lights 3 of 1024 columns — but a densely impulsive file was not tested.
- **The waveform migration touches code that is closed and green**, which is why it is last, conditional
  and separately committed, with a stop rule that permits deferring it.
- **Analysis gains Accelerate**, its first framework dependency — a system framework, already scoped to
  this module alone by `check-boundaries.sh` rule 7.
- **One OS/SDK, one machine.** Timings do not carry forward; the semantic conclusions do.
- **This slice shows the evidence and refuses to interpret it**, which some users will read as an
  unfinished feature. Accepted deliberately: showing and concluding are different jobs.

### Neutral

- Establishes the pattern for every future sample-based analysis: domain-owned decoding port, platform
  code in Media, pure DSP in Analysis, drawing in a feature.
- ADR-0015's reduction placement is superseded **in direction** by this record, exactly as it
  anticipated; ADR-0015 itself is unchanged and keeps its own status.

## Follow-ups

- **Promotion criteria** (see Status): the format matrix passing against production code, plus the
  manual validation in group 10. Until then this ADR asserts a direction, not a proven result.
- **`Spike/validate-static-spectrogram` is deleted** once this ADR is Accepted and the slice's own tests
  cover its observations; the deletion criterion is written into the spike report.
- **The waveform's migration may be deferred** to its own change under group 9's stop rule, and if it is,
  that is recorded rather than quietly dropped.
- **Automatic lossy-origin detection** is a future capability, and must carry evidence, alternative
  explanations and confidence rather than a verdict. Nothing in this ADR authorises it.
