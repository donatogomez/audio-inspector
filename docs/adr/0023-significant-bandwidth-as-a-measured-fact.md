# ADR-0023: Significant bandwidth as a measured fact, independent of the spectrogram

- **Status**: **Proposed.** Of its three promotion conditions the first is now **met** — the threshold,
  the persistence criterion, the analysis window, the reporting contract and the eligibility rule are
  all decided from measurement on graded fixtures, and the full rule set passes twelve of twelve
  pre-registered constraints in a single validation. Two remain: the impulse control must pass against
  **production** code, so an isolated transient provably does not widen the reported band, and the
  surface must be validated by a person looking at it. Partial evidence does not promote it.
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

5. **The measurement declares what it is looking at, and the declaration is part of it.**
   Measured: a window containing only a noise floor is indistinguishable, *from inside itself*, from one
   containing only quiet music. Spectral flatness cannot tell them apart — tape hiss and musical "air"
   at the same per-bin level both measure 0.564, to three decimals — and neither can reading the result
   at several persistence levels. The difference exists only in comparison with the rest of the file,
   and every such comparison is a **dynamic-range budget**.

   So the budget is declared rather than discovered: **a window contributes only if it sits within
   60 dB of the file's loudest spectral moment.** Its cost is one sentence, and both halves of it are
   the same rule:

   > Content in passages more than 60 dB below a file's loudest spectral moment is not measured, and a
   > noise floor further down than that does not count as content.

   Sixty decibels covers the macro-dynamics of the material this product is pointed at, with margin,
   and excludes every noise floor measured. It is not a physical boundary and is not presented as one —
   which is why **the metric is named `programme bandwidth`, stated in full as "programme bandwidth,
   within 60 dB of programme peak"**. The name carries the budget so that the figure cannot be read as
   a claim about everything in the file, and so that it stays true if the budget is ever revised.

6. **Absence needs no rule at all, and the earlier ones were artefacts.** A window of zeros transforms
   to magnitude exactly zero, so a window that carries no energy is ineligible on its own and a file of
   silence yields absence with nothing added. The −120 dBFS floor is deleted; so is the file-level
   energy test that briefly replaced it. Both existed only because the spike's first harness floored
   magnitudes at 1e-12, which turned a silent window into a −240 dB window *with a reference*.
   **A production accumulator must therefore not clamp its magnitudes** — that is a methodological
   requirement, not an implementation detail.

7. **This is not a filter-knee detector, and the record says so before a surface can imply it.** On a
   graded roll-off the measurement reports where content stops crossing the threshold, which is not the
   filter's corner. At 48 kHz with a 16 kHz knee, a roll-off gentler than roughly 85 dB per octave has no
   edge below Nyquist at all and the reported value is the top of the band.

8. **The value carries the resolution it was measured at**, and no surface may print more precision than
   that supports. `21.73 kHz` would be a fabricated digit.

   The uncertainty is now **derived rather than observed**. A Hann window's transform is
   `|W(d)| = |sin(πd)| / (π|d||d²−1|)` — verified against the true DTFT to 0.000 dB — whose skirt falls
   as `1/d³`. A relative threshold `T` therefore stays above the skirt out to
   **`d(T) ≈ (1 / (π·10^(T/20)))^(1/3)` bins**, which is **4.72 bins at −50 dB**. That, and not the bin
   width, not the main lobe, and not bin quantisation, is what the observed overshoot was: it is the only
   one of the four that moves with the threshold, and the measurement moves with it exactly.

   Consequences the record fixes:

   - **The reported frequency is an upper bound on where content ends**, overstating it by one bin when
     the edge falls on a bin and by up to `d(T)` bins when it does not — one-sided, upward, and dependent
     on the content's sub-bin position, which is unknowable from the result.
   - **An interval contract was derived and then falsified** and must not be reintroduced: tones one bin
     apart and in phase overshoot by 8.5 bins, past any bound `d(T)` supports. The domain carries a
     frequency and a resolution, not a lower and an upper bound.
   - **Display granularity must be coarser than the bias, not merely coarser than the bin.** At a
     42.67 ms window the bias is 23–111 Hz, so a tenth of a kHz is the finest defensible step.

9. **The analysis window is fixed in time, not in samples.** Measured: under a 2048-point window at every
   rate, ten short bursts totalling 5 % of a file read 12.65 % of windows at 44.1 kHz and 6.73 % at
   192 kHz — the same temporal evidence classified significant at one rate and insignificant at another.
   Time-locked, the same content reads 11.6–11.8 % at all five rates. The window is therefore **≈ 42.67
   ms**, realised as the nearest length `vDSP_DFT_zrop` accepts (`f · 2^m`, f ∈ {1,3,5,15} — so 1920 at
   44.1 kHz and 3840 at 88.2 kHz, within 2.0 %, rather than the 8.8 % error powers of two would force),
   with **75 % overlap**. `fftSize` and `hop` are part of the method's identity, because the persistence
   criterion is defined on windows.

10. **A lossy transport moves the reading without destroying the fact, and that is measured.** A
    64 kbps MP3 reads its own low-pass at 16 790 Hz where its source reads 20 075 Hz; a 320 kbps MP3
    keeps the source's edge; AAC at 128 kbps moves it four bins. Every one of them survives a rewrap to
    PCM with the **identical bin**, because the band limit travels with the samples and not with the
    container. Codec artefacts above the low-pass stayed below the threshold, so neither constant had to
    be widened to accommodate a codec. **None of this licenses the inference the change forbids**: that
    two files measure the same extent says nothing about where either came from.

11. **Channels are measured apart, and the budget is not.** A downmix that sums channels cancels
    opposite-polarity content to a flat line, and a measurement of *where energy stops* must not be able
    to lose energy the file carries — so each channel is measured on its own and `overall` is the
    highest of those readings, a **summary of facts** rather than a claim about "the programme".
    `SignalLevelMetrics` and `TruePeakMeasurement` set that precedent; `LoudnessAccumulator` combines
    only because BS.1770 defines programme loudness that way, and nothing defines this. Channels are
    **indices, never labels**. The programme **budget** stays global, because the programme is the file:
    a channel 70 dB under the rest is below it and reports no value.

12. **The bounded structure costs one declared tolerance, and it rounds towards measuring more.** The
    budget compares each window against the file's peak, which is unknown until the last chunk, so
    per-bin counters are **stratified by the window's own peak** in 0.25 dB strata — constant in
    duration, 7.57 MB for stereo at 192 kHz whatever the file's length, where one bit per bin per window
    would be 499 MB for three hours. The stratum straddling `filePeak − 60 dB` cannot be split: it is
    resolved **inclusively**, because a passage at exactly −60.0 dB is eligible under the exact rule and
    excluding its stratum drops it. So the budget is *60 dB, resolved to whole 0.25 dB strata, admitting
    at most 0.25 dB below it* — stated, not hidden, and in the harmless direction.

13. **Absence is an absence.** No audio, shorter than one window, or nothing meeting the criterion yields
   no value. Zero is not a result and **Nyquist is not a result** — the same rule that made −70 LUFS a
   gate rather than a reading (ADR-0022 §6). "No audio" is the numeric condition of §5, not a level.

14. **The shared STFT stage is deferred and named.** `SpectrogramAccumulator` already computes 1025 bins
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
- **Reporting a lower and an upper bound instead of a frequency.** Derived, and then falsified by
  measurement: coherent content one bin apart overshoots by 8.5 bins, outside any bound the window's own
  leakage supports. A bound a legal signal violates is not a bound.
- **Reporting the bin's upper edge rather than its centre.** Rejected: it adds half a bin of
  overstatement to a figure that already overstates, and buys nothing.
- **An absolute silence floor in dBFS.** Rejected in favour of a numeric energy test: any chosen level
  discards real content that the method still measures correctly, and none is needed.
- **A window fixed in samples.** Rejected on measurement: it makes the persistence criterion
  rate-dependent, classifying identical temporal evidence differently at 44.1 and 192 kHz.
- **Spectral flatness as a way to tell a noise floor from content.** Rejected on measurement: broadband
  hiss and band-limited "air" at the same per-bin level both measure 0.564. It separates *tonal*
  artefacts from noise, which is a different question, possibly worth its own indicator later.
- **A dynamic-range budget derived from the file itself** (its own dynamic range, or its loudness
  range). Rejected on principle: identical content in two files would be measured against two different
  budgets, breaking the rule that one method identity implies one number (§4.2 of the change's tasks).
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
  computed and discarded. **Now measured rather than feared** — see *What the integration cost* below:
  the sixth consumer costs what it costs alone, 0.05–0.20 s per audio-minute in Release, and adds no
  overhead beyond itself.
- **`SourceInspectionOutcome` reached six payloads**, and its own note said a sixth "should not simply
  be appended". **Decided and landed first, as `InspectionAnalyses`** — see below.
- **No published reference exists** for this quantity, and that is now measured rather than assumed.
  FFmpeg's `aspectralstats` has a `rolloff`, and it is the energy percentile this record already
  rejects: it under-reads a 16 kHz limit as 15.2–15.4 kHz, and adding a dominant 100 Hz tone moves it to
  12.5–13.4 kHz while the extent does not change at all. It tracks spectral **balance**, not **extent**.
  FFmpeg stays a producer of fixtures no macOS encoder can make, never a source of a fact.
- **The most useful reading is the one hardest to defend.** A 96 kHz file limited near 22 kHz is
  precisely what a user wants explained, and precisely what this must not explain yet.
- **An impulse alone in digital silence reads as broadband**, because eligibility removes the windows
  carrying no energy and so raises the share of the few that remain: a click occupying four of four
  eligible windows is present all the time. Measured, a programme must occupy about a quarter of a file
  before an isolated impulse stops setting the answer. Inside any real programme the impulse control
  passes, and §2's argument is unaffected — but the degenerate case is a property of the method, pinned
  by a test rather than left to be discovered.

### What the integration cost, and what it proved

Recorded here because it is evidence, not narrative. None of it promotes this record: the two remaining
promotion conditions are untouched.

**One read, and the container that made a sixth payload readable.** `InspectionAnalyses` groups only what
an inspection derives from the file's samples. The report stays outside it — it exists before the first
chunk — and `InspectionPresentation` stays separate because it models states that move from `.loading`
rather than settled outcomes. The new field carries **no default**, and the six outcome types are all
distinct, so omitting a field is *missing argument for parameter* and swapping two is *cannot convert
value of type*. There is no positional debt left to write a test against. The read count is still one
decoder, one decode call, one sample read, with programme bandwidth `.available` rather than merely
present; giving it a read of its own takes that to two, which the gate reports.

**The bundle is one operation's, whole.** A late result from a superseded inspection is dropped as a
unit, and this is asserted with six deliberately distinguishable analyses per operation rather than
inferred from fields that stayed `.loading`. The case that matters is a late bundle whose report *equals*
the one on screen — the same file inspected twice — where the merge fills every field still loading and
keeps every field settled: without the operation guard, A's analyses land on exactly the fields B had not
reached, leaving B's waveform beside A's loudness. Routing either the new field or an existing sibling
around that guard fails the same test.

**Isolation is bilateral**, and neither direction is an assumption: its absence leaves the other five
identical to a control run and does not shorten the read, and a sibling's real failure leaves its own
reading exactly what the accumulator produces from the same chunks. A producer failure partway — and,
the case that matters, *after the final chunk*, when a complete answer already exists — leaves all six
failed with nothing partial.

**Absence by configuration is unreachable, and that is a property rather than a gap.** Over every rate
from 10⁻³⁰⁰ to `greatestFiniteMagnitude` and channel counts from 1 to 1 024, 126 of 126 valid
`PCMStreamDescription`s were accepted and none declined: the domain type already guarantees a finite
positive rate and at least one channel, and no supported window length is one `vDSP` refuses. The real
absences come from the audio not matching its description, or from a file carrying no usable window.

**The numeric extremes are three cases, not two, and each has its own protection.** The magnitudes are
computed by two routes — the interior bins squared, DC and Nyquist taken linearly — and that asymmetry
decides which extreme an input can reach. A quiet *sine* collapses to no positive peak and returns
before the budget is computed; a quiet *Nyquist alternation* carries a denormal all the way through, and
`x · 0.001` underflows to exactly zero at and below 6.99 × 10⁻⁴³, which is why the budget is subtracted
in decibels. Samples at `greatestFiniteMagnitude` make the magnitudes `NaN`, which the eligibility rule
turns into an absence. Amplitudes above about 3 × 10¹⁶ keep the components finite while their squares
overflow, so the magnitude is `+∞`, which *is* greater than zero, passes eligibility, and reaches the
stratum conversion — that is what the finiteness clamp exists for, and nothing else exercises it.

**What it cost.** Release, ten minutes of stereo, one machine and one session, the minimum of three
repetitions per cell:

| rate | shared 5 | shared 6 | delta | accumulator alone | delta / alone |
| --- | --- | --- | --- | --- | --- |
| 44.1 kHz | 5.271 s | 5.788 s | 0.517 s | 0.512 s | 1.01 |
| 48 kHz | 5.702 s | 6.373 s | 0.671 s | 0.491 s | 1.37 |
| 96 kHz | 11.671 s | 12.586 s | 0.915 s | 0.956 s | 0.96 |
| 192 kHz | 23.156 s | 24.956 s | 1.800 s | 1.968 s | 0.91 |

Three of four ratios are at or below 1.01; the 48 kHz outlier is noise, and at 192 kHz — most expensive
and best resolved — the delta is 9 % *below* the isolated cost. There is no overhead beyond the work
itself, so nothing was optimised. These measure the consumers; decode is identical on both sides, and
the read-count gate is what proves it did not change.

**Memory, measured at the allocator rather than at RSS**, which could not resolve it. The sixth consumer
adds 2.4 MB at 48 kHz and 8.7 MB at 192 kHz — the stratified counters plus a bounded overlap tail and
preallocated scratch — and is **constant in duration**: quadrupling the audio moves it by half a
percent. It is therefore neither a copy of the PCM nor a retained spectrogram, both of which would be
about 184 MB for the same material. Retaining every window's magnitudes takes it to 233 MB at four
audio-minutes and makes it scale with duration, which is how the measurement was shown to discriminate.

### Neutral
- No port changes, no export version change, no new dependency, and no second read.
