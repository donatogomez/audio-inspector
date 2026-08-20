# Tasks — two-file measurement comparison

**Nothing below is implemented.** This change is design only so far: ADR-0024 records the decisions,
`design.md` the shape, and the delta spec the behaviour. Group 1 is blocking by design — the comparison
semantics are settled before a comparator exists, on the order `add-two-file-technical-comparison` used
and for the same reason.

**A note on what this change inherits.** `add-two-file-technical-comparison` is still open at 52/58 and
**ADR-0017 is still `Proposed`**, blocked on the VoiceOver traversal gap it shares with ADR-0015. This
change extends that surface and inherits that gap. It does not fix it, does not worsen it, and must not
be promoted by claiming it.

## 1. Semantics — decide them before writing a comparator

- [ ] 1.1 Confirm against production code that the second file's four measurements are computed and
      discarded today, and that the waveform and spectrogram are too. Record the two lines that discard
      them, so the "cost is already paid" claim is evidence rather than assertion.
- [ ] 1.2 Decide the comparability gate per metric, from the **domain identities** and never from a
      displayed string. ADR-0024 §4 is the decision; this task is the test matrix that pins it.
- [ ] 1.3 **Demonstrate the loudness weighting equivalence rather than assuming it.** The rule admits
      one specific pair of weightings because an end-to-end rate-invariance test reads the same signal
      identically at every rate. Cite that test; if it does not cover the pair, the rule narrows to
      exact method equality and 1.2's table changes with it.
- [ ] 1.4 Fix the bandwidth cell rule — `|f₁ − f₂| < (r₁ + r₂)/2` — and pin **both** sides of it,
      including the same-bin case, the exactly-one-bin-apart case and a two-different-grids case.
- [ ] 1.5 Decide where a difference is published. ADR-0024 §6 says LU only; the task is to state the
      unit argument in the tests so a later change cannot add a dB "difference" that is a ratio.
- [ ] 1.6 **Promotion criteria for ADR-0024**, written before implementation: the comparison against
      production code reusing the existing measurements, the bandwidth rule demonstrated on both sides,
      and a person looking at the surface. Not before, and never on partial evidence.

## 2. The domain types

- [ ] 2.1 `MeasurementComparison` in `AudioInspectorDomain`, built **only** from two
      `ReportMeasurements`, with the memberwise initialiser suppressed exactly as `FileComparison` does.
- [ ] 2.2 Four per-metric comparison types. **Not one generic type** — the four differ in gate, in
      channels, in difference and in classification, and one parameterised rule would be four rules
      wearing one name.
- [ ] 2.3 Reuse ADR-0017's structural gap vocabulary for "one side had nothing", rather than a second
      spelling of the same idea. Widen `ReportMeasurements`' documentation: it is the settled-measurement
      bundle, and export is one of its two consumers rather than its definition.
- [ ] 2.4 Purity: synchronous, total, deterministic, no `throws`, no Foundation, no `URL`, no framework,
      no I/O. Domain tests only.
- [ ] 2.5 **No aggregate of any kind** — no score, similarity, confidence, count of differences or
      `allSame` — and a test that the type exposes none.

## 3. Flow

- [ ] 3.1 Stop discarding the compared file's analyses; collapse `…Outcome` to settled optionals in
      `FeatureImport`, and the primary file's `…State` the same way. No lifecycle reaches the domain.
- [ ] 3.2 Publish the comparison **twice** — technical when the report arrives, measurements when they
      settle — rather than holding back a complete technical answer. Pin the order.
- [ ] 3.3 **Stale atomicity**: the measurement bundle belongs to the same operation as the report beside
      it, asserted with deliberately distinguishable values on both sides, reusing the existing
      handshake. No sleeps, no polling, no `Task.yield()`.
- [ ] 3.4 Cancellation stays neutral: dismissing the picker is not a statement about either file.

## 4. Cost

- [ ] 4.1 Prove **one decoder and one sample read** for the compared file, with the four measurements
      present — the existing decode-count gate extended to the comparison path.
- [ ] 4.2 Show what is retained: four small value types per side, no PCM, no spectrogram, no waveform.
- [ ] 4.3 Negative control: a second read for the comparison must fail 4.1.

## 5. Correctness, on real files through production

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
