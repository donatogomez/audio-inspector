# Tasks — two-file measurement comparison

**Groups 1 and 2 are complete; nothing is wired.** The semantics are settled and the domain comparator
exists, pure and tested. Nothing in the flow, the surface or the export has changed, and the second
file's measurements are still discarded — closing that is group 3. Group 1 was blocking by design — the comparison
semantics are settled before a comparator exists, on the order `add-two-file-technical-comparison` used
and for the same reason.

**A note on what this change inherits.** `add-two-file-technical-comparison` is still open at 52/58 and
**ADR-0017 is still `Proposed`**, blocked on the VoiceOver traversal gap it shares with ADR-0015. This
change extends that surface and inherits that gap. It does not fix it, does not worsen it, and must not
be promoted by claiming it.

## 1. Semantics — decide them before writing a comparator

- [x] 1.1 Confirm against production code that the second file's four measurements are computed and
      discarded today, and that the waveform and spectrogram are too. Record the two lines that discard
      them, so the "cost is already paid" claim is evidence rather than assertion.
      **Done.** `ComparisonDiscardedMeasurementsTests` drives the real coordinator and the real decoder
      over a real file: the compared file gets exactly one decoder and one read, all four measurements
      *and* both visualisations are produced, the comparison is already complete when the report lands,
      and nothing the read produces changes it. The structural half is stated separately rather than
      dressed up as dynamic evidence — that the measurements are *absent* cannot be shown, because
      `FileComparison` has no field they could occupy. Two controls bite: a second decode, and bandwidth
      ceasing to be produced.
- [x] 1.2 Decide the comparability gate per metric, from the **domain identities** and never from a
      displayed string. ADR-0024 §4 is the decision; this task is the test matrix that pins it.
      **Done.** `MeasurementComparisonTests` pins all four gates, including that identical values do
      not rescue an incompatible method. Seven mutations bite.
- [x] 1.3 **Demonstrate the loudness weighting equivalence rather than assuming it.** The rule admits
      one specific pair of weightings because an end-to-end rate-invariance test reads the same signal
      identically at every rate. Cite that test; if it does not cover the pair, the rule narrows to
      exact method equality and 1.2's table changes with it.
      **Done, and the evidence holds.** `LoudnessProductionMatrixTests` reads one signal at 44.1, 48,
      88.2, 96 and 192 kHz through the whole production path and requires the spread within 0.03 LU;
      production selects the published tables at 48 kHz and the rediscretised prototype everywhere else,
      so that test crosses exactly this pair. The rule therefore stayed as designed rather than
      narrowing to exact method equality.
- [x] 1.4 Fix the bandwidth cell rule — `|f₁ − f₂| < (r₁ + r₂)/2` — and pin **both** sides of it,
      including the same-bin case, the exactly-one-bin-apart case and a two-different-grids case.
      **Done.** Eight parameterised cases across the boundary, plus adjacent bins, two different grids
      and an A/B symmetry check. The boundary itself is `separated`; `<=` and exact-frequency equality
      both bite.
- [x] 1.5 Decide where a difference is published. ADR-0024 §6 says LU only; the task is to state the
      unit argument in the tests so a later change cannot add a dB "difference" that is a ratio.
      **Done.** The difference is `second − first` in LU, asserted positive, negative and zero, absent
      on an incompatible method and absent on a missing side. A structural test pins that no other
      metric carries one.
- [x] 1.6 **Promotion criteria for ADR-0024**, written before implementation: the comparison against
      production code reusing the existing measurements, the bandwidth rule demonstrated on both sides,
      and a person looking at the surface. Not before, and never on partial evidence.

## 2. The domain types

      **Done.** They are ADR-0024's `Status`, written before any of this existed.
- [x] 2.1 `MeasurementComparison` in `AudioInspectorDomain`, built **only** from two
      `ReportMeasurements`, with the memberwise initialiser suppressed exactly as `FileComparison` does.
      **Done.** Built only from two `ReportMeasurements`; the declared initialiser suppresses the
      memberwise one.
- [x] 2.2 Four per-metric comparison types. **Not one generic type** — the four differ in gate, in
      channels, in difference and in classification, and one parameterised rule would be four rules
      wearing one name.
      **Done.** `MeasurementValueComparison`, `LoudnessComparison`, `BandwidthReadingComparison` and
      `ChannelComparison`, composed into four named fields.
- [x] 2.3 Reuse ADR-0017's structural gap vocabulary for "one side had nothing", rather than a second
      spelling of the same idea. Widen `ReportMeasurements`' documentation: it is the settled-measurement
      bundle, and export is one of its two consumers rather than its definition.
      **Done.** `MeasurementGap` is `ComparisonGap`'s sibling and not a second spelling of it: it has a
      reason that occurs *while both sides are available* — the methods differ — which `ComparisonGap`'s
      shape makes unrepresentable by construction. `ReportMeasurements` now documents that it has two
      consumers and that export is only the first.
- [x] 2.4 Purity: synchronous, total, deterministic, no `throws`, no Foundation, no `URL`, no framework,
      no I/O. Domain tests only.
      **Done.** No Foundation, no I/O, no `URL`, no framework; boundaries green.
- [x] 2.5 **No aggregate of any kind** — no score, similarity, confidence, count of differences or
      `allSame` — and a test that the type exposes none.
      **Done.** `MeasurementComparisonBoundaryTests` asserts the field set over `Mirror` and sweeps for
      score, similarity, confidence, `allSame`, `isIdentical`, `matches` and the rest.

## 3. Flow
- [x] 3.1 Stop discarding the compared file's analyses; collapse `…Outcome` to settled optionals in
      `FeatureImport`, and the primary file's `…State` the same way. No lifecycle reaches the domain.
      **Done.** `SettledMeasurements` collapses both sides in `FeatureImport`, and returns `nil` for
      *unfinished* as distinct from *nothing to compare* — the compare action is offered the moment a
      report is on screen, so the primary can still be measuring when the compared file has finished.
- [x] 3.2 Publish the comparison **twice** — technical when the report arrives, measurements when they
      settle — rather than holding back a complete technical answer. Pin the order.
      **Done, and the order is pinned.** The technical comparison is published from the progressive
      report; the measurement comparison waits for whichever side settles last and is taken from the
      settled outcome, never assembled from progressive updates.
- [x] 3.3 **Stale atomicity**: the measurement bundle belongs to the same operation as the report beside
      it, asserted with deliberately distinguishable values on both sides, reusing the existing
      handshake. No sleeps, no polling, no `Task.yield()`.
      **Done.** `MeasurementComparisonAtomicityTests` supersedes B with C mid-read and lets B finish
      late, with four deliberately distinguishable measurements per file: the published pair is entirely
      C's, and equals what the domain builds from C's own bundle. No sleeps, no polling, no
      `Task.yield()`.
- [x] 3.4 Cancellation stays neutral: dismissing the picker is not a statement about either file.

## 4. Cost

      **Done.** Cancelling a replacement restores the previous comparison **with the bundle it was
      built from**, so a primary settling afterwards completes that comparison rather than nothing. A
      cancelled analysis is not a settled answer, so no pair is published for it and the technical half
      is untouched.
- [x] 4.1 Prove **one decoder and one sample read** for the compared file, with the four measurements
      present — the existing decode-count gate extended to the comparison path.
      **Done**, by the inverted group-1 suite: one decoder, one decode call, the four measurements
      present, and now reaching the comparison.
- [x] 4.2 Show what is retained: four small value types per side, no PCM, no spectrogram, no waveform.
      **Done, structurally.** Two `ReportMeasurements` and one `MeasurementComparison`: value types of
      `O(channels)`. Neither `PCMChunk`, `WaveformEnvelope` nor `Spectrogram` has a field in any of them,
      so no PCM, spectrum, waveform or spectrogram can be retained.
- [x] 4.3 Negative control: a second read for the comparison must fail 4.1.

## 5. Correctness, on real files through production

      **Done.** A second shared pass in the coordinator fails the read count.
- [ ] 5.1 The ten fixture pairs of `design.md` §7, each discriminating something a simpler rule would
      get wrong.
- [ ] 5.2 Pairs 8 and 9 specifically: a naive frequency-equality rule must fail them.
- [ ] 5.3 Pair 7 specifically: a naive method-equality rule must fail it.
- [ ] 5.4 Negative controls against production, each applied and reverted: bandwidth compared by
      equality; the cell rule using one side's resolution for both; the loudness gate widened to ignore
      the algorithm; channels compared across differing counts; a difference published for true peak.

## 6. Presentation

- [ ] 6.1 One sub-section beneath the technical rows, in the report's own metric order.
- [ ] 6.2 Bandwidth's outcome words are about the **grid** — `Indistinguishable at these resolutions` /
      `Separated` — not `Same` / `Different`.
- [ ] 6.3 The difference column exists on the loudness row and nowhere else.
- [ ] 6.4 `incomparable` says **why** structurally, on ADR-0017 §5's precedent — a reader must be able
      to tell "the methods differ" from "the file had no value".
- [ ] 6.5 Forbidden-vocabulary sweep over every string, extending the existing one with: master,
      remaster, transcode, upsample, lossy, compressed, dynamics, louder, quieter, hotter, better,
      worse, original, derived, generation, quality.
- [ ] 6.6 Nothing varies with the sign of the loudness difference — no colour, badge, icon or weight.
- [ ] 6.7 Accessibility: the structural half only. The traversal gap is ADR-0015's and stays open.

## 7. Deferred, and named so it is not quietly dropped

- [ ] 7.1 **Comparison export** — `schemaVersion` 1 describes one file and gains no second
      `inspectedFile` (ADR-0017 §9). A comparison document is a kind of its own. Not designed here.
- [ ] 7.2 **Visual comparison** — waveforms and spectrograms side by side:
      `add-two-file-visual-comparison`. Not started here.
- [ ] 7.3 **Evidence comparison** — alignment, gain matching, residual, correlation, spectral
      difference. Every step is a heuristic with a threshold. Not started here.
- [ ] 7.4 **Findings** — same master, remaster, transcode, upsample, lossy source, dynamics, quality,
      provenance. **This change is a producer of facts for that capability, never a small version of
      it.** Not started here.

## 8. Gates and closure

- [ ] 8.1 Four gates green plus the Xcode build and `git diff --check`.
- [ ] 8.2 Decide ADR-0024's status from what was actually done, update `CURRENT.md`, and archive through
      `openspec archive` **after merge**.
