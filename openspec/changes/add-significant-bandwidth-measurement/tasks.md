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

**Partly done. 5.1 and 5.3 are demonstrated; 5.2 and 5.4 are not, and are not marked.**

- [x] 5.1 One field on `SharedPCMAnalysisOutcome`, one accumulator in the composition. **The read count
      stays one**, at the gate that already asserts it.
      **Done.** The accumulator is built in `prepare(for:)` from the same `PCMStreamDescription` as its
      five siblings, fed in `accumulate(_:)`, ended in `failAll`, and finished in `finish(stream:)` —
      no protocol, no generic machinery, no second decoder. It follows **loudness's** shape rather than
      the others': its `init?` declines a stream it does not claim, which is an absence and not a fault,
      so it has an `absent` flag and no fault of its own. `SharedPCMDecodeCountTests` now asserts the
      read count with programme bandwidth **`.available`** rather than merely present, and pins the
      update order with the sixth last and the five before it unchanged.
- [ ] 5.2 Isolation: its failure or absence changes nothing about the other five, with negative controls.
      **Not demonstrated.** The composition's existing shape makes each consumer's outcome independent,
      and the producer-failure, cancellation and no-stream paths all carry a sixth value — but no test
      yet drives those paths *for this consumer*, and none of the negative controls this task asks for
      has been written. Until they exist this stays open.
- [x] 5.3 **The container refactor is due.** `SourceInspectionOutcome.inspected` already carries five
      labelled payloads and its own note says a sixth "should not simply be appended". Decide here
      whether this change introduces the container or records why it does not — do not append silently.
      **Done, and done first.** `InspectionAnalyses` groups only what an inspection derives from the
      file's samples; the report stays outside it because it exists before the first chunk, and
      `InspectionPresentation` stays separate because it models states that move from `.loading` rather
      than settled outcomes. The migration was landed as its own commit and is **observably neutral**:
      the same 1309 tests in 140 suites passed before and after, with the sixth analysis added only
      afterwards. The new field carries **no default**, so omitting it is a compile error.
- [ ] 5.4 Measure the real cost 5-against-6, as group 7 of `add-loudness-measurement` did. Baseline for
      reference: the five-consumer pass takes 1.02 s for 60 s of stereo at 48 kHz and 3.54 s at 192 kHz
      in Debug.
      **Not measured.** The accumulator's isolated cost is known (0.07/0.07/0.14/0.28 s per audio-minute
      at 44.1/48/96/192 kHz in Release), but the 5→6 delta through the shared pass has not been run.

## 6. Correctness against the fixtures

- [ ] 6.1 A known edge is reported within the stated resolution, at every supported rate.
- [ ] 6.2 **The impulse control**: a file silent but for one click reports no wider a band than silence
      does. This is the property the whole design exists for.
- [ ] 6.3 A quiet-but-persistent band is reported; a loud-but-isolated one is not.
- [ ] 6.4 Rate invariance: the same described signal agrees within resolution across the five rates.
- [ ] 6.5 Undefined cases yield absences: no audio, shorter than one window, silence.
- [ ] 6.6 A lossy encoder's band limit survives being rewrapped as WAV, on
      `MP3SpectrogramEvidenceTests`' own precedent — reported as a frequency, with no codec named.
- [ ] 6.7 Negative controls against production, each applied and reverted: persistence disabled;
      threshold made absolute; the reduction changed to a maximum over time; resolution reported finer
      than a bin; Nyquist substituted for an absence.

## 7. Presentation

- [ ] 7.1 One row, its own section or beside the spectrogram, stating what was measured and at what
      resolution. No precision beyond the resolution.
- [ ] 7.2 **No verdict and no comparison against the declared sample rate.** The forbidden vocabulary
      sweep that loudness uses, extended with: upsample, transcode, fake, lossy, suspicious,
      unnecessary, wasted, real/true resolution.
- [ ] 7.3 Absence in the existing not-computable phrasing.
- [ ] 7.4 Accessibility: the value and its unit announced together — **structural only**; the VoiceOver
      traversal gap that blocks ADR-0015 and ADR-0017 is not this change's to close.

## 8. Export

- [ ] 8.1 Additive under `measurements`, `schemaVersion` stays **1**, key omitted when absent, never
      `null`.
- [ ] 8.2 Carry the frequency, the resolution and the method identity. No verdict, no declared-rate
      comparison, no oracle metadata.
- [ ] 8.3 Document it in `docs/json-schema-v1.md` with the same honesty the loudness section uses.

## 9. Deferred, and named so it is not quietly dropped

- [ ] 9.1 **Shared STFT stage** — `SpectrogramAccumulator` already computes 1025 bins per hop and
      discards the resolution. Extract it once `average spectrum` gives it a second consumer, proving
      equivalence against the values this change pins. Not done here.
- [ ] 9.2 **Average spectrum** — the other unbuilt item of the roadmap's Phase 1b. Not started here.
- [ ] 9.3 **Comparison between two files** — an overlap test within resolutions, not equality, and an
      extension of `FileComparison`'s contract rather than a row. Not designed here.
- [ ] 9.4 **Findings / Evidence·Inference·Conclusion** — this change builds one indicator; an evidence
      engine needs several. Not started here.

## 10. Gates and closure

- [ ] 10.1 Four gates green plus the Xcode build and `git diff --check`.
- [ ] 10.2 Decide ADR-0023's status from what was actually done, update `CURRENT.md`, and archive
      through `openspec archive` **after merge**.
