# Tasks — significant bandwidth

**Nothing below is implemented.** Group 1 is blocking by design: no accumulator exists until the
methodology is measured. This is the order `add-loudness-measurement` used — constants settled and
sourced before an accumulator existed — and the reason its numbers survived review.

**Group 1 status.** 1.1–1.4 are settled from measurement in
`docs/spikes/2026-08-19-significant-bandwidth-methodology.md`: the threshold is **−50 dB relative to the
loudest bin in the same analysis window**, the persistence criterion is **≥ 10 % of eligible windows**,
and the two are **not sufficient on their own** — a window-eligibility gate at −60 dB below the file's
global spectral peak and an absolute silence floor at −120 dBFS are both required, and both are measured
rather than assumed. 1.5 and 1.6 remain open. ADR-0023 stays `Proposed`.

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
- [ ] 1.5 Fix the **resolution claim**: bin width per rate, and how a Hann window's spread widens the
      real uncertainty beyond one bin. Decide whether the reported value is a bin centre, a bin edge, or
      a range.
      **Measured, not yet decided.** The overshoot above a known hard cut-off is **≈ 4 bins, one-sided
      upward** — 3.7 to 4.35 bins at four different bin widths, across 48 and 192 kHz and FFT
      2048/4096/8192. So the honest uncertainty is about four bins, not half of one. Still to settle: bin
      centre / edge / range, paired with the analytic Hann main-lobe figure rather than this empirical one
      alone. Also open, and found here: the persistence constant is **tied to the analysis window** — the
      same signal reads 16 043 Hz at FFT 4096 and 24 000 Hz at FFT 8192 — so the method identity must
      carry `fftSize` and `hop`, and whether the window should be fixed in *time* rather than in samples
      is a group 3 question. Spike §7.
- [ ] 1.6 Record every constant with its source in a spike document, as
      `docs/spikes/2026-08-18-loudness-measurement-validation.md` Part A does.
      **Table written** at `docs/spikes/2026-08-19-significant-bandwidth-methodology.md` §11, with the
      source of each of the seven constants settled so far. It cannot be called complete while 1.5's
      constant does not exist.

## 2. Fixtures and the oracle

- [ ] 2.1 Reuse `AudioFixtureSignal.bandLimitedTones` and the existing format matrix rather than adding
      a generator. Extend it **only** where a graded roll-off or a noise floor cannot be expressed.
- [ ] 2.2 Cases: pure tone; tones to a known edge; two neighbouring edges; white noise; silence; a lone
      impulse; high content present ~1 % of the time; the same persistent; a high band at −20, −40 and
      −60 dB.
- [ ] 2.3 The same described signal at 44.1 / 48 / 88.2 / 96 / 192 kHz, written as real files.
- [ ] 2.4 WAV / FLAC / ALAC / AIFF equivalence, and AAC separately, on the container matrix's own
      precedent that a lossy codec is a different question.
- [ ] 2.5 Qualify FFmpeg as a **corroborating oracle only** where it can measure something comparable.
      It is not a normative source here and there is no published target for this quantity — which makes
      the analytic fixtures the primary evidence, not the tool.

## 3. The accumulator

- [ ] 3.1 `SignificantBandwidthAccumulator` in `AudioInspectorAnalysis`, taking `PCMChunk` like its five
      siblings, with its own STFT at full bin resolution.
- [ ] 3.2 **Chunk independence**, demonstrated by a test that fails when it is broken, at the same chunk
      sizes loudness uses.
- [ ] 3.3 Bounded memory: per-bin persistence counters, never a retained spectrogram.
- [ ] 3.4 Decide mono/stereo handling — per channel, or combined — and state why. Whatever is chosen
      must not assert a channel layout the pipeline does not read.

## 4. The domain model

- [ ] 4.1 `SignificantBandwidth` — `Sendable`, `Equatable`, failable, **not** `Codable`, carrying the
      frequency, the resolution it was measured at, and its method identity.
- [ ] 4.2 The method carries **identities, not editable configuration**, on `LoudnessMethod`'s own
      precedent: the same identifier must imply the same number.
- [ ] 4.3 **No verdict field of any kind**: no `isBandLimited`, no `suspectedUpsample`, no confidence,
      no comparison against the declared rate.
- [ ] 4.4 Absence is an optional the producer returns, never a floor. Nyquist is not a result.

## 5. The sixth consumer

- [ ] 5.1 One field on `SharedPCMAnalysisOutcome`, one accumulator in the composition. **The read count
      stays one**, at the gate that already asserts it.
- [ ] 5.2 Isolation: its failure or absence changes nothing about the other five, with negative controls.
- [ ] 5.3 **The container refactor is due.** `SourceInspectionOutcome.inspected` already carries five
      labelled payloads and its own note says a sixth "should not simply be appended". Decide here
      whether this change introduces the container or records why it does not — do not append silently.
- [ ] 5.4 Measure the real cost 5-against-6, as group 7 of `add-loudness-measurement` did. Baseline for
      reference: the five-consumer pass takes 1.02 s for 60 s of stereo at 48 kHz and 3.54 s at 192 kHz
      in Debug.

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
