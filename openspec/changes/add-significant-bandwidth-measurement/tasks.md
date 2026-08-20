# Tasks — significant bandwidth

**Nothing below is implemented.** Group 1 is blocking by design: no accumulator exists until the
methodology is measured. This is the order `add-loudness-measurement` used — constants settled and
sourced before an accumulator existed — and the reason its numbers survived review.

**Group 1 status.** 1.1-1.5 are settled from measurement in
`docs/spikes/2026-08-19-significant-bandwidth-methodology.md`: the threshold is **-50 dB relative to the
loudest bin in the same analysis window**, the persistence criterion is **>= 10 % of eligible windows**,
the analysis window is **time-locked at ~42.67 ms with 75 % overlap**, and the reported value is a **bin
centre plus its resolution**, never an interval.

**Groups 1, 2 and 3 are complete, and the domain model came with 3.** The methodology was decided by
measurement and survived two rounds of refutation; group 2 took it onto real files; group 3 turned it
into `SignificantBandwidthAccumulator`, which reproduces every one of group 2's targets **without a
single expected value changed or a tolerance widened**. Bounded memory is constant in duration —
7.57 MB stereo at 192 kHz for a file of any length — and channels are measured apart because a downmix
would cancel opposite-polarity content. Group 4 was brought forward only as far as `finish()` required.
Nothing is wired: no shared PCM consumer, no UI, no export, no comparison. ADR-0023 stays `Proposed`;
its remaining promotion conditions are the impulse control against production code, which group 6 owns,
and human validation of a surface that does not exist yet.

## 1. Methodology — decide it before writing an accumulator

- [x] 1.1 Build **graded fixtures**: a roll-off rather than a cliff, at several slopes. The spike's
      threshold sweep moved only 328 Hz across 80 dB because its fixture had an infinitely sharp edge,
      so it could not discriminate between thresholds and neither can any test built on it.
      **Done.** Roll-offs at 6/12/24/48/96/192/480 dB per octave above an 8 kHz and a 16 kHz knee, plus
      graded *level* and graded *persistence* series. Every roll-off reading matches the analytic
      prediction `knee · 2^(−T/S)`. They discriminate: the same sweep now moves the answer from 8 508 to
      23 543 Hz. Spike §2, §8.
- [x] 1.2 Decide the **threshold**, from measurement, and record what it is relative to: each window's
      own peak, the file's overall peak, or its gated loudness. State why the rejected two are worse.
      **Decided: −50 dB relative to each window's own spectral peak.** Admissible region [−65, −45],
      bracketed by fixtures; −50 is its midpoint with 20 dB of margin either way. All four rejected
      references were measured, not argued: the **file's overall peak** loses a real persistent band to a
      2 % transient (R4 → 16 008 Hz where the answer is 20 000); **global spectral RMS** and a **robust
      p95** are statistics over the bin population, not levels, and drift 6.0 dB and 41.8 dB across FFT
      sizes for identical content; **gated loudness** passes every constraint but its offset from a
      per-bin magnitude spreads 32.6 dB across fixtures, so one constant is not one sensitivity. Spike §3,
      §4.
- [x] 1.3 Decide the **persistence criterion** — a fraction of windows, and which percentile — against
      **non-stationary** material. p50 and p95 agreed on every fixture the spike tried because all of
      them were stationary; that agreement is not evidence.
      **Decided: present in ≥ 10 % of eligible windows**, measured against clicks, bursts and graded
      duty cycles. It is the smallest value that rejects full-band bursts totalling 1 % (4.3 % of windows)
      and 5 % (8.0 %) with real margin while keeping a band present in 10 % (10.8 %). Percentile
      restatement, exact: the k-th largest of the bin's per-window levels with `k = ceil(0.10 · N)` — a
      nearest-rank-from-the-top p90, **not** an interpolated p90 and **not** p95. A burst shorter than the
      window marks `fftSize / hop` windows, so duty cycle and window presence are different numbers and
      the criterion is defined on the second. Spike §2.1, §5, §5.1.
- [x] 1.4 Decide what a **quiet but persistent** band must do, and fix the level at which it must still
      be reported. This is the criterion that separates a measurement from a loudness gate.
      **Decided.** A persistent band at **−45 dB or above** relative to the loudest bin in the same window
      is reported in full; at −50 dB it is at the transition and reported partially; at −55 dB or below it
      is not reported. The threshold is a **sensitivity, not a discriminator** — a weak band and a low
      noise floor at the same relative level are the same thing spectrally and no threshold separates
      them. Two consequences are recorded rather than tuned away: continuous noise above the cut-off at
      −40/−50 dB *is* reported, and a file with a full-scale low end throughout under-reports a real high
      band 59.5 dB below its window peak. Spike §4, §10.
- [x] 1.5 Fix the **resolution claim**: bin width per rate, and how a Hann window's spread widens the
      real uncertainty beyond one bin. Decide whether the reported value is a bin centre, a bin edge, or
      a range.
      **Decided.** The Hann transform is `|W(d)| = |sin(pi d)|/(pi |d| |d^2-1|)`, verified against the
      true DTFT to 0.000 dB, and its skirt falls as `1/d^3`. A relative threshold T therefore reaches
      `d(T) = (1/(pi*10^(T/20)))^(1/3)` bins — **4.72 bins at -50 dB**. That is what the earlier "~4
      bins" was: not the bin width, not the 4-bin main lobe, not bin quantisation, but the threshold
      cutting the leakage skirt, and it is the only one of the four that moves with the threshold.
      **Contract: bin centre plus the resolution it was measured at.** An interval contract was derived
      and then **falsified** — coherent tones one bin apart overshoot by 8.5 bins — so lower/upper bounds
      are rejected rather than deferred. The reported value is an upper bound on where content ends,
      overstating by 1 bin (edge on a bin) to d(T) bins (edge between bins), one-sided upward; display
      granularity must be coarser than that bias, which is 23-111 Hz at a 42.67 ms window. Spike
      §12.1-12.4.

- [x] 1.6 Record every constant with its source in a spike document, as
      `docs/spikes/2026-08-18-loudness-measurement-validation.md` Part A does.
      **Done**, at `docs/spikes/2026-08-19-significant-bandwidth-methodology.md` §11, §12.13 and §13c.
      Six constants and one deletion: the reference (per-window spectral peak), the threshold (-50 dB),
      the persistence fraction (>= 10 %), the window (~42.67 ms time-locked, hop = fftSize/4, periodic
      Hann), the dynamic-range budget (60 dB, a declared product parameter with its cost tabulated), and
      the reporting contract (bin centre plus resolution). Deleted rather than sourced: the -120 dBFS
      floor and the file-level energy test that briefly replaced it -- both were artefacts of a
      magnitude clamp. One methodological requirement follows: **the transform must not clamp its
      magnitudes**, or silence stops being decidable.

- [x] 1.7 **Decide the window-eligibility rule.** Opened by refutation, closed by declaration.

      **Attempt 1 -- a level gate presented as a discovery.** Rejected: the two failure tables ("reject a
      noise-floor-only passage", "keep a real quiet passage") are exact mirror images, because to such a
      rule they are the same measurement.

      **Attempt 2 -- no gate at all.** Numerically exact and right on seven of eight collector files,
      but a broadband floor alone in more than 10 % of a file sets the answer at any level, down to
      200 dB below the programme. Spectral flatness cannot separate the two (0.564 for both tape hiss
      and musical "air"), nor can a persistence curve. Spike §13b.

      **Decided.** Two rules, one of which needs no constant:
      1. **eligibility** -- a window is an observation if it carries energy. An unclamped transform makes
         a zero window's magnitude exactly zero, so silence, partial silence and absence all fall out
         with nothing added. Measured: digital silence reads absent even with every other rule disabled.
      2. **budget** -- a window contributes only if it sits within **60 dB** of the file's loudest
         spectral moment. This is a declared product parameter, not a discovery, and it is load-bearing
         on exactly one case: a broadband noise floor alone in the file. Its cost is tabulated in spike
         §13c.3 and stated in one sentence whose two halves are the same rule -- *content more than
         60 dB below the loudest moment is not measured, and a noise floor further down does not count
         as content.*

      The metric is named **programme bandwidth**, in full *"programme bandwidth, within 60 dB of
      programme peak"*, so the budget travels with the figure instead of hiding inside it. Spike §13c.

## 1b. The analysis window — settled here, listed separately because it was not a numbered task

- [x] 1b.1 **Time-locked, not sample-locked**, on measurement: under a fixed 2048-point window, ten
      bursts totalling 5 % of a file read 12.65 % of windows at 44.1 kHz and 6.73 % at 192 kHz — the same
      temporal evidence classified significant at one rate and not at another. Time-locked it reads
      11.6-11.8 % at all five rates. Spike §12.5.
- [x] 1b.2 **Window ~42.67 ms, hop = fftSize/4 (75 % overlap).** `vDSP_DFT_zrop` accepts `f * 2^m` for
      f in {1,3,5,15}, so 1920 at 44.1 kHz and 3840 at 88.2 kHz hold the duration to within 2.0 %, where
      powers of two alone would force 8.8 %. 25 % overlap disagrees with the rest on the critical event
      duration; 50, 75 and 87.5 % agree, and more overlap rejects transients better. Spike §12.5, §12.7.
- [x] 1b.3 **`fftSize` and `hop` are part of the method identity**, because the persistence criterion is
      defined on windows. A transient marks **one** window, not `fftSize/hop` of them — the Hann taper
      attenuates it near a window's edge — which corrects part A. Spike §12.7.

## 2. Fixtures and the oracle

**Group 2 passes.** The fact survives the transport: real containers, five sample rates, real chunk
boundaries and both lossy codecs. Evidence is `ProgrammeBandwidthEvidenceTests`,
`ProgrammeBandwidthLossyEvidenceTests` and `ProgrammeBandwidthNegativeControlTests`, measuring with
`ProgrammeBandwidthReference` — the method in test code, because **no production accumulator exists and
nothing here asserts against one**. Spike §13d.

- [x] 2.1 Reuse `AudioFixtureSignal.bandLimitedTones` and the existing format matrix rather than adding
      a generator. Extend it **only** where a graded roll-off or a noise floor cannot be expressed.
      **Two cases added, and only two**: `sum` and `enveloped(rampFrames:)`, which is what a programme
      plus a second band at its own level needs. Roll-offs are a `sum` of sines and needed no case.
      `enveloped` carries a raised-cosine ramp because a hard amplitude step is a **broadband** event
      that measured as Nyquist in a fixture whose eligible-window count was small. Spike §13d.1.
- [x] 2.2 Cases: pure tone; tones to a known edge; two neighbouring edges; white noise; silence; a lone
      impulse; high content present ~1 % of the time; the same persistent; a high band at −20, −40 and
      −60 dB.
      **Covered**, and extended where group 1's decisions demanded it: edges at 8/12/16/20 kHz, bands at
      −30/−40/−60/−70 dB, presence at 5/25/50/100 %, budget passages at −40…−80 dB, graded roll-offs,
      silence, no-audio, sub-window files, a prime frame count, and an impulse both alone and inside a
      programme.
- [x] 2.3 The same described signal at 44.1 / 48 / 88.2 / 96 / 192 kHz, written as real files.
      **Done**, and it produced the resolution contract: the error is one-sided upward and at most
      **4.55 resolutions** against the analytic reach of 4.72, so the assertion is
      `0 ≤ error ≤ 5 × resolution`. The raw hertz are **not** comparable across rates — each quantises
      the edge onto its own grid — and the rates agree to within one resolution. Spike §13d.2.
- [x] 2.4 WAV / FLAC / ALAC / AIFF equivalence, and AAC separately, on the container matrix's own
      precedent that a lossy codec is a different question.
      **Lossless containers read the identical bin**, asserted exactly rather than within a tolerance.
      AAC moves the reading four bins and does not reach Nyquist. MP3 at 64 kbps reads its own low-pass
      (16 790 Hz against a 20 075 Hz source) and at 320 kbps keeps the source's edge; **all three
      bitrates survive a rewrap to PCM with the identical bin**. The MP3 rows are local evidence only —
      FFmpeg is not on CI, and a skipped run is not coverage. Spike §13d.5.
- [x] 2.5 Qualify FFmpeg as a **corroborating oracle only** where it can measure something comparable.
      It is not a normative source here and there is no published target for this quantity — which makes
      the analytic fixtures the primary evidence, not the tool.
      **Measured, and the answer is that it cannot.** `aspectralstats`'s `rolloff` is the energy
      percentile ADR-0023 already rejected: it under-reads a 16 kHz limit as 15.2–15.4 kHz, and adding a
      dominant 100 Hz tone moves it to 12.5–13.4 kHz while the extent does not change. It tracks
      spectral **balance**, not **extent**. FFmpeg stays a producer of fixtures no macOS encoder can
      make. Spike §13d.6.

## 3. The accumulator

**Group 3 passes.** `SignificantBandwidthAccumulator` in `AudioInspectorAnalysis`, reproducing group 2's
targets without a single expected value being changed or a tolerance widened. Spike §13e.

- [x] 3.1 `SignificantBandwidthAccumulator` in `AudioInspectorAnalysis`, taking `PCMChunk` like its five
      siblings, with its own STFT at full bin resolution.
      **Done.** `init?(sampleRate:channelCount:)` → `mutating accumulate(_:)` → `finish() -> SignificantBandwidth?`,
      the shape its five siblings use. Time-locked window derived per rate, periodic Hann built in place,
      75 % overlap, `vDSP.DiscreteFourierTransform` on `SpectrogramAccumulator`'s own precedent, DC and
      Nyquist unpacked into their own bins, and **no clamp anywhere in the path**.
- [x] 3.2 **Chunk independence**, demonstrated by a test that fails when it is broken, at the same chunk
      sizes loudness uses.
      **Exact equality** — not a tolerance — at 1, 3, 127, 512, 4 096, 65 536 and whole-file chunks, over
      48 and 192 kHz, on a hard edge, a weak persistent band, a file sitting on the budget boundary and
      silence. The test that fails when it is broken is verified: resetting the overlap state on every
      chunk breaks it (spike §13e.5).
- [x] 3.3 Bounded memory: per-bin persistence counters, never a retained spectrogram.
      **Done, and the alternatives were costed rather than assumed.** One bit per bin per window is exact
      but 499 MB for three hours at 192 kHz, and is a retained spectrogram whatever its resolution.
      Counters stratified by the window's own peak in **0.25 dB** strata are **constant in duration**:
      measured 1.78 / 1.89 / 3.78 / **7.57 MB** stereo at 44.1 / 48 / 96 / 192 kHz, for a file of any
      length. The declared tolerance the structure costs is written down: the stratum straddling
      `filePeak − 60 dB` cannot be split, and is resolved **inclusively**, because a fixture at exactly
      −60.0 dB proved the exclusive reading loses a passage the exact rule keeps. Spike §13e.1, §13e.2.
- [x] 3.4 Decide mono/stereo handling — per channel, or combined — and state why. Whatever is chosen
      must not assert a channel layout the pipeline does not read.
      **Per channel, with `overall` the highest of those readings.** Decided by the `oppositePolarity`
      fixture: any downmix that sums channels cancels it to a flat line, and a measurement of *where
      energy stops* must not be able to lose energy the file carries. Precedent chosen semantically —
      `SignalLevelMetrics` and `TruePeakMeasurement` are per channel plus overall; `LoudnessAccumulator`
      combines only because BS.1770 defines programme loudness that way, and nothing defines this.
      Channels are **indices, never labels**: four channels are four readings and no layout is named.
      The **budget stays global**, because the programme is the file: a channel 70 dB under the rest
      reports `nil`. Spike §13e.3.

## 4. The domain model

**Brought forward deliberately, and only as far as group 3 required.** `finish()` has to return
something, and inventing a provisional DTO that would later die is worse than building the value type
the change already specified. 4.1–4.4 are done; nothing about export, presentation or comparison is.

- [x] 4.1 `SignificantBandwidth` — `Sendable`, `Equatable`, failable, **not** `Codable`, carrying the
      frequency, the resolution it was measured at, and its method identity.
      **Done**, with a per-channel `Channel` carrying frequency and resolution, `channels: [Channel?]`,
      `overall`, and `SignificantBandwidthMethod`.
- [x] 4.2 The method carries **identities, not editable configuration**, on `LoudnessMethod`'s own
      precedent: the same identifier must imply the same number.
      **Done**: `programme-bandwidth-60db-v1`, carrying window frames, hop and rate — the parameters
      without which the identifier would not imply one number, because the persistence criterion is
      defined on windows.
- [x] 4.3 **No verdict field of any kind**: no `isBandLimited`, no `suspectedUpsample`, no confidence,
      no comparison against the declared rate.
      **Done**, and the type's documentation states what it is not: not a cut-off, not a claim about the
      whole file, not evidence of provenance.
- [x] 4.4 Absence is an optional the producer returns, never a floor. Nyquist is not a result.
      **And nor is zero, but the measurement can produce it**: a constant signal is DC, so DC is
      legitimately its highest qualifying bin and the reading is 0 Hz. Decide what the model does with
      that. Spike §13b.2.
      **Decided: report it.** Neither end is used as a floor or a sentinel — absence is `nil` throughout —
      so a *measured* 0 Hz or Nyquist is a reading and not a stand-in for "nothing found". Suppressing
      either would be inventing the verdict 4.3 forbids. The type says so, and a surface must not render
      them as absence.

## 5. The sixth consumer

**Done.** All four are demonstrated. 5.2's negative controls now discriminate, and 5.4 was measured in
Release in one session.

- [x] 5.1 One field on `SharedPCMAnalysisOutcome`, one accumulator in the composition. **The read count
      stays one**, at the gate that already asserts it.
      **Done.** The accumulator is built in `prepare(for:)` from the same `PCMStreamDescription` as its
      five siblings, fed in `accumulate(_:)`, ended in `failAll`, and finished in `finish(stream:)` —
      no protocol, no generic machinery, no second decoder. It follows **loudness's** shape rather than
      the others': its `init?` declines a stream it does not claim, which is an absence and not a fault,
      so it has an `absent` flag and no fault of its own. `SharedPCMDecodeCountTests` now asserts the
      read count with programme bandwidth **`.available`** rather than merely present, and pins the
      update order with the sixth last and the five before it unchanged.
- [x] 5.2 Isolation: its failure or absence changes nothing about the other five, with negative controls.
      **Done.** `SharedProgrammeBandwidthIsolationTests` pins nine properties: absence leaves the five
      identical to a control and does not shorten the read; a sibling's real failure (true peak
      overflowing on enormous finite samples) leaves programme bandwidth exactly what the accumulator
      produces from the same chunks; a producer failure partway, **and after the final chunk**, leaves
      all six failed with nothing partial; cancellation before the first chunk and mid-read cancels all
      six, on a handshake; shared equals direct at four rates; chunk independence through the
      composition at six chunk sizes.

      **The bundle is atomic, and that is a stronger property than "bandwidth of A does not appear".**
      `InspectionAnalysesStaleAtomicityTests` gives both operations six deliberately distinguishable
      analyses, so "the presentation is entirely B" is observed rather than inferred from fields that
      merely stayed `.loading`. The case that matters is a late bundle whose **report equals the one on
      screen** — the same file inspected twice: there the merge fills every field still `.loading` and
      keeps every field settled, so without the operation guard A's analyses land on exactly the fields
      B had not reached, leaving B's waveform beside A's loudness. Three controls, each applied and
      reverted: routing `.significantBandwidth` around the update guard fails it, routing `.loudness`
      around it fails the same test, and removing the outcome guard fails both and reports precisely
      that mixture. **The test protects the bundle, not the field added last.**

      **The four controls that did not bite were diagnosed rather than repeated, and three are now
      closed.** The suite that did not pin its own fix does now: the magnitudes are computed by two
      routes, and only the linear DC/Nyquist path carries a denormal amplitude to a positive spectral
      peak, so a quiet *sine* returns before the budget is computed while a quiet *Nyquist alternation*
      reaches it. `x · 0.001` underflows to exactly zero at and below **6.99 × 10⁻⁴³**, found by
      bisection; an amplitude of 5 × 10⁻⁴³ lands inside that region and traps under the old
      multiplication. The same investigation separated two overflows that had been treated as one — NaN
      magnitudes, stopped by the eligibility rule, and `+∞` magnitudes above about 3 × 10¹⁶, which pass
      eligibility and are what the finiteness clamp exists for. Three controls, each trapping exactly
      one test and leaving the others passing.

      **One prediction in this task was wrong and is corrected here.** It called bandwidth's `init?`
      declining a valid stream "an unreachable branch", which was right, but treated that as a gap to
      be worked around. It is a **property**: over every rate from 10⁻³⁰⁰ to `greatestFiniteMagnitude`
      and channel counts from 1 to 1 024, 126 of 126 valid `PCMStreamDescription`s were accepted and
      none declined. `.unavailable` **by configuration is unreachable**, because the domain type already
      guarantees a finite positive rate and at least one channel, and `windowFrames(for:)` cannot return
      a length `vDSP` refuses. The failable initialiser is defensive against inputs the domain forbids.
      Programme bandwidth's real absences come from elsewhere and are not fabricated here: `failAll`
      when the audio does not match its description, and `finish()` returning nothing for a file with no
      usable window — silence, shorter than one window, or a transform that cannot be represented.

      **The container's own controls need no test, because the compiler is stricter.** Omitting a field
      from `InspectionAnalyses(…)` is *missing argument for parameter*, and the six outcome types are
      all distinct, so swapping any two is *cannot convert value of type*. There is no positional debt
      left to test for. The one place a field **can** be silently dropped is
      `InspectionPresentation`, whose initialiser does carry `.loading` defaults — and letting the
      settled state fall back to one fails three suites, including this task's own.

- [x] 5.3 **The container refactor is due.** `SourceInspectionOutcome.inspected` already carries five
      labelled payloads and its own note says a sixth "should not simply be appended". Decide here
      whether this change introduces the container or records why it does not — do not append silently.
      **Done, and done first.** `InspectionAnalyses` groups only what an inspection derives from the
      file's samples; the report stays outside it because it exists before the first chunk, and
      `InspectionPresentation` stays separate because it models states that move from `.loading` rather
      than settled outcomes. The migration was landed as its own commit and is **observably neutral**:
      the same 1309 tests in 140 suites passed before and after, with the sixth analysis added only
      afterwards. The new field carries **no default**, so omitting it is a compile error.
- [x] 5.4 Measure the real cost 5-against-6, as group 7 of `add-loudness-measurement` did. Baseline for
      reference: the five-consumer pass takes 1.02 s for 60 s of stereo at 48 kHz and 3.54 s at 192 kHz
      in Debug.
      **Measured.** Release, ten minutes of stereo, one machine and one session, the minimum of three
      repetitions per cell because the delta is a ~10 % difference between two numbers each carrying
      ~5 % run-to-run noise — a single sample cannot resolve it, and the first two single-sample runs
      disagreed by a factor of two.

      | rate | shared 5 | shared 6 | delta | accumulator alone | delta / alone |
      | --- | --- | --- | --- | --- | --- |
      | 44.1 kHz | 5.271 s | 5.788 s | 0.517 s | 0.512 s | 1.01 |
      | 48 kHz | 5.702 s | 6.373 s | 0.671 s | 0.491 s | 1.37 |
      | 96 kHz | 11.671 s | 12.586 s | 0.915 s | 0.956 s | 0.96 |
      | 192 kHz | 23.156 s | 24.956 s | 1.800 s | 1.968 s | 0.91 |

      **The sixth consumer costs what it costs alone, and nothing extra.** Three of the four ratios are
      at or below 1.01, and the one outlier at 48 kHz is noise: repeated single runs at that rate gave
      1.10, 1.06 and 0.87. At 192 kHz — where the accumulator is most expensive and the measurement best
      resolved — the delta is 9 % *below* the isolated cost. There is no systematic overhead to
      diagnose, so nothing was optimised.

      **This measures the consumers, not the whole pass**, and that is deliberate: decode is identical
      on both sides, and including it would bury a 0.5 s delta under a much larger constant. The figure
      quoted above as a reference is Debug and includes decode, so it is not comparable with these; what
      proves decode did not change is the read-count gate, which still reports one decoder, one decode
      call, one sample read, with programme bandwidth `.available`.

      **Memory, at the allocator rather than at RSS.** RSS could not resolve this at all — the pages
      were already in the high-water mark — so live allocated bytes were measured instead. The sixth
      consumer adds **2.4 MB at 48 kHz and 8.7 MB at 192 kHz**, against a theoretical counter array of
      1.98 and 7.93 MB plus the bounded overlap tail and the preallocated scratch buffers. It is
      **constant in duration**: quadrupling the audio moves it by 0.4 % and 0.5 %. It is therefore
      neither a copy of the PCM (184 MB for that material) nor a retained spectrogram (also ~184 MB).
      At construction the figure is about half, because `counters` is an array of arrays and the second
      channel's buffer is shared until first written — the copy happens once, not per chunk.

      **The harness was shown to discriminate**, with one regression applied and reverted: retaining
      every window's magnitudes takes the footprint from 2.4 MB to 60 MB at one audio-minute and 233 MB
      at four — detected both by size and, more tellingly, by starting to **scale with duration**, which
      is the signature the bounded design forbids. Its resolution was also established honestly: a
      genuine per-chunk copy of the channel arrays is *not* detectable, because at 32 KB per chunk it is
      about 4 % of the accumulator and below the noise. Rebuilding the Hann window per transform is
      detectable at once — 0.49 s to 1.55 s, a 3.2× regression.

## 6. Correctness against the fixtures

**Done, against production.** The subject of every task below is the path a user's file actually
takes — a written file, the real `AVFoundationAudioDecoder`, the shared read, and the
`SignificantBandwidthOutcome` the composition publishes. Group 2's suites measure the same fixtures
with `ProgrammeBandwidthReference`, and group 3's feed the accumulator chunks directly; neither is
production, and nothing here constructs a `SignificantBandwidth` by hand. No expected value is taken
from a previous run, and every tolerance is stated in **resolutions** rather than hertz, so it means
the same thing at all five rates.

- [x] 6.1 A known edge is reported within the stated resolution, at every supported rate.
      **Done.** Four edges — 8, 12, 16 and 20 kHz — at 44.1, 48, 88.2, 96 and 192 kHz: twenty cases,
      each within the 5 resolutions the Hann skirt explains at −50 dB. **The one-sidedness is asserted
      across the whole matrix in one place**, because a per-case bound of `>= −1 resolution` would let a
      systematic downward bias hide inside it: no reading falls below its edge at any rate.
- [x] 6.2 **The impulse control**: a file silent but for one click reports no wider a band than silence
      does. This is the property the whole design exists for.
      **Done — and this task's own prediction was false, so it is corrected here rather than worked
      around.** A file silent but for one click does **not** report what silence reports. Measured
      through production it reads above 20 kHz, exactly as `ProgrammeBandwidthEvidenceTests` and
      ADR-0023's declared limitation already said it would. The eligibility rule is why: a window with
      no energy is filed nowhere, so the only eligible windows are the four the click touches, and the
      click is present in all four. It is not a transient *within* a programme — it **is** the
      programme, and a click is broadband. Silence and silence-plus-a-click are therefore kept as two
      tests, because they are two answers by two mechanisms and one predicate over both would hide that
      only one of them is an absence.

      **The property the design exists for is the other one, and it holds.** An isolated full-scale
      click inside a 16 kHz programme leaves the published reading **identical** — equality, not a
      tolerance, because a control that let the reading drift would pass while the transient was moving
      it. The turnover is asserted on both sides: `ceil(0.10 × 278) = 28` windows are needed, and
      measured it takes **eight** impulses rather than the seven four-windows-each would predict. The
      extra one is the Hann taper — the outermost of the four windows carries the click near an edge
      where the coefficient is near zero, so it never clears significance and an impulse is worth about
      three and a half windows. Clustering the clicks changes nothing, because the criterion counts
      windows and not spacing.
- [x] 6.3 A quiet-but-persistent band is reported; a loud-but-isolated one is not.
      **Done, on all three layers, through production.** **Persistence**: a band present 5 % of the file
      leaves the reading at the programme's own edge, and 10, 25 and 100 % are reported. **Budget**: a
      passage 50 and 60 dB below the programme takes part and one 70 dB below does not — the three
      anchors the specification uses, which confirms the conservative 0.25 dB stratification does not
      disturb them. **Prominence**: a high band 40 and 50 dB below its window's peak is reported, 60 and
      70 dB below is not. A band sitting exactly on the −50 dB threshold is reported but **not to its
      full extent**, because its topmost components are the ones closest to the threshold; that partial
      reading is asserted as what it is rather than rounded to either neighbour.
- [x] 6.4 Rate invariance: the same described signal agrees within resolution across the five rates.
      **Done.** The overshoot on a 16 kHz edge varies by no more than one resolution across the five
      rates. **The method identity is pinned per rate as well**, which is what makes "time-locked"
      testable rather than asserted: 1920 frames at 44.1 kHz, 2048 at 48, 3840 at 88.2, 4096 at 96 and
      8192 at 192 — the non-powers of two being what hold the window within 2 % of the 42.67 ms target.
      A sample-locked implementation reports 2048 everywhere and fails this.
- [x] 6.5 Undefined cases yield absences: no audio, shorter than one window, silence.
      **Done.** Zero frames, one frame, 1 000 and 2 047 all publish `.unavailable`, as does five seconds
      of digital silence — an absence caused by the file, never a floor, a zero or a substituted
      Nyquist. **Exactly one window measures**, and a partial tail after it changes nothing: asserted as
      equality between the two files, so a tail that leaked in would have to move the reading to pass.
- [x] 6.6 A lossy encoder's band limit survives being rewrapped as WAV, on
      `MP3SpectrogramEvidenceTests`' own precedent — reported as a frequency, with no codec named.
      **Done.** Through production, all three bitrates publish the **identical** measurement before and
      after a rewrap to PCM: the same samples, and the measurement is a pure function of them. A 64 kbps
      MP3 publishes its own low-pass, clearly below the source and clearly not a Nyquist artefact; at
      320 kbps it keeps the source's edge, so the measurement is not simply reporting "lossy". AAC is
      encoded by macOS and is CI coverage; **the MP3 rows are local evidence only** — FFmpeg is not on
      CI, and a skipped run is not coverage. Nothing reads a header or names a codec: the assertions are
      only that two files measure the same, or that one measures lower than another.
- [x] 6.7 Negative controls against production, each applied and reverted: persistence disabled;
      threshold made absolute; the reduction changed to a maximum over time; resolution reported finer
      than a bin; Nyquist substituted for an absence.
      **Done — nine controls, eight of which bite, and the ninth diagnosed rather than repeated.**
      Persistence disabled fails the impulse control itself, which is the one that matters: the isolated
      click then does produce a bandwidth. A maximum over time is the same mutation and the same
      failure. The threshold made absolute fails 35 assertions across prominence, persistence, channels
      and AAC; tightening it to −30 dB fails 15. A resolution finer than a bin fails 81. Nyquist
      substituted for an absence fails every undefined case. A sample-locked window fails the rate
      matrix and the identity. Channels mixed before the transform fails opposite polarity and both
      per-channel tests. Accepting the partial final window **traps**, which is the correct failure for
      a bounds violation.

      **The ninth is a documented redundancy, not a gap.** Removing the budget's check at the end alone
      changes nothing, because the budget is enforced **twice** — the ring's capacity is 60 dB of strata
      by construction, so a window below the budget was already dropped before the check could see it.
      Removing the check *and* enlarging the ring admits the −70 dB passage and fails exactly the budget
      test. This was recorded when the accumulator was built and is confirmed here at the production
      level.

      **One end-to-end case is not reachable, and is recorded rather than faked.** The denormal
      amplitudes the underflow arithmetic needs do not survive the write-and-decode round trip. That is
      evidenced rather than claimed: the signal level metrics from the same shared read report a peak of
      **zero**, so the file the decoder hands over is silence and the absence is the correct answer to
      it. The evidence for that arithmetic stays at the PCM level, where it can be exercised. The
      overflow extreme **is** reachable through a real file and publishes a finite in-range answer.

## 7. Presentation

**Done.** One section, on `LoudnessSection`'s precedent, placed after the level sections and before the
spectrogram: it is the first measurement in the report about *frequency* rather than level, and it
precedes the spectrogram because it is a settled number and that is a picture. It is deliberately **not**
a caption on the spectrogram — that is a different transform at a different resolution, and pairing them
would suggest one can be checked against the other by eye.

**The visible name is "Programme bandwidth", never the domain's own.** The type keeps
`SignificantBandwidth` for symmetry with its state and its outcome; the surface uses the product's name,
and a test sweeps every string it can produce to keep the two apart. None of the names that would
overclaim is used: not "effective sample rate", not "real"/"true" bandwidth, not "audio resolution", not
"cut-off frequency". The name describes a measurement, not a property of the world.

**Note on ADR-0023.** Closing this group does **not** satisfy the record's third promotion condition. That
asks for a person looking at the surface, and no such pass has run — the runbook and the pre-computed
expected values are in `docs/manual-validation-mvp.md`, marked PREPARED, not executed.

- [x] 7.1 One row, its own section or beside the spectrogram, stating what was measured and at what
      resolution. No precision beyond the resolution.
      **Done, as two rows and a method line.** The value, the resolution as a quantity of its own, and
      one sentence saying what was measured. `HumanFormat.programmeBandwidth(_:resolution:)` rounds to
      the smallest power of ten that is **at least** the resolution, so the last digit shown is always
      worth more than one bin: `16 101.5625 Hz` reads `16.1 kHz`, and `20 015.625 Hz` reads `20 kHz`
      rather than `20.02 kHz`, which would imply a 10 Hz distinction the bins cannot make.

      **The rule is identical at all five rates, and that is a consequence rather than a coincidence.**
      Because the window is fixed in *time*, the resolution is 22.97–23.44 Hz whether the file is 44.1
      or 192 kHz, so the display step is 100 Hz and the form is one decimal in kilohertz everywhere. A
      sample-locked window would make the displayed precision depend on the file's rate, and the
      per-rate test would catch it. Beyond the reference points the rule is **swept** — every frequency
      from 1 to 96 kHz on six different grids — because it is a one-sided guarantee and one
      counter-example would break it.

      **The resolution is never an uncertainty.** It is the width of an analysis bin, and ADR-0023
      refuses to publish a false bound of uncertainty, so it is a second row with its own name and never
      `16.1 ± 0.02 kHz`. That form claims the true value lies in an interval, which this measurement does
      not claim — and the reading is already biased one way, upward by the window's leakage, so a
      symmetric interval would be wrong twice. The sweep rejects `±`, `+/-`, and any string describing
      the resolution as error, tolerance, margin, accuracy or confidence.
- [x] 7.2 **No verdict and no comparison against the declared sample rate.** The forbidden vocabulary
      sweep that loudness uses, extended with: upsample, transcode, fake, lossy, suspicious,
      unnecessary, wasted, real/true resolution.
      **Done, and extended past the list.** Loudness's sweep plus every word above, plus codec, mp3,
      aac, cutoff, rolloff, filtered, truncated, genuine, authentic, and the phrases that smuggle an
      inference in without using any of them — "appears to be", "was probably", "suggests that". Word-
      split rather than substring, because "bandwidth" contains "band" and "programme" contains "gram".
      Nothing names a platform or a container format, and nothing invokes Nyquist or the declared rate:
      that is asserted twice over, by the sweep and by comparing a mid-band reading against one at the
      top of the band and requiring the same strings. Nothing is coloured, badged or weighted by what
      the value contains, and there is **no disclaimer sentence** — one would introduce the very frame
      the measurement refuses, and would be longer than the fact it qualifies.
- [x] 7.3 Absence in the existing not-computable phrasing.
      **Done**, in the report's own words: "Not computable for this file.", with the detail sentence and
      the "Everything else in this report is unchanged." closing every sibling uses. Never a number —
      not zero, not Nyquist — and the words "silence", "silent" and "insufficient" are swept for, since
      the cause is not something presentation knows. A **measurement that carries no reading** (eligible
      windows, no bin meeting persistence) reads as the same absence rather than as a zero or a dash; it
      is not a second enum case, because the distinction is about what to show.
- [x] 7.4 Accessibility: the value and its unit announced together — **structural only**; the VoiceOver
      traversal gap that blocks ADR-0015 and ADR-0017 is not this change's to close.
      **Done, structurally.** "Programme bandwidth, 16.1 kHz" as one sentence, and "Analysis resolution,
      23 Hz" as its own — the resolution is a separate quantity spoken separately, for the same reason it
      is not appended with a `±`. Every non-measured state names the section first, so a reader landing
      on the sentence knows what it is about. The method line is announced as part of the measurement
      rather than as decoration. **The traversal gap is untouched**: this adds a section to the same
      scrolling area every other analysis lives in, so it inherits the gap rather than fixing or
      worsening it, exactly as true peak's own validation recorded.

## 8. Export

**Done, and the export chain's own debt was paid first.** `ReportExporting`, `ReportExportAction` and
`ReportExportModel` each carried a note saying three positional optionals was past the shape's
comfortable width, that a container was the answer, and that introducing one touches every call site —
so it was deferred to whoever added a fourth measurement, *precisely* so the refactor would not be
hidden inside that change. Programme bandwidth is the fourth. `ReportMeasurements` landed on its own
commit, before anything was added to it, and is **observationally neutral**: the exported bytes for all
five combinations — nothing, signal levels alone, true peak alone, loudness alone, all three — are
byte-identical before and after, compared by checksum, with the same 1381 tests passing unchanged.

It lives in `AudioInspectorDomain` because both ends of the chain need it, and holds only settled domain
measurements. `InspectionAnalyses` was considered and rejected on three independent grounds: it is the
*flow's* bundle, it carries the waveform and the spectrogram, and its fields are `…Outcome` values
modelling lifecycle that must never reach the wire.

- [x] 8.1 Additive under `measurements`, `schemaVersion` stays **1**, key omitted when absent, never
      `null`.
      **Done.** A fourth sibling under `measurements`, `schemaVersion` unchanged, and a report exported
      without it is **byte-identical** to one from before the key existed. Absence is the key not being
      there — never `null`, never a zero, never Nyquist, never an empty object. A measurement can also
      exist and carry **no reading** (its windows were eligible and no bin met the persistence
      criterion); the Feature collapses that to no key as well, so the section's not-computable sentence
      and the document never disagree. That is loudness's own rule, whose absence likewise has several
      causes and exports none of them: **the document describes measurements, never why one does not
      exist.**
- [x] 8.2 Carry the frequency, the resolution and the method identity. No verdict, no declared-rate
      comparison, no oracle metadata.
      **Done.** Hertz as unrounded `Double`, both numbers. The screen shows `16.1 kHz`; the wire carries
      `16101.5625`, and a test asserts the two are **different** — a change that exported the displayed
      number would otherwise pass a test that merely checked for a plausible figure.

      **`resolution` is a separate field and never an interval.** It is the width of an analysis bin,
      not an uncertainty, so there is no `±` and no `uncertainty`, `error`, `tolerance` or `margin`
      anywhere. The interval form would be wrong twice: it would claim a bound this measurement does not
      support, and the reading is biased **one way** — upward, by the window's leakage — so a symmetric
      interval would be wrong in shape as well as in kind.

      **The method is copied, never reconstructed.** One versioned identifier plus `windowFrames`,
      `hopFrames` and `sampleRate`. The threshold, the persistence fraction and the budget are *not*
      duplicated as fields: the identifier stands for the whole rule set, and emitting them as data
      would invite a consumer to believe some other combination was possible. The frame counts *are*
      exported because the window is fixed in **time**, so they differ per rate and cannot be
      reconstructed. Nothing branches on a sample rate — a control that derives the window from the rate
      fails the multi-rate test.

      **No verdict anywhere.** No comparison against the declared rate, no confidence, no score, no
      codec named or guessed at, and no field in which such a conclusion could be expressed. Channels
      keep their index with `null` where a channel carried nothing, and no layout is named.
- [x] 8.3 Document it in `docs/json-schema-v1.md` with the same honesty the loudness section uses.
      **Done**, in the same shape and with the same refusals: the field table, why the key is not
      `cutoff`, `frequencyLimit`, `effectiveSampleRate` or the domain's own name, why `resolution` is a
      grid rather than an error bar, why the rule set's constants stand behind the identifier instead of
      travelling as data, and an explicit statement that this measurement does **not** show a file was
      upsampled, transcoded or produced from a lossy source — a band limit is a fact about content, and
      the causes that could produce one are not distinguishable from it.

      Ten negative controls, each applied and reverted: a rounded frequency, kilohertz, the resolution
      rendered as an uncertainty pair, a hardcoded method, a window derived from the sample rate, an
      explicit `null` key, `schemaVersion` 2, a `cutoffDetected` field, and persistence disabled so the
      click diverges — all nine fail a test. The tenth, reintroducing positional optionals on the port,
      is a compile error.

## 9. Deferred, and named so it is not quietly dropped

**Considered and deliberately scoped out — none of it was started, and none of it is pretended.** The
checkboxes stay unticked on this repository's own precedent: `add-true-peak-measurement` was archived
with five deferred tasks open (its group 11), because a deferred item is neither done nor forgotten and
ticking it would claim work that does not exist. Each entry below says where the work actually lives.

- [ ] 9.1 **Shared STFT stage** — `SpectrogramAccumulator` already computes 1025 bins per hop and
      discards the resolution. Extract it once `average spectrum` gives it a second consumer, proving
      equivalence against the values this change pins. Not done here.
      **Still deferred, and the trigger is unchanged: it needs a second consumer.** This change measured
      what a private transform costs rather than assuming it — the sixth consumer adds what it costs
      alone, 0.05–0.20 s per audio-minute in Release, with no overhead beyond itself (5.4) — so the
      extraction is an optimisation with a known price rather than a necessity. The equivalence values
      it would have to reproduce now exist and are pinned by groups 2, 3 and 6.
- [ ] 9.2 **Average spectrum** — the other unbuilt item of the roadmap's Phase 1b. Not started here.
      **Still deferred.** It is the second consumer 9.1 waits for, and the two are one piece of work.
- [ ] 9.3 **Comparison between two files** — an overlap test within resolutions, not equality, and an
      extension of `FileComparison`'s contract rather than a row. Not designed here.
      **Still deferred, and this change deliberately did not touch comparison at all**: no comparison
      production file is in its diff. The shape it would need is now more constrained than when this was
      written — an overlap must be tested within *each file's own* resolution, and this change
      establishes that the resolution is ~23 Hz at every rate because the window is time-locked.
- [ ] 9.4 **Findings / Evidence·Inference·Conclusion** — this change builds one indicator; an evidence
      engine needs several. Not started here.
      **Still deferred, and this change is the strongest argument for keeping it that way.** Programme
      bandwidth is precisely the indicator a reader most wants turned into a conclusion about a file's
      origin, and both surfaces refuse to: ADR-0023 §1, the presentation's vocabulary sweep, and the
      export contract, which provides no field in which such a conclusion could be written.

## 10. Gates and closure

- [x] 10.1 Four gates green plus the Xcode build and `git diff --check`.
      **Done.** `./Scripts/check-boundaries.sh`, `swift build -Xswiftc -warnings-as-errors`,
      `swift test` (run twice) and `OPENSPEC_TELEMETRY=0 openspec validate --all --strict`, plus
      `git diff --check` clean. **The Xcode build applies and was run**: the package is SwiftPM but
      `App/AudioInspector.xcodeproj` links it as the shipped app target, and
      `xcodebuild -scheme AudioInspector -configuration Debug build` succeeds — this task's mention of
      it is current, not stale.
- [ ] 10.2 Decide ADR-0023's status from what was actually done, update `CURRENT.md`, and archive
      through `openspec archive` **after merge**.
      **Two of three done; the third is gated on merge by this task's own wording.** ADR-0023's status
      was decided from what was actually done and is now **`Accepted` (2026-08-20)**, promoted on its
      three literal conditions and on nothing else, with a `Promotion` section recording the evidence
      *and* what it does not cover — including that the manual pass was narrower than ADR-0019's, which
      is stated rather than smoothed over. `CURRENT.md` is updated. **The archive has not run**, and
      must not: this task places it after merge, and nothing has been pushed, opened as a pull request
      or merged. This entry stays open until then.
