# Tasks — two-file measurement comparison

**Groups 1 to 6 are complete; nothing is exported.** The semantics are settled, the domain comparator
exists, the flow publishes it, the ten fixture pairs run through production against real files, and the
sub-section is on screen beneath the technical rows. ADR-0024 stays `Proposed` — its third promotion
criterion is *a person looking at the surface*, and the surface has existed for one commit. The battery
that validation runs against is prepared in this change's `README.md`. Group 1 was blocking by design — the comparison
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
- [x] 5.1 The ten fixture pairs of `design.md` §7, each discriminating something a simpler rule would
      get wrong.
      **Done, and every value came out of a file.** `MeasurementComparisonPairsTests` writes each side,
      decodes it with `AVFoundationAudioDecoder`, folds it through the six shared consumers and
      collapses it with `FeatureImport`'s own `settledMeasurements`; nothing in the suite constructs a
      measurement. Two fixtures had to be *measured* before they were fixed: pair 3 raises the loudness
      with a second comb interleaved between the first's components, because a loud low tone raises each
      window's own peak — which the significance threshold is relative to — and moved the reading two
      bins; pair 4 needed no gain matching at all, a band 30 dB down clearing the threshold while
      contributing a part in a thousand of the energy, so the fixture states its own equivalence instead
      of inheriting it from a measurement.
- [x] 5.2 Pairs 8 and 9 specifically: a naive frequency-equality rule must fail them.
      **Done, on readings production produced.** 88.2 kHz and 96 kHz put one 16 kHz edge at 16 101.09 Hz
      on a 22.97 Hz grid and 16 101.56 Hz on a 23.44 Hz one — 0.47 Hz apart against a 23.20 Hz boundary,
      `indistinguishable` with **unequal** centres. And two edges one bin apart land 23.4375 Hz apart
      against a 23.4375 Hz boundary: the boundary itself, reachable from production, `separated` because
      the inequality is strict. Compared by equality of hertz, pair 8 fails; classified with `<=`, pair 9
      does.
- [x] 5.3 Pair 7 specifically: a naive method-equality rule must fail it.
      **Done.** 44.1 kHz against 48 kHz on the same signal: the weightings are read from what actually
      ran — `itu_r_bs1770_5_48k_prototype_rediscretised_v1` against `itu_r_bs1770_5_tables_1_2_48k` —
      and the test fails if they ever coincide, so it cannot go quietly vacuous. Emptying the allow-list
      breaks it.
- [x] 5.4 Negative controls against production, each applied and reverted: bandwidth compared by
      equality; the cell rule using one side's resolution for both; the loudness gate widened to ignore
      the algorithm; channels compared across differing counts; a difference published for true peak.
      **Done — twelve controls, applied and reverted one at a time, and three of them are findings.**
      Bandwidth by equality fails pair 8; bandwidth never separating fails pairs 4 and 9; channels
      intersected fails pair 6; and true peak grows a difference only as a *stored* field —
      `Mirror` does not see computed properties, so the structural control covers the shape a difference
      would have to take and not a derivation someone writes beside it. Seven more bite the same way:
      dropping the compared file's bundle, emptying the weighting allow-list, a second shared read, an
      inverted difference, an absence becoming `same(0)`, and a superseded result being allowed to land.
      **Two do not reach production, and are classified rather than faked.** The loudness gate ignoring
      the algorithm changes nothing observable, because production runs one algorithm; it stays pinned in
      the domain suite. The cell rule using one side's resolution alone needs two readings whose
      separation falls in a sub-hertz window the real grids do not produce — and applying it found the
      domain suite catching only one of the two directions, so `theCellRule` gained the symmetric row and
      now catches both.

## 6. Presentation

- [x] 6.1 One sub-section beneath the technical rows, in the report's own metric order.
      **Done.** `MeasurementComparisonSection` sits between the eight technical rows and the context
      block, in the report's own order — levels, true peak, loudness, bandwidth — not reordered by
      importance and specifically not with loudness first because it is the row carrying a difference.
      The technical table is untouched: folding both into one would put a fifth column on eight rows
      that have no use for one. Until **both** files settle, the sub-section says what is happening
      rather than rendering an empty table, because the rows above it are already complete.
- [x] 6.2 Bandwidth's outcome words are about the **grid** — `Indistinguishable at these resolutions` /
      `Separated` — not `Same` / `Different`.
      **Done**, and they are cases of their own in `MeasurementOutcomeDisplay` rather than a relabelling
      of `same`/`different`, so no later edit can collapse them back. Each side's analysis resolution is
      on screen beneath its reading — the outcome refers to *these* resolutions, and a reader has to be
      able to see what they are — labelled with the report's own name for it and never as a `±`.
- [x] 6.3 The difference column exists on the loudness row and nowhere else.
      **Done**, and swept rather than exampled: over every comparison shape, no row but integrated
      loudness carries a `difference` or announces one. The unit is **LU**, never LUFS — subtracting two
      levels cancels the reference — and `HumanFormat.loudnessDifference` is the only formatter that can
      produce one, so true peak and the levels have nothing to reach for.
- [x] 6.4 `incomparable` says **why** structurally, on ADR-0017 §5's precedent — a reader must be able
      to tell "the methods differ" from "the file had no value".
      **Done.** The four gaps produce four distinct sentences, asserted distinct rather than assumed:
      each missing side is named, and `methodsDiffer` says the numbers are not on the same scale. **None
      of them says anything failed**, because nothing did — the flow ran and both files were inspected.
      `methodsDiffer` is unreachable from production (group 5's own finding), so it is validated here and
      deliberately not in the manual battery.
- [x] 6.5 Forbidden-vocabulary sweep over every string, extending the existing one with: master,
      remaster, transcode, upsample, lossy, compressed, dynamics, louder, quieter, hotter, better,
      worse, original, derived, generation, quality.
      **Done**, over every string reachable from a comparison in every shape one can take, plus the
      indirect-inference phrases *appears to be*, *probably*, *indicates that*, *points to*. **It needs
      no exemption**, unlike the technical subtitle: this sub-section's disclaimer denies the inference
      without naming it, so the blunt scan covers the copy too. A second sweep pins that no domain
      identity reaches the reader — this surface describes no method, so the rule is no slug at all and
      there is no fallback that could go stale.
- [x] 6.6 Nothing varies with the sign of the loudness difference — no colour, badge, icon or weight.
      **Done.** `+4.0 LU` and `-4.0 LU` produce rows identical in every field but the number, and the one
      styling hook the model exposes — `isSecondary` — tracks *"this cell is an explanation"* and nothing
      else, so `Same` and `Different` are styled alike and every outcome is distinguishable by its text
      alone.
- [x] 6.7 Accessibility: the structural half only. The traversal gap is ADR-0015's and stays open.
      **Done, and only that half.** Each row is one element announcing the measurement, both files'
      values, the outcome and the difference where there is one; an absent side announces the absence
      rather than falling silent, since a blank is indistinguishable from a zero to a reader who cannot
      see the row. The traversal gap ADR-0015 and ADR-0017 share is untouched and stays open.

**One thing the design did not anticipate, found by running real files.** Two DC offsets around 10⁻¹⁴
both print as `0.0000` beside the word `Different`, and two bandwidth readings one bin apart both print
as `16.1 kHz` beside `Separated` — because `linearOffset` shows what `Float` honestly carries and
`programmeBandwidth` shows no digit finer than a bin (ADR-0023). Left alone either row reads as a defect.
The answer is a line saying the display rounds them together, **never another digit**: it states the
relationship between the display and the measurement and says nothing about how large the difference is,
which is exactly the digit the limit exists to withhold.

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
