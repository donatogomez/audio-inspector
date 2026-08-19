# ADR-0023: Significant bandwidth as a measured fact, independent of the spectrogram

- **Status**: **Proposed.** It stays Proposed until three things are true: the threshold and persistence
  criterion are decided **from measurement on graded fixtures** rather than from the sharp-edged ones
  the motivating spike used; the impulse control passes against production code, so an isolated
  transient provably does not widen the reported band; and the surface has been validated by a person
  looking at it. Partial evidence does not promote it.
- **Date**: 2026-08-18
- **Deciders**: Project maintainer
- **Related**: **ADR-0016** (the STFT spectrogram this deliberately does *not* build on), ADR-0020 and
  **ADR-0021** (the shared read this joins as a sixth consumer), ADR-0006, ADR-0018, ADR-0019 and
  **ADR-0022** (the precedent for a self-describing measurement that emits no verdict),
  `docs/analysis-methodology.md`, change `add-significant-bandwidth-measurement`

## Context

`docs/roadmap.md` Phase 1b names *"the significant max frequency"* and it is the last item of that
phase unbuilt. It is also the indicator the product's own README uses to illustrate what Audio
Inspector is for — and, in the same breath, what it must never do: *"It will never just say 'fake
MP3.'"*

The obvious implementation is to read the highest lit band of the spectrogram that already exists. A
spike measured whether that works. It does not, and the measurements decided this record.

## Decision

1. **Significant bandwidth is a measured fact and emits no finding.** It reports the highest frequency
   carrying persistent energy above a stated threshold. It does not assert upsampling, transcoding,
   lossy provenance or a source codec, and it is not compared against the declared sample rate as a
   verdict. `CLAUDE.md` already forbids the shortcut — *"never assert transcoding from a single
   frequency cutoff"* — and this record does not create an exception to it.

2. **It is not derived from `Spectrogram`.** Three independent reasons, each measured rather than
   argued:

   - **The spectrogram reduces over time by maximum.** A file of digital silence containing one impulse
     reports **23 977 Hz** under a max-over-time reading and **0 Hz** under a percentile. Persistence —
     which `docs/analysis-methodology.md` explicitly requires — is destroyed by the reduction.
   - **Its resolution is a presentation cap, and the answer moves with the sample rate.** 512 bands span
     0–Nyquist, so band width scales with the rate: the same 16 kHz-limited signal reads 16 042 Hz at
     44.1 kHz and **16 594 Hz at 192 kHz**.
   - **Those caps are documented as free to change**: *"Caps, not promised resolutions: neither is
     exported, persisted or shown, so both can change without breaking anything."* A domain measurement
     may not depend on a constant whose own comment invites changing it.

3. **It is a sixth consumer of the one shared PCM read**, with its own STFT at full bin resolution.
   Still one read of the file (ADR-0021), no new decoder, no new dependency.

4. **The methodology is decided before the accumulator exists.** The threshold and the persistence
   fraction were **undetermined** as this was first written, and the spike said so rather than guessing:
   its fixtures had infinitely sharp edges, so an 80 dB threshold sweep moved the answer only 328 Hz and
   discriminated nothing. `add-loudness-measurement` settled its constants first and that is why they
   survived; this follows it.

   **Since measured**, on graded fixtures, in
   `docs/spikes/2026-08-19-significant-bandwidth-methodology.md`: the threshold is **−50 dB relative to
   the loudest bin in the same analysis window**, and the persistence criterion is **presence in ≥ 10 %
   of eligible windows**. This does not promote the record — see the status above, whose other two
   conditions are untouched.

5. **Threshold and persistence are not sufficient, and the two rules that complete them are named.**
   Measured: *no* relative reference at *any* threshold and *any* persistence reports absence for digital
   silence, because on silence every bin and every relative reference sit at the same numerical floor. A
   **window-eligibility gate** — a window whose own spectral peak is more than 60 dB below the file's
   global spectral peak contributes to neither the count nor the denominator — is gain-invariant by
   construction and is inert on every fixture except one that is partly digital silence. An **absolute
   silence floor** at −120 dBFS on the global spectral peak is not gain-invariant and is not meant to be:
   it detects the absence of audio rather than measuring bandwidth. Gain invariance was measured to hold
   over an 80 dB range above that floor.

6. **This is not a filter-knee detector, and the record says so before a surface can imply it.** On a
   graded roll-off the measurement reports where content stops crossing the threshold, which is not the
   filter's corner. At 48 kHz with a 16 kHz knee, a roll-off gentler than roughly 85 dB per octave has no
   edge below Nyquist at all and the reported value is the top of the band.

7. **The value carries the resolution it was measured at**, and no surface may print more precision than
   that supports. A bin is 21.5 Hz wide at 44.1 kHz and 93.8 Hz at 192 kHz, and a Hann window spreads a
   tone beyond one bin: the overshoot above a known hard cut-off measures **≈ 4 bins, one-sided upward**,
   consistently at four different bin widths. `21.73 kHz` would be a fabricated digit.

8. **Absence is an absence.** No audio, shorter than one window, or nothing meeting the criterion yields
   no value. Zero is not a result and **Nyquist is not a result** — the same rule that made −70 LUFS a
   gate rather than a reading (ADR-0022 §6).

9. **The shared STFT stage is deferred and named.** `SpectrogramAccumulator` already computes 1025 bins
   per hop and throws the resolution away; sharing that stage would make this nearly free. It is the
   right end state and the wrong first step — it would land a refactor inside a feature and design for
   one consumer while guessing at the second. It waits for `average spectrum` to give it a second.

## Alternatives considered

- **Highest lit spectrogram band.** Rejected on the three measurements above. It is the cheapest option
  and the one a reader will keep proposing, which is why the numbers are recorded here rather than left
  in a spike.
- **Spectral roll-off percentile** (the frequency below which 99 % of energy lies). Rejected: dominated
  by the loud low end, so a strong bass note places it near 1 kHz whatever exists above. It measures
  spectral balance, not extent.
- **An absolute dBFS threshold.** Rejected: it makes the answer a function of programme level rather
  than of content, so the same master at two gains reports two bandwidths. Measured: attenuating one file
  by 20 dB moved its answer by 4.4 kHz.
- **A threshold relative to the file's overall spectral peak.** Rejected on measurement: a full-scale
  event occupying 2 % of a file raises that peak by 33 dB, and a real high band present *throughout* is
  then lost — 16 008 Hz reported where the answer is 20 000.
- **A threshold relative to the global spectral RMS, or to a robust 95th percentile of all bins.**
  Rejected: neither is a level. Both are statistics over the bin population, so they move when the number
  of empty bins moves — measured drift across FFT sizes, for identical content, of 6.0 dB and **41.8 dB**
  respectively, against 0.0 dB for a peak. A threshold relative to them is not a fixed sensitivity.
- **A threshold relative to the file's gated loudness (BS.1770-5).** Measured with the published 48 kHz
  weighting rather than argued away, and it passes every pre-registered constraint. Rejected because the
  quantity is not commensurable with the one being thresholded: the offset between broadband gated energy
  and a single bin's magnitude spread **32.6 dB** across the fixtures, so one constant would mean a 31 dB
  different sensitivity on two different files. It would also couple this measurement to the loudness
  gate, and at rates other than 48 kHz to this project's own derivation of the weighting.
- **Reporting Nyquist when nothing is found.** Rejected as the floor mistake this project has already
  made once and refused: it turns "not measurable" into a number.
- **Shipping an upsampling indicator with it.** Rejected: one indicator is not an evidence engine, and
  the methodology requires several independent ones with alternative explanations.

## Consequences

### Positive
- The first genuine *indicator* the evidence engine will need, built as a fact so it cannot become a
  verdict by accident.
- Completes the roadmap's Phase 1b.
- Reuses the fixture generator, the format matrix and the MP3 band-limit evidence already built and
  proved.

### Negative / costs
- **A sixth FFT.** Until the shared stage exists this computes a transform the spectrogram has already
  computed and discarded. Measured baseline for the five-consumer pass: 1.02 s per 60 s of stereo at
  48 kHz, 3.54 s at 192 kHz, in Debug.
- **`SourceInspectionOutcome` reaches six payloads**, and its own note says a sixth "should not simply
  be appended". The change must decide the container or record why not.
- **No published reference exists** for this quantity. Unlike loudness there is no Tech 3341 to be
  measured against, so the primary evidence is analytic fixtures and FFmpeg is corroboration at best.
- **The most useful reading is the one hardest to defend.** A 96 kHz file limited near 22 kHz is
  precisely what a user wants explained, and precisely what this must not explain yet.

### Neutral
- No port changes, no export version change, no new dependency, and no second read.
