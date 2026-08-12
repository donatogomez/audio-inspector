# Implementation Tasks

**Groups 1–5 are done, and group 5's stop rule fired.** The contract, the methodology, the domain
model and the accumulator are finished and tested; the end-to-end cost measurement then **rejected a
fourth PCM read** and blocked the wiring. Evidence:
`docs/spikes/2026-08-11-true-peak-methodology-validation.md` and
`docs/spikes/2026-08-12-true-peak-end-to-end-cost.md`.

**Group 6 is now done, and it is what group 5 was waiting for**: `add-shared-pcm-read` merged, so true
peak is wired as a **third consumer of the read that already exists** rather than as the fourth decode
the measurement rejected. An inspection reads the samples **twice**, with true peak included, and the
third consumer costs its DSP and no decode (6.6). **Groups 7 and 8 are done too**: the value is on screen
in its own section, in **dBTP**, with the method stated in words and no verdict attached to it, and its
independence from `clippedSampleCount` is demonstrated rather than asserted. **Group 9 is done as well**: the value is exported under
`measurements.truePeak`, linear, with its method, and without a `schemaVersion` bump. What remains is
group 10 — the gates, the manual validation, and ADR-0019's own status decision.

**The methodology is now fixed and is no longer a decision for a later group**: polyphase FIR, **8×**,
**48 taps per phase**, Kaiser **β = 6.0**, cutoff **1.0**, phases normalised, **zero-extension** at the
edges, **`Float`** arithmetic, **linear** internally and **dBTP** only on screen, agreement with FFmpeg
within **0.05 dB** on signals smooth at their boundaries. A later group that wants to change any of
these changes the analysis engine version, not a preference.

Boundaries no future task may cross: the measurement is **estimated, never read from the samples**;
`TechnicalProperties` gains nothing (ADR-0018 — this needs decoded audio); `SignalLevelMetrics`, its
accumulator, its presentation, its export object and `clippedSampleCount` are **not modified**;
Accelerate stays inside `AudioInspectorAnalysis` and no `vDSP` type crosses a port; no framework type or
error crosses a domain port; **no constant is chosen without a measurement behind it**; no LUFS, no LRA,
no crest factor, no significant max frequency, no finding, no flag, no score.

## 1. The contract

- [x] 1.1 Open the change with `proposal.md`, `design.md`, this task list, and the delta spec on
      `audio-signal-level-metrics` (ADDED only — the existing sample-level requirement, its clipping
      threshold and its isolation requirement are deliberately left untouched, so no requirement is
      duplicated).
- [x] 1.2 Read ADR-0006 literally and separate what it **fixes** (standard, ≥4× oversampling before peak
      detection, factor and filter recorded with the result, `AudioInspectorAnalysis` + Accelerate,
      FFmpeg `ebur128` as the cross-check oracle with explicit tolerances, named constants tied to the
      engine version) from what it **leaves open** (`design.md` §3–4). Six open decisions named rather
      than silently chosen: the factor above 48 kHz, the interpolation filter, edge handling, arithmetic
      width, the cross-check tolerance, and whether the oracle can run in CI.
- [x] 1.3 Define true peak normatively against sample peak, with the four boundary cases decided in
      advance — silence, zero frames, samples beyond full scale, and the "never below the sample peak"
      invariant (`design.md` §2).
- [x] 1.4 Audit the native APIs and split them into **methodologically equivalent** (vDSP polyphase FIR,
      chosen) and **convenient but semantically different** (`AVAudioConverter`/`AudioConverterRef`,
      rejected: unpublished filter, OS-version-dependent, and it would put the measurement in the module
      that owns file access rather than DSP). `vImage` not applicable; frequency-domain interpolation
      kept as a measured candidate rather than dismissed (`design.md` §5).
- [x] 1.5 Decide the domain placement against four options and record why a sibling type wins over
      extending `SignalLevelMetrics` (`design.md` §6), and why no analysis-engine-version field is
      introduced here (ADR-0006 ties it to *stored* results; there is no store yet — ADR-0004).
- [x] 1.6 Write **ADR-0019** in `Proposed` for the two decisions ADR-0006 does not make — a measurement
      carrying its own methodology, and a positive true peak reported as a value rather than raised as a
      flag — with its promotion conditions. Add its row to `docs/adr/README.md`. ADR-0006 is
      **referenced, never edited**.

## 2. The methodology spike — measure before implementing

**Done. All six open decisions are closed by measurement**, and three of them closed *against* what
`design.md` first assumed. Evidence:
`docs/spikes/2026-08-11-true-peak-methodology-validation.md`. Spike package:
`Spike/validate-true-peak/`, outside the production graph, deleted when ADR-0019 is Accepted and this
slice's own tests cover its observations. **No `Sources/` or `Tests/` file was touched.**

- [x] 2.1 Built the disposable spike (`Spike/validate-true-peak/`, its own SwiftPM package, Swift 6 mode
      with `-warnings-as-errors`, importing nothing but Accelerate and Foundation). **21 fixtures**,
      every one synthesised from a formula and written as a hand-built RIFF/WAVE IEEE-float file, so no
      external audio is evidence anywhere and no framework's own conversion sits between the formula and
      the oracle. Covers all seventeen requested characteristics: silence; crest on a sample; crest
      between samples; near Nyquist; sample peak < 1 with true peak > 1; a stored sample of 1.5; an
      impulse; hard edges; energy at the first and at the last frame; mono; stereo with different
      channels; 44.1/48/96/192 kHz; and a music-like programme (12 partials plus seeded noise).
      **Four fixtures were added mid-spike, not planned** (faded and exactly-periodic tones) — see 2.4.
- [x] 2.2 **The filter: polyphase FIR, 48 taps per phase, Kaiser β = 6.0, cutoff = 1.0, each phase
      normalised to unit sum.** Chosen from a 24-design sweep on the criterion this product actually
      needs: flat within ±0.1 dB across 16–20 kHz, which is 0.73–0.91 of Nyquist at 44.1 kHz. 48 taps is
      the shortest design that reaches it (0.93·N); 32 taps stops at 0.89·N; 64 and 96 buy nothing
      usable. Image leakage is ≤ +0.02 dB for every design, so it never became the binding constraint.
      **BS.1770's own annex coefficients were not used and not reproduced: the standard's text was not
      available to this spike**, and remembered numbers would be fabricated evidence. The designed
      filter is validated instead against analytic ground truth and against FFmpeg's own R128 meter, and
      the resulting claim is bounded accordingly everywhere it appears (`design.md` §4.8).
- [x] 2.3 **The factor: 8×, flat at every supported sample rate.** Decided on worst-case behaviour over
      64 signal phases per frequency, not on a single lucky phase: **−0.169 dB at 4× versus −0.042 dB at
      8×**. R128 limits are quoted to 0.1 dB, so 4× — legal under ADR-0006's "≥4×" — can flip the
      judgement a reader is making. Rate-dependence was rejected because 2× at 192 kHz would break
      ADR-0006's own floor. Measured cost of the choice: +0.29 s Release / +0.33 s Debug on a ten-minute
      stereo file.
- [x] 2.4 **Edge handling: zero-extension.** The only policy that neither fabricates nor misses:
      `constant` reads **1.1303** where the file's own maximum is 1.0, `mirror` reads **0.9432** on a
      tone whose true peak is provably 0.9, and `interior-only` reads **0.000014** on a file whose peak
      is a full-scale sample at frame 0 — breaking the `truePeak >= samplePeak` invariant outright.
      **This is also where the spike corrected itself**: the first run showed both this implementation
      *and* the oracle reading above a tone's own amplitude, and faded and exactly-periodic fixtures were
      added to separate edge ringing from filter error. It was entirely edge ringing — a file's boundary
      against silence is a real discontinuity, and its overshoot is a fact about the file, not an
      artefact to remove.
- [x] 2.5 **The tolerance: 0.05 dB against FFmpeg for signals smooth at their boundaries, up to 96 kHz;
      0.0042 dB against analytic truth.** Derived rather than rounded up for comfort: worst measured
      agreement **0.0236 dB**, plus the oracle's own ±0.0048 dB printing quantisation, gives 0.029 dB
      credible worst. Fixtures with truncated boundaries disagree by up to 1.05 dB and are **excluded
      with a reason** — they measure two filters' edge ringing, not agreement — and are checked against
      analytic truth instead. 192 kHz is excluded as **not comparable** (2.6).
- [x] 2.6 **The oracle is gated on FFmpeg's presence; the analytic fixtures carry the CI-enforced
      claim.** Three oracle limitations were measured, not assumed: it prints true peak to three decimal
      places linear (a ±0.0005 floor), it **does not oversample at 192 kHz at all** (its true peak
      equals its own sample peak there, against an analytic 0.9), and on truncated fixtures it measures
      edge behaviour. The analytic fixtures have exact answers, need no external tool, and agree ten
      times more tightly — so gating the weaker check is not a weakening, and "cross-checked in tests"
      never quietly means "on one machine only". FFmpeg stays a dev/test dependency, never shipped
      (ADR-0003 §4).
- [x] 2.7 Spike report written: `docs/spikes/2026-08-11-true-peak-methodology-validation.md` — environment,
      fixtures, verbatim oracle command, every table, the candidates rejected, the corrections this spike
      forced on `design.md`, falsification criteria written before the measurements, and the deletion
      criterion for the package.

**Also closed here, though not listed as a task**: `truePeak >= samplePeak` is proven **structural**, not
patched. Phase 0 of the interpolator is the exact identity because `sinc` is zero at every non-zero
integer, so the stored samples are inside the set the maximum is taken over — worst shortfall over 21
fixtures is exactly `0.0`, and the negative control (cutoff 0.90) breaks it by −0.16 as predicted.
Chunk independence is **bit-exact** at every chunk size from one frame up, and `Float` matches `Double`
to 1.9 × 10⁻⁷ linear, so the accumulator uses `Float` (`design.md` §4.4, §4.9).

## 3. The domain model

**Done.** `Sources/AudioInspectorDomain/ValueObjects/TruePeakMeasurement.swift` — **zero imports**, no
Accelerate, no AVFoundation, no SwiftUI, no `Codable`, no JSON or `schemaVersion`, no dependency on
`AudioInspectorAnalysis`. Nothing about DSP: the file holds a result and the identity of the method that
produced it, and does not know how to produce one.

- [x] 3.1 Added the sibling value type. `TruePeakMeasurement` (named for what it is — one measurement
      carrying its own methodology, per ADR-0019 — rather than `TruePeakMetrics`, which would claim a
      plurality of metrics that does not exist), with `TruePeakMeasurement.Channel` (`sampleCount`,
      `truePeak: Float?`), `TruePeakMethod` (`oversamplingFactor`, `filter`) and
      `TruePeakFilterIdentifier`. `Sendable`, `Equatable`, **not `Codable`**, and deliberately not
      `Comparable` or `Hashable` — no order over measurements is meaningful and nothing keys on one.
      **The `nil`-iff-empty rule is enforced in both directions by a failable initialiser**, following
      `WaveformBucket`/`WaveformEnvelope`/`Spectrogram` rather than `SignalLevelMetrics`'s unchecked
      init: a contradictory channel is unrepresentable, not merely undocumented.
      **`overallTruePeak` is derived, never stored** — a computed maximum over the channels, so it has
      no initialiser argument and no stored property and therefore *cannot* disagree with them. That
      differs from `SignalLevelMetrics`, which must store its overall values because `overallRMS` and
      `overallDCOffset` are genuinely not functions of the per-channel results; a maximum of maxima is.
      **The filter identity follows `WarningCode`'s own precedent** — a `RawRepresentable` over `String`
      with named static members and a `snake_case` rawValue (`"polyphase_fir_v1"`), chosen after
      auditing how this repository already versions contracts rather than inventing a format. The
      rawValue is the identity, so renaming the Swift member or moving the file cannot change it, and
      the `v1` names a whole methodology: changing the taps, β, cutoff, normalisation or edge policy
      requires a new identity.
      **The 48 taps, the β and the cutoff are deliberately *not* in the model.** It records which
      methodology ran, never how to configure one — a result type carrying its own DSP parameters would
      let a consumer write back a measurement that never happened.
- [x] 3.2 Documented in the type itself, in the register `SignalLevelMetrics` uses for its own cases:
      linear not decibels (dBTP named as a presentation unit that appears nowhere in the module); values
      beyond full scale kept and never clamped; "not computable" distinct from a measured zero, stated
      in both directions; why the overall is the maximum and why that combination is exact; why the
      sample peak is **not** duplicated here and where `truePeak >= samplePeak` is demonstrated instead;
      and why the type is not `Codable`.
- [x] 3.3 Unit-tested with constructed values, no file and no DSP —
      `Tests/AudioInspectorKitTests/TruePeakMeasurementTests.swift`, **35 tests** (757 → 904 across the
      suite): mono, stereo, six-channel; the `nil` rule in both directions; every empty; one empty beside
      one measured; empty beside silent; zero, below, at and above full scale (0.9999999, 1.0, 1.0000001,
      1.05, 1.5, 8.0, 1000.0) surviving construction unchanged; negative, `NaN`, signalling `NaN`, both
      infinities and a negative sample count all rejected; an empty channel list rejected; negative zero
      accepted and behaving as zero; the overall equal to the maximum and order-independent; the method
      travelling with the value and participating in equality; the filter rawValue pinned literally;
      `Sendable` by compile-time constraint; and `Codable`/`Comparable`/`Hashable` proven **absent** by
      runtime conformance check rather than by comment.
      **Two negative controls, both reverted in full** (`diff` against a pre-mutation copy showed no
      residue): (1) computing the overall as a **mean** instead of a maximum broke 6 assertions across 4
      tests, including the one that exists to say the overall is not a mean; (2) **clamping** a value
      above full scale to 1 broke 14 assertions across 4 tests. Both confirmed the tests discriminate
      rather than passing vacuously.

## 4. The accumulator (`AudioInspectorAnalysis`, Accelerate — placement already fixed by ADR-0006)

**Done.** `Sources/AudioInspectorAnalysis/TruePeakAccumulator.swift` — nothing `public`, nothing
reachable from a feature or the app, and no reference to it anywhere outside `AudioInspectorAnalysis`.
Domain, Media, the features, the app, the JSON contract, the waveform and the spectrogram are **all
untouched**: this group added two files and modified none.

- [x] 4.1 Implemented as a polyphase FIR at 8×, 48 taps per phase, Kaiser β 6.0, cutoff 1.0, phases
      normalised to unit sum — one `vDSP_conv` plus one `vDSP_maxmgv` per phase, run at the **input**
      rate, so the zero-stuffed 8× signal is never materialised and no buffer scales with 8× the
      duration. `window` and `convolved` are allocated once and reused, growing only to the largest chunk
      seen. **The 384 coefficients are generated from the four parameters, never pasted**: there is no
      table in the repository, so the constants remain the single source of truth. `sinc` evaluates its
      integer zeros exactly (`u == u.rounded()` → `u == 0 ? 1 : 0`) rather than through
      `sin(πu)/(πu)`, which returns ~1e-16 there. Every constant is `static let` on an internal type —
      no configuration surface exists at any layer.
- [x] 4.2 Continuity across chunks: exactly `tapsPerPhase - 1` = **47** samples cross each boundary,
      which is the 23 of left context a position needs plus the 24 of lookahead that hold back the last
      positions of a chunk until the next arrives. **The task list previously named only the 23** —
      that figure is the left-context/zero-extension depth, and carrying only it would lose the
      positions that were not yet emittable; 47 is what an FIR of length 48 provably cannot do without.
      No `removeFirst` on a growing buffer: `pending` never exceeds 47 between calls, so maintaining it
      copies a fixed 47 floats per chunk regardless of chunk size or file length. Verified **bit-exact**
      at 1, 3, 127, 512, 2048, 4096, 65536 and whole-file, mono and stereo, on five signals — equality,
      not tolerance.
- [x] 4.3 The invariant is structural. Phase 0's taps are exactly `0, …, 1, …, 0` (asserted with `==`,
      not a tolerance), so the reconstruction reproduces the stored samples bit for bit and the maximum
      is taken over a set that already contains them. **No clamp exists in the file**, and `truePeak >=
      samplePeak` is asserted across nine signals including silence, an impulse, a stored 1.5, and
      energy at the first and last frame. Group 2's negative control is now a run test rather than a
      comment: at cutoff 0.90 phase 0 stops being the identity and the invariant breaks on five of the
      nine.
- [x] 4.4 The convolution is `Float` end to end, with the reason documented beside the code. Pinned by a
      test against a deliberately slow `Double` reference reconstruction written the least clever way
      possible: agreement within 1e-6 linear, consistent with the 1.9 × 10⁻⁷ the spike measured.
- [x] 4.5 **28 tests**, no file and no framework beyond Accelerate: the filter's own shape (phase-0
      identity, exact sinc zeros, unit-sum phases, 384 coefficients); silence as a measured zero; a crest
      on a sample; a crest hidden between samples where the stored samples read 3 dB lower; sample peak
      below full scale with true peak above it; an impulse reconstructing to exactly its own height; a
      stored 1.5 measured and not clamped; energy at the first and last frame; a truncated tone keeping
      its own boundary overshoot; chunk independence mono and stereo; determinism; per-channel
      independence with no mixdown; six channels; all four sample rates including **192 kHz against
      analytic truth**; zero frames and empty chunks reporting `nil` rather than zero; a file shorter
      than the filter; a mismatched chunk ignored; an invalid channel count refused; and the method
      travelling with the result.
      **Three negative controls, all reverted in full** (`diff` against a pre-mutation copy showed no
      residue each time): (1) **cutoff 0.90** broke the phase-0 identity and `truePeak >= samplePeak` on
      five signals; (2) **constant extension at the tail** instead of zeros fabricated **+1.13 dB** on
      the last-frame fixture — the same 1.1303 the spike measured for that policy; (3) **carrying no
      history between chunks** collapsed chunk independence and dropped the last-frame peak to 0.0003.
- [x] 4.6 Cross-checked against FFmpeg `ebur128 peak=true+sample` in its own suite,
      `Tests/AudioInspectorKitTests/TruePeakOracleTests.swift`, gated on the tool's presence with a skip
      message that says outright that a skip is **not** evidence of agreement. Within the tolerance
      pinned in 2.5 (**0.05 dB**) at 44.1, 48 and 96 kHz on faded tones and on a complex programme.
      **192 kHz is deliberately absent from this suite** — the oracle does not oversample there, so a
      comparison would measure its limitation; that rate is covered by analytic truth in 4.5. The oracle
      test reads **both** `true_peak` and `sample_peak` and asserts the two stay ordered in both meters,
      which is the independence `design.md` §12 claims.

## 5. Cost — measured before the architecture is committed to

**Done, and the stop rule fired.** Evidence:
`docs/spikes/2026-08-12-true-peak-end-to-end-cost.md`. The harness drove the real
`SourceInspectionCoordinator` with its production defaults, real files, real AVFoundation decode and
the real `TruePeakAccumulator`; it was created, measured and **deleted**, and **no production file was
touched in this group**.

- [x] 5.1 Measured with a disposable harness, 1 min and 10 min, mono and stereo, Debug and Release,
      against a decode-only baseline. The candidate sweep this task also asked for was already done in
      group 2 (factors 2–16, six filter designs, three implementations), so it is not repeated; what was
      missing and is now measured is the **real** decode path rather than synthetic buffers. Added
      beyond the task: FLAC and AAC, which turned out to be the rows that decide the outcome.
- [x] 5.2 Whole-inspection wall time, three operations versus four. Ten minutes of stereo: **3.804 s →
      4.956 s in Debug (+30.3 %)** and **0.728 s → 1.288 s in Release (+76.8 %)** for WAV; **5.082 s →
      6.658 s** and **2.011 s → 2.986 s** for FLAC. The delta equals the isolated operation in every row
      (1.152 against 1.152; 0.560 against 0.557), so the total is the sum and no contention, cache or
      setup anomaly appears.
- [x] 5.3 **Stop rule applied, and triggered.** Isolating the decode from the measurement — the
      distinction the rule turns on — the fourth read alone costs **23.5 % of a FLAC inspection and
      23.6 % of an AAC one in Release**, and 16–21 % in Debug. That is not "clearly insignificant".
      **The design's own premise was wrong by more than an order of magnitude**: §8 accepted the fourth
      read partly on a cited 0.035 s per decode, which describes the cheapest uncompressed case; the
      real figure against the port is 0.473–0.534 s for a compressed file in Release. §8 kept an escape
      hatch for exactly this — *"remains the escape hatch if group 5's numbers against the real decode
      path disagree"* — and it is used rather than argued away.
      Per the rule: nothing was folded, merged or migrated, the number is recorded, and **a separate PCM
      -sharing change is the next step** (ADR-0016 already permits one *on top of* the seam once
      measurement justifies it — this is that measurement).
      Recorded alongside, because it has a different remedy: the true-peak **DSP** costs about 0.51 s
      Release / 0.53 s Debug for the same file and **no amount of sharing removes it**. That is the
      feature's own price, not the architecture's, and the stop rule does not govern it.

## 6. Wiring — a third consumer of the shared read

> **UNBLOCKED (2026-08-12).** Group 5's stop rule rejected a fourth **read**, not a fourth consumer,
> and named its own release condition: *this group resumes once a PCM-sharing change lands*. It has.
> `add-shared-pcm-read` is merged and archived, the capability that says a file's samples are read once
> is in the canonical specs, and `SharedPCMAnalysisGeneration` — the composition that folds one decode
> into several accumulators — is ordinary code on this branch now. **ADR-0020 is `Accepted`**:
> *independent analyses* is the invariant, *independent decodes* was only the implementation.
>
> **6.1 and 6.2 are rewritten below, and the original wording is quoted so the change is auditable
> rather than silent.** They said *"Add the generation as a **fourth** independent operation over the
> existing `AudioDecoding` port, with its own decoder instance and its own cancellation"* and *"Extend
> the inspection outcome and the presentation state with a **fourth** case … each of the four
> operations"*. **Superseded by ADR-0020**: a fourth *read* is exactly what group 5's measurement
> rejected, and independence no longer comes from owning a decoder. Only the mechanism changed — every
> property those tasks demanded is still demanded, and 6.3 is untouched.
>
> **`TruePeakMeasurement`, `TruePeakAccumulator`, the methodology and their tests are not redesigned.**
> If wiring ever required changing the accumulator, that is evidence the shared architecture is wrong
> and must be justified before proceeding (ADR-0020 follow-ups).

- [x] 6.1 Add true peak as a **third consumer of `SharedPCMAnalysisGeneration`** — one more accumulator
      folded from the read that already exists. It creates **no decoder**, opens no `URL` and no security
      scope, changes neither `AudioDecoding` nor `PCMChunk`, and receives **the same `PCMChunk` value**
      the other two consumers receive, in the same synchronous callback, inside the coordinator's
      existing window (ADR-0010). Its accumulator is built once, from the same single stream description
      the others are built from, so three consumers can never disagree about the file they are reading.
      No `PCMConsumer` protocol: the composition holds it concretely, as a stored property beside the
      other two (`add-shared-pcm-read` design §7).
- [x] 6.2 Extend the shared outcome, the inspection outcome, the update channel and the presentation
      state with true peak's **own** case, exactly as the third analysis was added — beside the others,
      never nested in `InspectionReport`, and with no combined status anywhere. Confirm by test that all
      four settle independently: a failing or cancelled true peak leaves the report, the waveform, the
      spectrogram and the signal levels exactly as they would have been, **and the reverse direction
      too**. Include negative controls that make these tests fail, then revert them in full.
- [x] 6.3 Confirmed: nothing here opens a `URL`, a security scope or a file. The composition receives a
      decoder the coordinator built inside its own window, the read finishes before `run` returns, and
      the existing `theDecoderRunsInsideTheWindow` and *"generating a spectrogram writes nothing beside
      the source"* tests cover the window and the read-only guarantee for the read true peak now shares.
- [x] 6.4 **The decode count is the architectural gate.** Prove at the port that the three shared
      consumers cost **one** `AudioDecoding` call, that a whole inspection performs **two** sample reads
      (the waveform's own and the shared one), and that adding true peak added **none** — with a negative
      control that gives true peak its own decoder and makes the count test fail.
- [x] 6.5 **Chunk independence, which `add-shared-pcm-read` could not test and named as owed.** The
      shared read must produce the **bit-identical** `TruePeakMeasurement` an independent reference
      produces from the same audio, at every chunk size and for the whole file in one chunk — no
      tolerance, because true peak's own guarantee is bit-exactness and sharing must not weaken it.
- [x] 6.6 Measured against production code, 10 min stereo, three runs after a warm-up, on the same
      machine and the same fixtures the shared-PCM confirmation used, so the two are directly
      comparable. **The third consumer costs its DSP and no decode.** Release: the shared pass goes from
      0.378 / 1.032 / 1.133 s (WAV / FLAC / AAC) to 0.949 / 1.592 / 1.703 s — a delta of **0.571 /
      0.560 / 0.570 s**, against a true-peak DSP measured alone at 0.555 / 0.561 / 0.550 s. **The delta
      is the same in all three formats**, which is the signature of a pure DSP cost: a decode would have
      cost 0.058 s more for WAV and 0.700 s more for FLAC, and the deltas would differ by format. Debug
      agrees — deltas 0.681 / 0.689 / 0.768 s against decodes of 0.686 / 1.331 / 1.029 s.

## 7. Presentation

- [x] 7.1 `HumanFormat.decibelsTruePeak`, a **sibling** of `decibelsFullScale` rather than a call to it:
      the arithmetic is identical and the unit is not, and quoting a reconstruction under the stored
      sample's unit would claim a measurement that never happened. Pinned at `1.0 → 0.00 dBTP`,
      `0.5 → -6.02 dBTP`, `1.1 → +0.83 dBTP` (signed and **never clamped**) and exact silence at the
      project's own `-120.00` floor rather than `-∞`. `nil` never reaches it: absence is the caller's
      word, not a fabricated zero.
- [x] 7.2 Its own section, titled *True peak*, beneath *Signal levels* and above *Spectrogram* — with
      levels because it is amplitude, after them because it is a different kind of amplitude. Its own
      `TruePeakPresentation` (`loading`/`measurement`/`absent`/`failed`, no visible `cancelled`), so a
      failure here cannot blank the sample-level rows and a failure there cannot blank this. Per-channel
      detail in the established `Channel 1: … · Channel 2: …` form, only above one channel, **numbered
      and never named** — asserted at two channels and at six.
- [x] 7.3 The method is stated in words beside the value, **from the measurement's own recorded factor
      and filter** rather than constants repeated in the surface — a file measured at 4× is described as
      4×, and an identity this surface does not recognise is shown as itself instead of borrowing the
      known one's words. No coefficients, no taps, no window. **No standard is claimed** and a sweep
      pins that: this filter was designed to recorded parameters and validated against analytic truth
      and an independent meter, not built from BS.1770 Annex 2's own coefficients (ADR-0019 §6). A file
      with no audio frames reuses the existing sentence exactly, rather than gaining a second voice for
      the same state.
- [x] 7.4 The sweep runs over **every** string this section can produce, aimed at the value most likely
      to attract a verdict — a reconstruction at +3.52 dBTP — and covers the named vocabulary plus
      *overs*, *clipping*, *warning*, *better*, *worse*, *fake* and *transcode*. A separate test pins
      that **nothing is compared against the sample peak**: no delta, no "exceeds", no "higher than",
      because the surface that put them side by side would be inviting a conclusion neither type
      supports. Colour carries no meaning — the value above full scale is announced with the same name
      and weight as any other, and only a genuine failure to measure reads at full weight.
      **Four negative controls, each reverted in full:** the unit switched to dBFS broke ten tests; a
      file with no frames reading `0.00 dBTP` broke the absence tests; a "Clipping detected" phrase added
      to the copy broke the sweep; and clamping values above full scale before formatting broke the
      unclamped-value tests.

## 8. True peak versus clipped samples — the independence, proven

- [x] 8.1 **Case A**, the one this metric exists for: a sine of amplitude 1.2 sampled an eighth of a
      cycle off its crest stores every sample at **0.8485** and reconstructs to **1.1999**. Zero clipped
      samples and **+1.58 dBTP**, both truthful at the same moment — a surface that inferred either from
      the other would have to call this file clipped when it holds no clipped sample, or below full
      scale when its waveform is not. Measured through the production shared read, with both values
      shown side by side and no word joining them.
- [x] 8.2 **Case B**: a 997 Hz tone at amplitude 1.2 stores **13 857** samples at or beyond full scale
      and reconstructs to **1.2004**. Both facts reported, neither concluded from the other, and each
      asserted equal to what its own accumulator produces from the same audio with the other never
      constructed. Coexistence is not causation, and nothing here says it is.
- [x] 8.3 **Case C**: the same generator at amplitude 0.5 — sample peak **0.5000**, zero clipped, true
      peak **0.5002**, shown as an ordinary **-6.02 dBTP** with no special wording. It is what stops case
      A from being explained by the fixture generator rather than by the signal.
      **Two further cases are kept apart deliberately**, because collapsing them would lose the
      distinction both domain types exist to preserve: *measured silence* reports a real zero from both
      and floors at **-120.00 dBTP**, while *no frames at all* leaves the true peak with no maximum to
      report — and the clipped count keeps its defined **0** in both, because counting nothing genuinely
      yields none.
- [x] 8.4 **By search**: no line of code in either metric's accumulator, model, generation or
      presentation mentions the other. Every hit for the other's name is a documentation comment, each
      one inspected; `clippingThreshold` is read at exactly one place, the stored-sample counter; no
      warning, no `if truePeak > 1`, and no comparison of a true peak against full scale exists
      anywhere. **By test**: each result equals the same accumulator run alone, value for value — proof
      by consequence, since Swift cannot be asked to demonstrate that a type lacks a member.
      **By sweep**: no string in either section calls a positive true peak clipping, and the sweep
      matches single words whole rather than as substrings, because "overs" is jargon for a clipped
      sample *and* sits inside the innocent "oversampling" the method line legitimately contains.
      **Three negative controls, each reverted in full:** deriving the clipped count from a true peak
      above full scale broke case A and the non-derivation test; reporting the sample peak as the true
      peak broke cases A and B; adding "Inter-sample clipping detected." to the row broke both sweeps.
      This implements **ADR-0019**, which reports the value and refuses the flag, narrowing ADR-0006's
      "flagged when true peak > 0" sentence rather than contradicting it — the flag is an inference and
      belongs to `findings`, with evidence and confidence, which does not exist yet.

## 9. Export

- [x] 9.1 `measurements.truePeak` ships as a sibling of `signalLevels`: `overall` as a **number or an
      explicit `null`** (not an object — there is one number here), `channels[]` carrying each channel's
      frame count beside its value under the same rule, and `method` **inside** `truePeak` with the
      factor and the filter identifier read from the measurement's own record rather than from the
      accumulator's constants. **Linear on the wire, dBTP only on screen** — pinned by a test that
      exports 1.0, 0.5 and 1.2 as themselves and sweeps the bytes for `dBTP`, `dBFS` and `-6.02`.
      `schemaVersion` stays **1**. The filter travels as an identity, never a recipe: no taps, window,
      cutoff or coefficients, and no `bs1770`/`ebu`/`r128`/`compliant` token anywhere.
- [x] 9.2 Isolation holds in every direction. A report without a true peak is **byte-identical** to
      before, with and without signal levels beside it; `measurements` is still omitted entirely when
      neither measurement exists; adding a true peak changes **not one byte** of the `signalLevels`
      object or of any envelope field. Both keys are independently optional, so all four combinations
      are representable and none is `null`. Lifecycle never reaches the wire: `loading`, `unavailable`,
      `failed` and `cancelled` all collapse to `nil` in the view before the export layer sees them.
      **Five negative controls, each reverted in full:** dBTP on the wire broke four tests including the
      end-to-end one; a zero-frame channel exported as `0` broke the null tests; a DSP key in
      `technicalProperties` broke that guard; `"truePeak": null` for an absent measurement broke the
      omission test; and a hardcoded method broke the test that ties it to the measurement.
      **The end-to-end path is proved separately**, because this project has already been caught by
      unit tests passing while the real wiring was broken: a real file is decoded, measured through the
      shared read, translated by the composition root and exported, and the number in the document is
      asserted to be the measured one.
- [x] 9.3 `docs/json-schema-v1.md` gains a `measurements.truePeak` section in the same table form:
      every field with its type and null rule, the linear unit stated explicitly, `method`'s placement
      and why it is not hoisted, the identity-not-recipe rule, the absence of any conformance claim, a
      worked example, and the tests that pin each of them. The `measurements` preamble now states that
      its children are independently optional. Nothing about `signalLevels` was reworded.

## 10. Gates, validation and closure

- [x] 10.1 All six green over the final tree: `./Scripts/check-boundaries.sh`,
      `swift build -Xswiftc -warnings-as-errors`, `swift test` (run twice, no flake),
      `OPENSPEC_TELEMETRY=0 openspec validate --all --strict`, the Xcode `AudioInspector` Debug build,
      and `git diff --check`.
- [x] 10.2 **Passed** (`docs/manual-validation-mvp.md`). Launched by executable path from the freshly
      built binary, never `open` — the process this project has been caught by before is still alive and
      still unkillable, and launching by path is immune to it. The fixture is **analytic rather than
      chosen**: a tone shifted an eighth of a cycle so every stored sample lands at `amplitude/√2`,
      because whether a real master crosses full scale between samples is an accident of that master.
      Seen together on screen: *Peak sample* **−1.43 dBFS**, *Clipped samples* **0**, *True peak*
      **+1.58 dBTP** with its per-channel breakdown and its method line — the case this measurement
      exists for, observed rather than argued, with no warning, colour, badge or diagnosis attached.
      The exported document carries `1.1999318599700928` **linearly** where the screen shows `+1.58`,
      with `method` intact, `schemaVersion` 1 and no path. Reproducibility was checked in a stronger
      form than a second export: the exported value is **bit-identical** to an independent run of the
      same pipeline in another process. **VoiceOver was not exercised** and none is claimed — the known
      traversal gap is inherited, not introduced.
- [ ] 10.3 **Three of four done.** **ADR-0019 is `Accepted`**, promoted on its own two conditions and
      nothing else: the oracle agreement demonstrated **against the production path** — a new gate drives
      the real decoder and the shared read, not the accumulator in isolation — at **0.0005 dB** against
      FFmpeg 8.1.2 where the pinned tolerance is 0.05 dB, and the manual validation above. Its
      `Promotion` section records the evidence and the four things it does **not** cover, including the
      192 kHz exclusion and the standing refusal to claim BS.1770 conformance. The spike package
      `Spike/validate-true-peak/` is **deleted**, its own criterion having been met (ADR Accepted, and
      the slice's tests covering what it observed); the durable report in `docs/spikes/` stays. Nothing
      imports it and no build references it. `CURRENT.md` is updated. **`openspec archive` runs after
      the merge**, so this task stays open until then rather than being marked on three quarters of its
      content.

## 11. Deferred, and named so it is not quietly dropped

- [ ] 11.1 **LUFS (M/S/I) and LRA** — governed by the same ADR-0006, placed by the roadmap in Phase 3,
      and a change of their own. Not designed here.
- [ ] 11.2 **Crest factor** — free once peak and RMS exist, deferred for the reason
      `add-computed-technical-properties` `design.md` §12 recorded: alone, outside the loudness suite's
      context, it invites the out-of-context reading the methodology document warns against.
- [ ] 11.3 **An inter-sample-clipping flag or finding** — ADR-0006 names one; interpretation in this
      project carries evidence, alternatives and confidence, which is the schema's still-unused
      `findings` object and a capability of its own. Scoped out here by ADR-0019, not dropped.
- [ ] 11.4 **An analysis-engine-version field** in the domain and on the wire — cross-cutting, tied by
      ADR-0006 to *stored* results, and there is no store yet (ADR-0004, Phase 2).
- [x] 11.5 **Decode deduplication across the operations — done, and this change is what consumed it.**
      Opened by 5.3's stop rule, it was answered by `add-shared-pcm-read` (merged, archived, **ADR-0020**
      `Accepted`), and group 6 then wired true peak as the third consumer of that one read. An
      inspection performs **two** sample reads — the waveform's own and the shared one — so this is no
      longer deferred work and is marked rather than left claiming a debt that no longer exists. The
      waveform's own migration remains genuinely open, and it is tracked where it belongs:
      `add-shared-pcm-read`'s own deferred section, not here.
- [ ] 11.6 **Significant max frequency** — unchanged from where `add-computed-technical-properties` left
      it: it needs its own noise-floor/persistence methodology, and is not part of this slice.
