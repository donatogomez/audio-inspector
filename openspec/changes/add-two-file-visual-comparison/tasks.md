# Implementation Tasks

**Nothing is implemented.** Groups run in order: 1–3 build the contract and the lifecycle, 4–5 the
geometry, 6–7 the surface, 8–9 the evidence, 10 the two human checks ADR-0025's promotion depends on,
11 closure.

Boundaries no task may cross: no new PCM read and no recomputation of either artefact; `WaveformEnvelope`,
`Spectrogram`, `PCMStreamDescription`, `ReportMeasurements`, `MeasurementComparison`, `FileComparison`,
`InspectionReport`, the property reader and the JSON exporter are **not touched**; no visual artefact
enters `ReportMeasurements` or the export; `AVFoundation`/`AudioToolbox`/`Process` stay in
`AudioInspectorMedia` and Accelerate in `AudioInspectorAnalysis`; no `@unchecked Sendable`, no
`DispatchQueue`, no lock. The original files are never modified.

**Every task marked as a negative control must be demonstrated to fail** when the property it guards is
removed, and the removal reverted in full. A control that has never been seen to fail is a comment.

## 1. Contracts — the settled shapes, before any behaviour

- [x] 1.1 A **per-file visual container** in `FeatureImport`: what became of the envelope, what became of
      the spectral model, and the `PCMStreamDescription` the read produced. A sibling of
      `ReportMeasurements`, **never a field of it** (ADR-0025 §3). `Sendable`, `Equatable`, not `Codable`.
      `FileVisuals`, in `Sources/FeatureImport/SettledVisuals.swift`. **It lives here and not beside
      `ReportMeasurements` in the domain**, and the reason is a real difference rather than a filing
      preference: that container is a domain type because the domain consumes it — `MeasurementComparison`
      takes two of them and the export DTO maps from it — and this one has no domain consumer and never
      will, because nothing compares two drawings and nothing serialises one. Not `Codable` and not
      `Comparable`, asserted rather than intended.
- [x] 1.2 A **settled pair** value carrying both files' containers, constructible only from two settled
      sides. `loading` and `cancelled` MUST be unrepresentable in it (ADR-0025 §5 and design §3).
      `PairedVisuals`, with `init?(first:second:)` over two optionals so *"a side that has not settled"*
      is answered by the type rather than by each caller. Neither lifecycle case is representable at all:
      `SettledWaveform` and `SettledSpectrogram` have three cases, and the collapse returns `nil` for the
      other two. It carries **no operation token** — which operation a pair belongs to is answered by
      where the flow stores it (group 3), not by an identifier kept in advance of a need.
- [x] 1.3 Collapse lifecycle to settled **once, in `FeatureImport`**, for both sides, in the seam
      `SettledMeasurements.swift` already established: the first file's `…State` and the compared file's
      `…Outcome`. `cancelled` collapses to *not settled*; `unavailable` and `failed` stay **distinct**.
      `settledVisuals(from:)` on `InspectionPresentation` and on `InspectionAnalyses`, in a file beside
      the measurements' own collapse rather than inside it: the two take opposite halves of the same
      bundle and collapse for **opposite** reasons — a measurement's failure and absence both become
      `nil` because the wire describes measurements and not why one is missing, and a drawing's must not,
      because the paired surface has to say which happened. The stream description is **passed in**,
      because neither source type carries one and it belongs to the read; it is never rebuilt from the
      report's declared properties, which are what the header claims rather than what was decoded.
- [x] 1.4 Assert the type refuses what the spec refuses: no pair from an unsettled side, absence and
      failure not interchangeable, and a zero-column model carried as its own answer rather than as an
      absence.
      `SettledVisualsTests`, 18 tests, plus a fourth refusal the audit found: **an available artefact
      with no stream description is unrepresentable.** A read reports no description exactly when the
      file exposed no usable frame count, and then every analysis is absent — so a drawing whose axis
      cannot be stated is a combination no read produces, and the initialiser fails on it.
      **Three negative controls seen to fail, and reverted:** collapsing `cancelled` to `unavailable`
      (2 issues), collapsing `failed` into `unavailable` (2 issues), and removing the stream-description
      guard (2 issues). Each restoration was verified by checksum against a pristine copy.
- [x] 1.5 Confirm nothing in group 1 adds a field, a case or a conformance to any domain type.
      `Sources/AudioInspectorDomain/` is byte-identical to `main`. `WaveformEnvelope` gained no sample
      rate, `Spectrogram` gained nothing, `ReportMeasurements` gained no field, and no existing type
      moved module. The new types are additive and, at the end of this group, have **no production
      caller at all** — connecting them is group 2's.

## 2. Retention — stop discarding what the second file already produced

- [x] 2.1 Retain the compared file's visual container where `analyses.settledMeasurements` is already
      taken, in `ImportFlowModel.settle(…)`. Nothing else about that method changes.
      `comparedVisuals = analyses.settledVisuals`, on the line after `comparedMeasurements`. The
      technical and measurement halves of that method are byte-for-byte what they were; the one other
      edit is the parameter that carries the previous visuals for the picker-cancel restore, which 2.3
      needs and which mirrors `andMeasurements` exactly.
      **Getting the description there was the real work, and the seam chosen is the one that makes the
      wrong answer unrepresentable.** `AudioDecoding.decode` returns it, `SharedPCMAnalysisGeneration.run`
      held it and dropped it at `SharedPCMAnalysisOutcome`, which had no field for it. It now carries one
      (**no default** — every return path of `run` names it, and forgetting one is a compile error), the
      coordinator passes it into `InspectionAnalyses`, and `InspectionAnalyses.settledVisuals` became a
      **property that reads its own** rather than a function taking one: pairing an artefact with another
      read's description is now unrepresentable at that seam instead of merely unlikely.
      `InspectionAnalyses.stream` **does** carry a default, and the type's own no-default rule is
      answered rather than ignored: that rule exists so an *analysis* cannot be forgotten, this is not
      one, production builds the value in a single place, and a caller that omits it gets **no visual
      bundle at all** rather than a quietly wrong axis — because `FileVisuals` refuses an artefact whose
      stream is unknown. Honouring it literally would have meant rewriting 94 unrelated test call sites
      in a turn scoped to retention.
- [x] 2.2 Take the primary file's side from the state it already holds in `InspectionPresentation`. **It
      is not re-retained** and not copied into the comparison's own storage (ADR-0025 §4).
      **Nothing was added for the first file**, and the prohibition is asserted rather than assumed:
      *"the first file's pictures are untouched, and are not copied anywhere"* compares its
      `WaveformState` and `SpectrogramState` across a settled comparison and checks the retained side is
      the **second** file's, and the production-reach suite does the same over two real files at two
      different rates. Where the first file's own description will come from when the pair is assembled
      is group 3's question; nothing here answers it early.
- [x] 2.3 Confirm the retained value is released by the same three events that already release
      `comparedMeasurements`: a comparison starting, a comparison dismissed, and a new primary inspection
      ending the comparison.
      All three, plus the fourth half of the same lifecycle: the picker-cancel path **restores** the
      previous comparison's visuals exactly as it restores its measurements. Not restoring would leave
      one comparison's measurements beside another's pictures, which is the pairing defect group 3 exists
      to prevent — so mirroring is the conservative reading of *"the same events"*, not an extension of
      them. Four tests, one per event.
      **Cancelled analyses are a separate thing from a cancelled picker**, and both are pinned: a settled
      outcome whose drawings were cancelled retains **nothing** (the group 1 collapse returns `nil`), and
      an *absence* is retained as an absence, because that is a settled answer about the file.
- [x] 2.4 **Negative control — a second read would be caught.** Extend the counting harness
      `ComparisonMeasurementsReachTheComparisonTests` already uses so that a second `decode` call, or a
      second decoder, fails the suite. Demonstrate the failure by adding one temporarily, then revert.
      `ProductionReadCounts` gained `reportedStreams` — every description the decoder actually returned,
      in call order — so *"the retained description is the one the read produced"* is provable against the
      decoder rather than against a number that happens to agree. The new production-reach suite asserts
      **two decoders and two decode calls** for two files, with the pair retained.
      **Seen to fail.** `sharedAnalyses(for:at:)` was made to run the shared pass twice; the suite failed
      with `(counts.decodersMade → 4) == 2` and `(counts.decodeCalls → 4) == 2` — both counters, not one.
      Reverted from a pristine copy, verified by checksum and by grep, and the suite is green again.

## 3. The pair's lifecycle — atomic publication, staleness, cancellation

- [x] 3.1 Publish the pair **only when both sides have settled**, in the shape
      `publishMeasurementComparisonIfBothSettled` already has, and in **one assignment** carrying both
      sides.
      That function became `publishWhateverHasSettled`, the single place either half is published, and it
      assigns `.ready(technical, measurements, visuals)` once. **A side that has not settled is not a side
      with nothing**, and for the drawings that now includes the read's own description: a file whose
      pictures are settled but whose stream is not yet known is **not** settled, because a drawing whose
      extent cannot be stated is not one anything can present. Neither half is ever walked back.
      **Getting the first file's description there was the work.** It died in
      `apply(_:restoringOnCancellation:)`, which built an `InspectionPresentation` and dropped
      `analyses.stream`. `InspectionPresentation` now carries it, taken in **both** branches of that
      method — it arrives with the settled outcome and with nothing else, because the report is published
      before a sample is read — and `InspectionPresentation.settledVisuals` became a **property reading
      its own**, exactly as the compared side's already did. Both sides now travel the same route from a
      decoder to a settled bundle, and neither can be handed the other's description.
- [x] 3.2 Structure the retained per-comparison payload so a visuals bundle **cannot** be paired with
      another operation's measurements or technical comparison — one merged value, or sibling fields
      cleared in lockstep. Whichever is chosen, prove the other combination is unrepresentable rather
      than merely untested.
      **One merged value**, and the argument was already written in the type: `ComparisonState.ready`
      carries the technical and measurement halves in one case *"because they are one answer about one
      pair of files: two states could drift apart, and a stale guard would have to protect both."* The
      pair joins that case as a third payload rather than living in a property of its own. There is
      therefore **no second value for a stale result to land in** — which is what control 3.8 makes
      visible by creating one.
      One further invariant is explicit rather than implied: the publisher refuses unless
      `presentation.report == technical.first`, so a pair can never be built from a primary file the
      comparison was not made against.
- [x] 3.3 **Superseded second file.** B in flight, user chooses C, B lands late: no pair containing B is
      ever published. Reuse `MeasurementComparisonAtomicityTests`'s handshake — a scripted action released
      step by step, **no sleep, no polling, no `Task.yield()`** — and give B and C **deliberately
      distinguishable** drawings so *"entirely C"* is observed rather than inferred from empty fields.
      B is peak 0.20 at 48 kHz, C is peak 0.30 at 96 kHz, and the first file is peak 0.10 at 44.1 kHz —
      three values no two of which can be confused. The test asserts the technical half, **both sides of
      the published pair**, and **the retained source the pair is built from**: the last of those is what
      catches a defect that corrupts the visual lane while leaving the published value looking right.
- [x] 3.4 **Cancelled second inspection** publishes no pair, and no side is shown as absent, failed or
      empty because of it.
      The group 1 collapse returns `nil` for a cancelled artefact, so nothing is retained and
      `PairedVisuals(first:second:)` yields nothing. The technical comparison is untouched: cancelling
      the drawings says nothing about it.
- [x] 3.5 **Dismiss** and **new primary inspection** each clear the pair, and a result already in flight
      cannot land afterwards.
      Both reassign `comparison` wholesale, so the pair goes with it rather than being walked back, and
      both bump the comparison operation first so a result in flight is dropped before it can settle.
      **The intermediate state of a replacement is pinned separately**: B settles and publishes a pair, C
      is then chosen and is still working, and B's pair is gone *while C works* rather than merely being
      replaced once C finishes. A pair on screen beside a loading comparison would describe a file the
      user had already replaced.
- [x] 3.6 **A second file that could not be opened** leaves the comparison's failure exactly as it is
      today and publishes no pair.
      `.preparationFailed` still produces `.failed(message:)` — never a `.ready` — so there is no case a
      pair could be published into.
- [x] 3.7 **Negative control — stale would be caught.** Remove the operation guard and demonstrate that
      3.3 fails; revert.
      **Seen to fail with 4 issues.** With the guard gone, B's late landing reached `settle` and took
      everything: the technical half read `b.wav` instead of `c.wav`, the published pair's second side
      was B's 48 kHz drawing, and so was the retained source. Reverted from a pristine copy, verified by
      checksum and by grep, suite green again.
- [x] 3.8 **Negative control — two sources would be caught.** Build the pair from two independently read
      values in a temporary variant and demonstrate that 3.3 fails; revert.
      The visuals were made to arrive by a second, unguarded path — recorded and published outside the
      guard the rest of the comparison passes through. **Seen to fail with 3 issues**, and the *signature*
      is the point: the technical assertion **passed** while the pair's second side became B's 48 kHz
      drawing. That is exactly the mixture this group exists to prevent — one operation's pictures beside
      another operation's facts — and it is a different failure from 3.7's, where everything became B's.
      Reverted from a pristine copy, verified by checksum and by grep, suite green again.

## 4. Waveform — shared axes, computed as arithmetic and asserted without rendering

- [x] 4.1 Shared time extent = `max` of the two files' `frameCount / sampleRate`, each from **that file's
      own** stream description. One function, outside the view, in the shape `WaveformGeometry` already
      has — *"every property worth guaranteeing here … is arithmetic that needs no rendering at all."*
      `PairedWaveformAxis` in `FeatureAnalysis`, a pure value with no rendering and no envelope. It takes
      two `PCMStreamDescription?` — a **domain** type, which is what lets it live beside
      `WaveformGeometry` at all: `FeatureAnalysis` cannot see `PairedVisuals`, and joining the two is the
      composition root's job (group 6). Seconds are `frameCount / sampleRate` and **never frames alone**:
      the same duration at 44.1 and 48 kHz holds different frame counts, and comparing frames would
      report a difference in time where there is none.
      **Failable, on the two cases that have no axis**: neither file reported a stream, or both reported
      one carrying no audio. A shared extent of zero is refused rather than divided by.
- [x] 4.2 Each side's drawn fraction = `its extent / the shared extent`; the longer file's is exactly `1`.
      Assert the equal-duration case, the second-shorter case and the first-shorter case.
      All three, plus the bounds: no fraction exceeds `1`, one side always reaches exactly `1`, and every
      fraction is finite. **A read that reported no stream gets no lane**, never a lane of zero seconds —
      *no extent was measured* and *this file lasts no time* are different statements, and a file that
      opened holding no audio genuinely is the second.
- [x] 4.3 The existing bucket→band arithmetic is reused **unchanged** inside each side's fraction. A
      resize re-runs geometry and nothing else.
      `laneSize(_:in:)` returns that file's share of the width and the whole height; the caller builds
      the **existing** `WaveformGeometry` against it. Asserted by value: a lane's bands are identical to
      what one file alone gets at that size, and the last bucket's trailing edge is the **lane's** width
      rather than the pair's. `WaveformGeometry` is not modified.
- [x] 4.4 Beyond a file's own extent: **no bar, no baseline, no substituted silent bucket**. Assert that
      the remainder yields no drawn value at all, and that `WaveformBucket.silent` is never introduced
      there.
      The geometry knows only the envelope's own bucket count and returns `nil` past it, so no band lands
      in the remainder and none is invented to fill it. `remainderFraction` names the region as *outside
      this file's audio* and carries no sample, so it cannot be confused with the measured zero
      `WaveformBucket.silent` is. Asserted that the same envelope is byte-identical after being paired
      with a file 100× longer, that its bucket count is unchanged, and that it contains no `.silent`.
      A lane of zero width yields **no geometry at all** rather than something stretched into place.
- [x] 4.5 Amplitude uses the existing fixed range for **both** lanes, with the clamp applied when drawing
      and only then. Assert both lanes are driven by the same range **as values**.
      `amplitudeRange(for:)` is asked per lane and answers `WaveformGeometry.drawnRange` for both — the
      parameter exists so the rule is answered rather than assumed. Asserted as values, and asserted
      through the geometry: the two lanes differ in width and not in height, so six amplitudes land at
      identical heights in both.
- [x] 4.6 **Negative control — per-file normalisation would be caught.** Re-range one lane to its own peak
      temporarily and demonstrate 4.5 fails; revert.
      `amplitudeRange(for: .first)` returned `-0.9 ... 0.9`. **3 issues**, all in 4.5's test, all
      amplitude: the two lanes' ranges differ, and neither matches `drawnRange`. Nothing temporal moved.
- [x] 4.7 **Negative control — a stretched lane would be caught.** Make the shorter file fill the axis
      temporarily and demonstrate 4.2 fails; revert.
      Every lane's `fraction` forced to `1` while `shared` stayed the maximum. **13 issues** across six
      tests, and the signature is what makes it a different defence from 4.6: fractions became `1` where
      they should be `0.5`, `0.625` and `0`, lane widths became the pair's, remainders became `0` — and
      **not one `sharedSeconds` assertion failed.** The shared extent was still right; only the geometry
      derived from it was wrong, which is exactly the defect this control exists for.
      **A third mutation was run**, because *"each side normalised against its own extent"* is a different
      site from either of the above: the shared extent was taken from the first file instead of the
      maximum. Its signature is distinct again — `sharedSeconds` itself wrong (`5.0` for a 10 s pair), and
      **fractions above `1`** (`2.0`, and a maximum of `9.0`), which neither 4.6 nor 4.7 can produce.
      All three reverted from a pristine copy, verified by checksum and by a `MUTATION` grep, suite green.

## 5. Spectrogram — shared time, shared frequency, and the range that is not the floor

- [x] 5.1 Time reuses group 4's shared extent, from the same source, so a waveform lane and a spectrogram
      lane cannot disagree about how long a file is. Assert it.
      `PairedSpectrogramAxes` **composes** `PairedWaveformAxis` rather than copying its formula, and
      fails wherever it fails — so agreement is true **by construction** rather than by convention. The
      cross-test drives four duration pairs through both types and asserts the shared extent, both
      fractions and both durations are the same values. Group 4 is not modified.
- [x] 5.2 Shared frequency extent = `max` of the two Nyquists; each side's vertical fraction =
      `its nyquist / the shared nyquist`. Assert equal rates, 44.1 against 96, and **96 against 44.1** so
      the rule is not order-dependent.
      All three, plus 96 against 192 in both orders and the bounds: no fraction above `1`, the
      higher-rate side exactly `1`, and `sharedNyquist == max(rate) / 2` over four pairs.
      **The Nyquist comes from `PCMStreamDescription` and from nothing else.** `Spectrogram` carries the
      same rate — it is built from that description — but consulting it would tie the *axis* to a
      *drawing*: a file whose model is absent or failed still has a Nyquist, and the shared axis the
      other file is drawn against must survive that. One source for both axes also makes mixing them
      unrepresentable. That the two agree is **verified** by a test rather than assumed.
- [x] 5.3 Above a file's own Nyquist: **no cell**. Assert the region yields no drawn value, and that the
      axis is labelled to the **shared** Nyquist rather than to the lower one.
      `occupiedRect` sits at the **bottom** — 0 Hz is at the bottom, the convention
      `SpectrogramGeometry.verticalBand` already imposes — and `outOfRangeRect` is the strip above it.
      The two never intersect. Handing the occupied rect to the **existing** `SpectrogramGeometry`
      lands every band inside it, and an index past the model's own bands still resolves to `nil`: no
      band is invented to fill the strip. `SpectrogramAxes.frequencyMarks(nyquist:)` is reused unchanged
      and asserted to end at 48 kHz for a 44.1/96 pair — **not** at the lower file's 22.05 kHz.
      **The out-of-range strip spans the file's own time, not the shared width**, because past its last
      frame there is a *different* absence and group 4's remainder already names that one.
- [x] 5.4 The out-of-range region is rendered **distinguishably from the ramp's floor colour**. Assert it
      as a value — the treatment used there is not the colour `SpectrogramColourRamp` produces at the
      floor — rather than by looking at a rendering. `SpectrogramColourRamp` itself is **not modified**.
      `outOfRangeTreatment` is a mid-grey, and the claim is asserted twice. By **value**: it differs from
      `components(for: floorDecibels)` and its relative luminance is more than 0.2 above it, so the
      difference is separable rather than merely non-zero. And **structurally**: it is achromatic, and
      the ramp never is — swept across 241 levels from −120 to +120 dBFS, every colour the ramp produces
      keeps red apart from blue, so an equal-component treatment cannot be any level it can show.
      The final styling is group 6's; what this fixes is that the two facts cannot collide.
      `SpectrogramColourRamp` is byte-identical to `main`.
- [x] 5.5 Both lanes use the same ramp, the same floor and **one** legend describing both. Assert as
      values.
      `energyRange(for:)` and `floorDecibels(for:)` are asked per lane and answer `SpectrogramColourRamp.range`
      and `Spectrogram.floorDecibels` for both — the parameter exists so the rule is answered rather than
      assumed, exactly as group 4's `amplitudeRange(for:)` does. One legend: the swatches and ticks are
      the ramp's own statics, not a lane's, and the same level is the same colour whichever lane asks.
- [x] 5.6 **Negative control — floor and out-of-range colliding would be caught.** Paint the out-of-range
      region with the floor colour temporarily and demonstrate 5.4 fails; revert.
      `outOfRangeTreatment` set to `components(for: floorDecibels)`. **4 issues** across both of 5.4's
      tests: the treatment equalled the floor, its luminance delta fell to exactly `0.0`, it stopped
      being achromatic, and the ramp was found reproducing it. **Nothing geometric moved.**
- [x] 5.7 **Negative control — cropping to the lower Nyquist would be caught.** Set the shared extent to
      `min` temporarily and demonstrate 5.2 and 5.3 fail; revert.
      `sharedNyquist` set to `min`. **14 issues** across seven tests, and the signature is the one this
      control exists for: the shared extent became the **lower** Nyquist (22 050 for a 44.1/96 pair),
      fractions rose **above 1** (`2.17`, `2.0`), and — the point — the axis label dropped to 22 050, so
      **the 96 kHz file's upper range disappeared silently**. Both 5.2 and 5.3 failed, as the task says.
      **A third mutation was run**, because cropping and stretching are different defects at different
      sites: every `frequencyFraction` forced to `1` while `sharedNyquist` stayed the maximum. Distinct
      signature again — **not one `sharedNyquist` assertion failed**, no fraction exceeded 1, and what
      broke was the fractions, the out-of-range fraction falling to `0`, and the occupied rect filling
      the whole height. All three reverted from a pristine copy, verified by checksum and a `MUTATION`
      grep, suite green.
- [x] 5.8 Confirm no raster is built at anything other than the model's own size, and that
      `SpectrogramRaster`'s no-interpolation rule still holds for both lanes.
      Asserted for both lanes, at two different grid sizes: the buffer's width and height are the model's
      own `columnCount` and `bandCount`, and its byte count is exactly `columns × bands × bytesPerPixel`.
      The lane's area is a **drawing** size and never a raster size — asserted to differ from the
      buffer's dimensions — so nothing here resamples. `SpectrogramRaster` is byte-identical to `main`.

## 6. Replacement — the paired drawings stand in for the single ones

- [x] 6.1 With **no settled pair**, the report surface presents the first file's own envelope and spectral
      model exactly as it does today. This is the default, and it covers *not yet*, cancelled, dismissed,
      superseded and *second file failed* without a case for each.
      `RootView.reportVisuals(for:in:)`. One rule really does cover all five, because all five reach the
      composition root as a comparison state carrying **no settled pair** — group 3 already made
      `.ready`'s third payload `nil` until both sides have settled. Asserted over `.none`, `.loading`,
      `.failed` and `.ready(_, _, nil)`, and driven through the real flow for *cancelled before it
      settles* and *a new primary inspection*.
- [x] 6.2 With a **settled pair**, the paired sections are presented and the two single-file sections are
      not.
      Asserted both ways: the paired sections are present, **and** neither single section appears
      anywhere in what the surface presents.
- [x] 6.3 Assert the first file's envelope appears **exactly once** on the surface, and its spectral model
      exactly once — the property the product decision exists for (design §8).
      `ReportVisuals` answers *which sections* as a **collection**, precisely so *how many* is a value a
      test can read — a rendering cannot be asserted, which is why the surface's answer is a value at
      all. One waveform section and one spectral section in either mode.
      **Negative control, seen to fail:** the pair added beneath the first file's own drawing instead of
      standing in. **4 issues** across both suites — `waveformSections.count → 2`, the paired section no
      longer first, the two modes disagreeing, and the restoration suite catching it too. Reverted from a
      pristine copy, verified by checksum and a `MUTATION` grep.
- [x] 6.4 Returning to the single drawings reads the values already held: **no file is read and no
      artefact is produced again**. Assert with the decode counter.
      Two real files through the real coordinator and the real decoder: one decoder and one read each,
      the pair settles, `dismissComparison()`, and the counters are asserted **unchanged** — still two
      and two — with the first file's own drawings back and still `.available`. The counters are live in
      the same test, moving 0 → 1 → 2 before the dismissal.
      **The path structurally cannot read anything**: what comes back is a pure function of state the
      flow already holds, and it has no decoder to call. **Negative control, seen to fail:** dismissal
      made to re-inspect the first file — the suite failed with *"the single drawings did not come
      back"*, because a re-inspection destroys the held report before it can rebuild it. Reverted, and
      `ImportFlowModel` verified byte-identical by checksum.
- [x] 6.5 Assert the property rows, the technical comparison and the measurement comparison are all still
      presented, unchanged, while a pair is on screen.
      `comparisonPresentation(for:)` returns the **same value** with and without a settled pair, so the
      visual mode reads the state rather than rewriting it; and the report handed to the surface — its
      properties, its warnings, its status — is unchanged by building the visuals. Only the two visual
      sections are replaced; `ReportView` renders `propertiesSection` and `ComparisonSection` exactly as
      before.
      **Both derive from one read of the flow's state**, bound once in `reportSurface`, so the pictures
      and the facts beside them can never come from two different reads.
- [x] 6.6 The choice between the two presentations is a **total** mapping with no default case, in the
      shape `RootView`'s existing state mappings have.
      Three total switches and no `default` anywhere: `ComparisonState` → `ReportVisuals` (with
      `.ready(_, _, .none)` and `.ready(_, _, .some)` as separate patterns rather than an `if let` or a
      `??` fallback), and the two settled answers → lanes. **Both visual sections read the same
      `ReportVisuals`**, so a paired waveform beside a single spectrogram is unrepresentable rather than
      merely avoided — asserted over four states.
      A new case in any of these enums is a compile error here, not a silent fall back to one file's
      drawing.

      **Two things this group did that are worth naming.** The paired presentation types and the two
      geometry types were widened to `public`, because the composition root is the only layer that may
      see both a settled pair and the geometry that lays it out — the same reason `WaveformPresentation`
      is public. No behaviour changed. And `comparisonPresentation(for:)` became internal rather than
      private, aligning it with every other mapping beside it, so what the surface is handed can be
      asserted rather than reimplemented in a test.

      **Deferred to group 7, deliberately:** the words beside a paired lane, the legend, and the axis
      labels. The out-of-range strip is drawn in the treatment group 5 fixed; what it *says* is group
      7's, and the presentation already carries the axes it will need.

## 7. Copy — absence, failure, out-of-range, and the words that are not allowed

- [x] 7.1 Per side and per artefact: **absent**, **failed** and — for the spectral model — **too short to
      analyse** are three distinct statements. Reuse the sentences the single-file surfaces already use
      where they fit; do not invent a second vocabulary for the same fact.
      `PairedVisualsCopy` **borrows rather than invents**: a lane's three states are the three the
      single-file surfaces already have sentences for, and those sentences arrive verbatim through
      `WaveformCopy.text(for:)` and `SpectrogramCopy.text(for:)`. What is added is only what a pair needs
      and one file does not — which file a lane is, and what the part of the axis it does not reach means.
      The three statements are asserted distinct on both sides and for both artefacts, and the two
      artefacts' absences are asserted **different from each other**: one sentence for both would lose
      which drawing is missing.
- [x] 7.2 A neutral failure sentence naming no path and no framework, as today.
      The failure's own message, unchanged, and asserted neutral: no `/`, no framework name, no error
      code, on both sides and for both artefacts. A failure is also asserted **never equal** to an
      absence — the collapse the measurements make deliberately is the one this surface may not make.
- [x] 7.3 Words for the two out-of-range regions: *this file has no audio beyond here* and *this file
      cannot represent this range*. They must be **different sentences**, because they are different
      facts, and a person has to be able to tell them apart in group 10.
      *"This file carries no audio beyond here."* and *"This file cannot represent this range."* —
      ADR-0025 §12's own wording for both rows. Asserted different, asserted bound to their own axis
      (the time remainder never speaks about frequency and vice versa), and asserted **absent** when a
      file reaches the whole of its axis. Each is swept against its own forbidden list: the time
      remainder may not be called *silence*, *silent*, *no signal*, *empty* or *missing*; the frequency
      remainder may not be called *floor*, *no energy*, *low energy*, *truncated*, *missing* or
      *unsupported*.
      *(`tasks.md` writes the first as "has no audio"; ADR-0025 §12 writes it "carries no audio". The
      record's wording is used — same fact, and the record is where the row lives.)*
- [x] 7.4 One side's absence or failure never withholds the other side's drawing and never removes the
      shared axis.
      Group 6 pinned this at the presentation level; group 7 pins it in the words. An absent side gets
      its own sentence, the drawn side keeps its drawing and its own detail line, and **neither
      mentions the other** — asserted by checking each lane's label for the other lane's attribution.
      The shared axis lines are the section's and survive either lane's state.
- [x] 7.5 Attribution is **first** and **second**, by position, reusing `ComparisonCopy`'s existing
      wording — never *original*, *copy*, *source* or *derived*.
      `PairedVisualsCopy.attribution(_:)` returns `ComparisonCopy.firstFile` / `.secondFile` — the rule
      that neither file is *original*, *copy*, *source* or *derived* is one rule and lives in one place.
      **The words follow the position, never the content**: the same lane placed on the other side is
      named the other way round and nothing else about what it says changes, asserted over every lane
      state for both artefacts.
- [x] 7.6 **Negative control — forbidden vocabulary fails the suite.** A sweep over **every** string this
      surface can render, in every state, for the terms ADR-0025 §12 forbids. Demonstrate it fails by
      adding one temporarily; revert.
      The denylist is **read from ADR-0025 §12's table** rather than remembered, plus ADR-0017's refused
      attributions: *same, identical, different, separated, similar, indistinguishable, matching, louder,
      quieter, high-frequency, source, original, copy, derived, master, remaster, transcode, upsample,
      quality, better, worse, confidence, reference, candidate*. Matched on **word boundaries**, case
      insensitively.
      **The sweep's scope is this surface and nothing else** — 2 sides × 4 waveform lane states × 2
      answers to *does it reach the whole axis*, the same for 4 spectral lane states, plus both
      attributions and both axis lines: 100+ strings, every one of them reachable from a rendered view.
      A sweep of the repository would fail on the ADR that lists the terms and on the tests that check
      they are absent, so it is not one.
      **Seen to fail:** *"— a lower quality rate."* appended to the frequency remainder, a string the
      surface really renders. **18 issues**, and the sweep named the term: `offences → ["quality"]`,
      once per string carrying it, plus the two assertions on the sentence itself. Reverted from a
      pristine copy, verified by checksum and by a `MUTATION` grep.
- [x] 7.7 Accessibility: each drawing is one element labelled with the artefact and its file; the shared
      extents are available as text; nothing depends on colour alone.
      Each **lane** is one element — not the section, and not one element per bucket or per cell. The
      lane's own `.accessibilityElement(children: .ignore)` folds the drawing's element into it, and the
      label is *attribution, then the drawing's own sentence, then what the unreached part of the axis
      means*. Asserted: every lane's label begins with its file and names its artefact, in every state;
      an absent or failed lane announces **that** rather than a drawing that is not there; and the
      label is **identical for a 1-column grid and a 1 024-column one**, and for 2 buckets and 2 048 —
      which is what *one element per drawing* means in a value a test can read.
      The shared extents are stated in words (`timeAxis`, `frequencyAxis`), and the region above a file's
      Nyquist is **both** drawn in group 5's treatment **and** said in a sentence, so the distinction from
      the ramp's floor never rests on colour alone.
- [x] 7.8 **Differing channel counts produce no statement here.** Two files with different channel counts
      are drawn as they are, and nothing on this surface compares, reconciles or remarks on the counts —
      ADR-0024 §7 already compares them where a per-channel measurement exists.
      Each lane says what its **own** file carries — *combined across 1 channel*, *combined across 2
      channels* — which is the single-file sentence reused and a fact about that file, not a comparison.
      The whole surface is then swept at both channel counts for *not compared per channel*, *channel
      counts*, *channels differ*, *1 and 2 channels*, *channel mismatch* and *differing channel*: none
      appears. `MeasurementComparison`'s own channel note stays where it is and does not leak here.

## 8. Production reach — the pair really is what the inspection produced

- [x] 8.1 Drive the **real** pipeline for two real files: real coordinator, real decoder, real
      accumulators. Assert **one decoder and one decode call per file**, with the pair retained.
      `PairedVisualsProductionReachTests`, over two files that differ in **rate, length and level** —
      44.1 kHz / 1.0 s / 0.01 against 48 kHz / 2.0 s / 0.04 — so a side on the wrong lane anywhere on the
      path is a wrong number rather than a coincidence.
      **One counter per file**, not one for the pair: *one decoder and one read per file* is asserted per
      file rather than inferred from a total two files could share unevenly. The counters cover the whole
      operation — report, measurements, waveform, spectral model and the pair — and are **never reset
      between phases**. The pair is asserted genuinely settled, with all four drawings available, so the
      counts are the cost of a finished comparison rather than of an abandoned one.
- [x] 8.2 Assert each side's envelope and spectral model in the pair are **equal** to the values that
      file's own inspection produced — reuse, not a lookalike.
      Compared against the outcomes **captured at the coordinator's own boundary**, never against an
      artefact rebuilt in the test: `paired.first.waveform == .available(firstAnalyses.waveform's
      envelope)`, and the same for the model and for both sides. The stream descriptions are asserted to
      be those inspections' own, and to carry the right rate and frame count per side.
      **No swap**, asserted in both directions: the two files' envelopes, models and descriptions are
      first asserted **different from each other** — so the fixtures still discriminate — and then each
      lane is asserted to hold its own.
- [x] 8.3 **Negative control — recomputation would be caught.** Rebuild one artefact from a second pass
      temporarily and demonstrate 8.1 or 8.2 fails; revert.
      **A real second pass, not a changed value**: the coordinator was made to rebuild the *spectral
      model* from a second `SharedPCMAnalysisGeneration` run over the same file — a second decoder and a
      second `decode`. **8 issues**, all of them counters: `decodersMade → 2` and `decodeCalls → 2` for
      **each** file against the expected 1, and `→ 4` against the expected 2 in aggregate. Reverted from
      a pristine copy, verified by checksum and by a `MUTATION` grep.
      **A second control was run**, because 8.4's test could in principle pass on values that happened to
      agree: the two sides of the pair were swapped where the flow assembles it. **21 issues across three
      tests** — the reuse test (10), the coherence test (4) and the end-to-end reach test (7, including
      the shorter file's share of the time axis flipping from `0.5` to `1.0`). Reverted the same way.
- [x] 8.4 The pair, the technical comparison and the measurement comparison on screen together all
      describe the same two inspections, over real files.
      Read out of **one** `.ready` value: the technical half is asserted equal to
      `FileComparison(first:second:)` over the two reports those inspections returned; the measurement
      half equal to what the domain builds from the two bundles they settled on; and the visual half to
      carry those same inspections' stream descriptions. The three are then asserted to **agree about
      which file is which** — 44.1 kHz then 48 kHz in the technical rows and in the pair alike — and the
      fixtures are asserted to discriminate for the measurements too, their loudness differing.
- [x] 8.5 Confirm the report is still emitted before any sample is read, unchanged — the ordering the
      existing suites already pin.
      Not *before the other updates* — **before a sample exists**. The decoder is asked, at the moment
      each report arrives, whether it had been called yet, in the shape `SharedPCMDecodeCountTests`
      already uses; asserted `false` for **both** inspections. Each is then asserted to have really read
      its file once, so a report that preceded nothing could not pass, and the pair is asserted to settle
      afterwards: report-first did not cost the drawings.
      **No sleep, no polling, no `Task.yield()`** anywhere in this group — the flow's own calls are
      awaited.

      **No production changed.** Group 8 set out to find a piece of groups 1–7 reachable only through a
      constructor in a test, and found none: the diff is one test file. The end-to-end test walks the
      whole path on the two real files — settled contracts, the retained pair, the time axis at `0.5`
      against `1`, the frequency axis shared at 24 000 with the lower file at `22 050/24 000`, the paired
      sections standing in exactly once, and the two out-of-range sentences appearing on the side that
      earns each and on neither other.

## 9. Cost, boundaries and the export

- [x] 9.1 Measure retained memory with and without a pair. Expected: **≈ 2.02 MiB more** while a pair is
      held (2 MiB model + 16 KiB envelope). Record what was measured rather than what was predicted, and
      state the machine and configuration.
      **Measured, on two instruments, because neither is sufficient alone** (`RetainedCostSupport.swift`
      names the blind spots of each): a walk of the payload buffers the flow really keeps alive,
      deduplicated **by storage address**, which is exact and blind to closure captures; and the
      process's own `phys_footprint`, which sees everything and is process-wide and noisy.
      **Machine and configuration** — Apple M1 Pro, arm64, 32 GiB, macOS 26.3 (25D125), Swift 6.3.3,
      `swift test` (Debug) and `swift test -c release -Xswiftc -enable-testing` (Release). Fixtures are
      production-sized and take their size from `SpectrogramGridMapping` and `WaveformBucketMapping`
      rather than from a literal, so a cap that moves moves the measurement with it. Two states: **S**,
      one file inspected with its own drawings settled and no comparison; **P**, the same plus a settled
      pair.
      **The exact instrument, identical in Debug and Release:** S = 2 113 536 B, P = 4 227 072 B,
      **delta = 2 113 536 B = 2.016 MiB** — the prediction met to the byte, and the whole of it one more
      file's drawings.
      **The process instrument** cannot be read one scenario at a time: measured that way it reports
      **zero**, because a 2 MiB buffer is a large allocation, the allocator caches freed large regions,
      and every run after the first is served from pages already in the footprint. It is therefore a
      **ramp** — five batches of eight, none ever released, warm-up kept rather than freed. Per pair:
      **2.029 MiB** (Debug, this suite alone), **1.805 MiB** (Debug, whole suite in parallel),
      **1.801 MiB** (Release). That spread *is* the variability, and it is reported rather than
      averaged away; the assertion is deliberately loose — it catches *no cost at all* and *twice the
      cost*, and leaves the exact figure to the exact instrument.
      **Copy-on-write is measured, not named.** With a pair on screen a `Spectrogram` is reachable
      **four** times — the first file's own, the retained compared side, and the pair's two sides — from
      **two** distinct buffers. A physical copy of the first file's model would have doubled the delta,
      and did not.
      **A, B and C are not added together anywhere.** The model is this task's; the raster is 9.4's and
      has a different lifetime; the read's temporary memory is 9.2's.
      `PairedVisualsRetainedCostTests`.
      **Corrected in group 11: the process reading is recorded and no longer asserted on.** Group 9 put
      a loose bound on it and saw it hold twice; group 11's final gate run is the third, and it
      **failed** — 0.037 MiB per pair against the 2.027 this reads when the suite runs alone, because
      three of the paired ramp's five batches were served from pages other suites had already churned
      into the process's footprint and the median landed on one of them. The bound was removed rather
      than widened: a threshold tuned to a quiet machine fails on a busy one and proves nothing on a
      quiet one, which is the conclusion 9.2's own reading had already reached and this one should have
      reached with it. **No evidence is lost.** The figure 9.1 asks to be recorded is still measured and
      still printed, and the claim was never this instrument's: the exact instrument gives
      2 113 536 B to the byte, deterministically, and *retained once* is covered from the other side by
      the replacement test and by the `pairHistory` control under 9.3.
- [x] 9.2 Confirm **no PCM is retained** and no accumulator outlives its read.
      Over the **production route** — the real `SourceInspectionCoordinator`, the real
      `SharedPCMAnalysisGeneration`, the real six accumulators. Only the decoder is a double, and only
      so a large stream can exist without a large file: it **generates** each chunk and retains none,
      which the scripted fake, holding an array of chunks, could not do without becoming the thing being
      measured.
      **Structurally**, the finished bundle is walked and the types a retained read would appear as are
      asked for **by name**: no `PCMChunk`, no `Array<Array<Float>>`, and none of the six accumulators,
      the generation or the decoder. The walk is asserted to have reached the drawings, so the absences
      are absences rather than a walk that stopped early.
      **The decisive measurement is a ratio, not a threshold.** Two streams, 15 s and 30 s: twice the
      samples — 5 275 648 B against 10 551 296 B — and **the same retention to the byte**, 2 113 536 B.
      Anything held in proportion to the input would show as a difference, and there is none; what is
      kept is a function of `SpectrogramGridMapping`'s caps and of nothing else.
      **The footprint reading is recorded, not asserted on**, and that is a decision. A quiet run reads
      a 2.1 MiB rise at the last chunk of a 10.06 MiB read; the same window read 6.5 MiB under the full
      suite and 146 MiB in Release beside the 9.1 ramp — other suites' allocations, indistinguishable
      from this one's. A threshold tuned to the quiet number would fail on a busy machine and prove
      nothing on a quiet one.
      **One thing worth reading rather than assuming:** the peak is **not** at the last chunk. The
      spectral model is built by `finish()`, after the samples stop, so the footprint is higher when the
      inspection returns than it was mid-read. That is the drawing being made, not the read being held —
      and the first draft of this task asserted the opposite and was wrong.
      `ReadTemporaryMemoryTests`.
- [x] 9.3 Confirm at most **one** pair is retained, and that a new comparison releases the previous one.
      **One field, one pair**: `PairedVisuals` is reached exactly once from the flow, and the shapes a
      history would take — `Array<PairedVisuals>`, `Dictionary<Int, PairedVisuals>`, `Array<FileVisuals>`
      — are asserted absent rather than assumed never written.
      **B is gone when C arrives**, asserted on values that discriminate: B's model at 96 kHz, C's at
      48 kHz, and the pair on screen carrying C's beside a technical comparison naming `c.wav`. After
      the replacement the graph still holds one pair and four `Spectrogram` values, so B is not
      reachable by any stored path.
      **The state does not grow with use**: three comparisons in a row, and the retained payload after
      the third equals what it was after the first, to the byte. Dismissing gives back exactly
      2 113 536 B — the second file's drawings and nothing else.
      `PairedVisualsRetainedCostTests`.
      **Negative control — seen to fail, added in group 11 and recorded here rather than where it was
      run.** Group 9 closed this task on positive assertions alone, and group 11's audit of ADR-0025
      found that the record's automated list requires *"each must fail when the property is broken,
      demonstrated by a negative control"* — with **bounded retention** on that list. The control was
      therefore run before the record was promoted, not argued away. `ImportFlowModel` was given a
      `pairHistory: [PairedVisuals]` appended on every publication — the plausible leak, a flow keeping
      the previous comparison so a reader could go back to it. **4 tests failed, 9 issues**, and they
      name both halves of the property: *more than one pair retained* —
      `count(of: "PairedVisuals") → 2` against 1, and `Array<PairedVisuals>` newly reachable — and *the
      load grows with use* — `4 227 072 B` after the first comparison against `6 340 608 B` after the
      second, exactly one more file's drawings per comparison made. Reverted from a pristine copy,
      verified by checksum, by a `MUTATION` grep and by a `pairHistory` grep, with the suite green
      again.
- [x] 9.4 Confirm at most **two** spectrogram rasters exist at once — the consequence of group 6's
      replacement, asserted rather than assumed.
      **Not argued from group 6.** The count is read off **every** state the surface can be in: sixteen
      combinations of paired lanes — the three settled answers plus the empty model that is an answer
      and not an absence — and five single-file states. The maximum observed is **2**, and 0 and 1 both
      occur, so `<= 2` is a maximum rather than a statement about a surface that never draws.
      **Counted as rasters, not as lanes**: a lane is counted only when `SpectrogramRaster.buffer(for:)`
      really produces one, which it declines for a model with no cells.
      **The size, measured on the buffer itself**: 1024 × 512 × 4 = **2 097 152 B** per raster,
      4 194 304 B for the maximum of two — identical in Debug and Release.
      **The level this is guaranteed at is stated rather than implied.** `ReportVisuals` is the whole of
      the app's answer to *which drawings are on screen*, and the bound is a bound on **what this
      architecture asks to be drawn**. It is not a claim about SwiftUI's internals: a framework may hold
      a previous frame's image while it diffs, and nothing here can see that or promises otherwise.
      `PairedSpectrogramRasterCostTests`.
- [x] 9.5 **The export is byte-identical** with a pairing on screen and without one, for the same report.
      **Negative control:** make a visual reachable from the export path temporarily and demonstrate the
      suite fails; revert.
      **Through the real path, not the encoder.** The same `JSONReportExporter` the composition root
      builds, inside the real `ReportExportCoordinator`, writing real bytes to a real file and comparing
      what is read back — because the interesting failure is not *the encoder invented a key* but
      *something on the path handed the encoder more than it should have*. The only substitution is the
      destination: an `NSSavePanel` cannot be driven from a test. The clock and the generator are
      injected fixed, as every other export test does. The pair is asserted **settled** before the
      second export, so the claim is about a pair rather than about its absence. A positive control is
      kept permanently: a report that genuinely differs produces different bytes through the same path.
      **The document is pinned too**, because byte identity alone would not catch a leak that happened
      to appear in both exports: the top level is exactly the seven v1 keys, and thirty-one key names a
      drawing could arrive under are asserted absent — over **keys**, never values, since a file may
      legitimately be named `spectrogram.wav`.
      **The control was run and did fail.** The mutation was end-to-end and real: `ReportEnvelopeDTO`
      gained a `spectrogramColumnCount`, `InspectionReportMapper` gained a `FileVisuals` parameter and
      populated it, `ReportExporting`/`JSONReportExporter`/`ReportExportCoordinator` carried it, and
      `AppContainer` wired the **retained pair's second side** into the production export action. The
      field was made non-optional deliberately — a leaked field that is merely omitted when `nil` is a
      control that cannot fail.
      **Five tests in four suites failed, twelve issues**: this task's own top-level key assertion;
      `ExportComparisonIsolationTests` — *"the document carries exactly one inspected file"*, whose key
      set gained `spectrogramColumnCount`; `SpectrogramReportIsolationTests` — *"the exported JSON is
      byte-identical with and without a spectrogram"*, on a forbidden key; `JSONReportExportContractTests
      .partialInspectionMatchesTheCanonicalExample`, on the canonical document; and 9.6's own
      *"no export source names a visual type"*.
      **A first attempt at the control was rejected** rather than kept: changing the port's requirement
      outright broke the test doubles and the suite failed to **build**, which is a weaker result than a
      suite that builds and fails on its assertions. The mutation was reshaped so every existing
      conformance still compiled.
      **Reverted in full**, verified three ways: `git status` clean but for the new test files, a
      `MUTATION` grep returning zero, and SHA-256 checksums of all seven touched sources plus
      `docs/json-schema-v1.md` identical to the pre-mutation checkpoint.
      `PairedVisualsExportIsolationTests`.
- [x] 9.6 `./Scripts/check-boundaries.sh` green; no AVFoundation, no Accelerate and no `URL` in
      `FeatureImport` or `FeatureAnalysis`; no framework type in any port.
      The script is green and stays the gate. It is **not** what closes this task: 9.6 enumerates
      specific restrictions, and a task that names a property is closed by asserting **that** property —
      the lesson of `add-static-spectrogram-visualization` 10.4, which ADR-0025 records. So each is read
      off the sources by name, and a failure says which one broke: no `AVFoundation`/`AVFAudio`/
      `AudioToolbox`/`CoreAudio` and no `Accelerate` import in either feature; no `URL` token in either
      feature's code, comments excluded exactly as the script excludes them; neither feature importing a
      concrete module, nor each other. The **three ports** are read line by line against nineteen
      framework type names. A fourth check was added for 9.5's structural half: **no export source names
      a visual type** — the assertion the negative control tripped first.
      `ArchitectureBoundaryTests`.
- [x] 9.7 **A missing drawing never damages a report.** With either file's artefact absent or failed,
      both reports keep the same properties, warnings and global status they would have otherwise, and no
      inspection warning is emitted for the drawing.
      **Thirty-six cases against one baseline.** Six states per side — available, waveform absent,
      waveform failed, model absent, model failed, and the model with **no columns** that is an answer
      rather than an absence — applied to the first file, the second, and both. Each is compared with
      the same two files' all-available run: properties, warnings and status for **both** reports, plus
      the technical and measurement comparisons. The baseline report carries two warnings and a
      `partial` status, so *unchanged* is asserted over a report that has something to lose.
      **The two reports are built once and reused**, and that is not a convenience:
      `AudioFileReference` carries an ephemeral `id` that is new on every construction, and a helper
      that rebuilt them made every `FileComparison` comparison fail on an identifier that is
      deliberately not part of what a report says. That was found by running it.
      **No warning names a drawing**, asserted twice: the warning set is the inspection's own and no
      more, and no code, field or message contains *waveform*, *envelope*, *spectrogram*, *spectral*,
      *drawing*, *visual* or *raster* — so a future warning code about a waveform would fail this even
      if the count stayed the same.
      **And the absence is represented rather than hidden**, because an intact report bought by quietly
      dropping the pair would be worth nothing: the pair still settles, the missing lane says which of
      the two things happened to it, the artefacts that did arrive are untouched, and a pair whose
      spectral models **both** failed stays in paired mode instead of falling back to a single drawing.
      `VisualAbsenceReportIsolationTests`.
- [x] 9.8 Confirm the diff touches none of: `WaveformEnvelope`, `Spectrogram`, `PCMStreamDescription`,
      `ReportMeasurements`, `MeasurementComparison`, `FileComparison`, `InspectionReport`,
      `SpectrogramColourRamp`, the property reader, the exporter, `schemaVersion` 1.
      Confirmed against the **whole change** — `d27933c` (the merge base) to the working tree, not this
      group's own diff — because that is what the task protects and what the archived precedent
      (`add-drag-and-drop-file-import` 10.2) checked. Fifteen paths, each independently `0` files
      changed: the seven domain types above, `SpectrogramColourRamp`, `AVFoundationAudioFilePropertyReader`,
      the four export sources (`JSONReportExporter`, `InspectionReportMapper`, `ReportJSONDTO`,
      `ReportExporting`), `ReportExportCoordinator` and `docs/json-schema-v1.md`.
      `InspectionReportMapper.schemaVersion` is still `1`, and the export layer is asserted to name none
      of the visual types (9.6) rather than merely to be unmodified.

      **No production changed.** Group 9 is seven test files and this record; the export mutation was a
      negative control and is gone. What the group found was in its own instruments, not in groups 1–8:
      a footprint read one scenario at a time reports zero, a peak assumed at the last chunk is not
      where the peak is, and a report rebuilt per case is not the same report.

## 10. Manual validation — the two properties ADR-0025's promotion turns on

**Only two, and each is binary.** Both are written before the application is opened and are left
unedited afterwards. Neither may be answered with *looks good*, *clear enough* or *easy to understand*;
each asks two questions with a literal yes or no. Record the result in
`docs/manual-validation-mvp.md` as a durable statement, including anything that failed, unsoftened.

- [x] 10.1 **M1 — different durations.** Inspect a file of about 3:30, compare it against one of about
      3:00 (either order), and wait for the paired drawings.
      **Q1.** Does the shorter file's drawing end **before** the right-hand edge of the shared axis, at a
      position consistent with the two durations shown in the property rows above? **yes / no**
      **Q2.** Does the remainder of that lane read as **"this file has no audio here"** rather than as
      silence? **yes / no**
      **PASS** = yes to both. **FAIL** = no to either. A remainder that reads as a quiet passage, a flat
      line or an unfinished drawing is a **no** to Q2.
      **PASS. A person ran this against the real application and reported both answers; they are
      recorded exactly as reported.** This session did not see the surface — nothing below came from a
      test, a headless render or a reading of the source, and no observation is attributed to it.
      **Fixtures**, generated outside the repository so that duration is the only difference: `first` =
      `m1-first-210s-44100.wav`, 210.000 s; `second` = `m1-second-180s-44100.wav`, 180.000 s. Both
      44.1 kHz, mono, 16-bit, from the same generator — the 3:00 file is the first 180 s of the same
      programme. Identical Nyquist, so the frequency axis takes no part.
      **Q1 = yes.** The 3:00 file's drawing ends before the right-hand edge of the shared axis, at a
      position consistent with 180 of 210 seconds.
      **Q2 = yes.** The remainder reads as that file no longer carrying audio there, and not as measured
      silence.
      **What was also on screen** — reported as description, not as a second criterion:
      `This file carries no audio beyond here.`
      **A layout defect was observed during this pass and is recorded rather than smoothed over**: in the
      paired waveform section, text overlaps vertically — around
      `Amplitude over the whole file, combined across 1 channel.` and `Second file`, and later between
      `This file carries no audio beyond here.` and the second lane's amplitude line. **Non-blocking for
      this task**, on the operator's own report that both questions could be answered unambiguously
      **yes** in spite of it. It is neither a wrong edge nor a wrong reading of the remainder, which is
      what M1 asks about. Recorded unsoftened in `docs/manual-validation-mvp.md`; **not fixed here.**
- [x] 10.2 **M2 — different Nyquists.** Compare a 44.1 kHz file against a 96 kHz one (either order) and
      wait for the paired spectral models.
      **Q1.** Does the 44.1 kHz model stop **below** the top of the shared frequency axis? **yes / no**
      **Q2.** Is the region above it distinguishable **by eye** from the floor colour used **inside** the
      drawing? **yes / no**
      **PASS** = yes to both. **FAIL** = no to either. Q2 is the one this check exists for: if the two
      look the same, the surface is saying *measured and very quiet* where it means *cannot represent
      this range*, which is a defect and not a gap.
      **PASS. Reported by the same person, on the same build, in the same session**, and recorded
      exactly as reported.
      **Fixtures**, generated so that the sample rate is the only difference: `first` =
      `m2-first-44100hz-30s.wav`, 44.1 kHz, Nyquist 22 050 Hz; `second` = `m2-second-96000hz-30s.wav`,
      96 kHz, Nyquist 48 000 Hz. Both 30.000 s, mono, 16-bit, one generator — a sweep that stops at
      12 kHz, below both Nyquists, so the ramp's own floor colour is present **inside** both drawings as
      the thing Q2 compares against. Equal duration, so the time axis takes no part.
      **Q1 = yes.** The 44.1 kHz model stops visibly below the top of the shared 48 kHz axis.
      **Q2 = yes.** The region above that file's own Nyquist is distinguishable **by eye** from the floor
      colour used inside the drawing.
      **What was also on screen** — description, not a second criterion:
      `This file cannot represent this range.`
      **Q2 is the property `SpectrogramColourRamp` and `PairedSpectrogramAxes` could only ever assert as
      values.** 5.4 and 5.6 assert that the treatment is not the ramp's floor colour and that it is the
      only achromatic thing on the ramp; that two colours differ as values is not that they are
      distinguishable on a real display to a real person, and that is what was answered here.
- [x] 10.3 Process identity, before either check: terminate every running instance, rebuild, and launch
      the new binary **by its executable path — never `open`** — confirming a fresh window first. The
      precedent for why is in `docs/manual-validation-mvp.md`.
      **Done, in that order, before either check.** Every running `AudioInspector` process was
      terminated and none was left alive; the app was rebuilt from `9f44af09f78f850362af19110a78b4a3d5619d9e`
      with a clean, **isolated** derived-data path — `/tmp/ai-g10-build`, not the shared Xcode one — with
      a clean worktree; and the binary was launched **directly by its executable path**,
      `/tmp/ai-g10-build/Build/Products/Debug/AudioInspector.app/Contents/MacOS/AudioInspector`, never
      through `open`. One `AudioInspector` process was alive during the pass, and it was that one.
      **The fresh, empty import window was confirmed by the person before either check** — the
      confirmation the precedent asks for, and the one part of this task a session cannot make for
      itself.
      **The precedent was not merely cited, it was met a second time.** Between preparing the build and
      the pass, a **different** binary appeared alive — built minutes earlier into the shared Xcode
      derived-data path and carrying `-NSDocumentRevisionsDebugMode YES`, with a different SHA-256 from
      the one prepared. Its commit was never established, and it was **not** the instance either check
      was run against. That is exactly the failure `docs/manual-validation-mvp.md` records from
      2026-08-11 — *"the build under test was not the build that was actually running"* — and it is why
      the isolated derived-data path and the confirmed PID are part of this record rather than a detail.

## 11. Gates and closure

- [x] 11.1 Four gates green — `./Scripts/check-boundaries.sh`,
      `swift build -Xswiftc -warnings-as-errors`, `swift test`,
      `OPENSPEC_TELEMETRY=0 openspec validate --all --strict` — plus the Xcode app build and
      `git diff --check`.
      **All green, on the final tree.** Boundaries respected; the zero-warnings build completes;
      `swift test` **run twice**, as the closure precedent does — **1628 tests in 181 suites**, no
      issues either pass; `openspec validate --all --strict` passes 11 of 11; `xcodebuild -scheme
      AudioInspector -configuration Debug` **BUILD SUCCEEDED**; `git diff --check` clean. The focused
      suites this change owns were run together as well — 102 tests in 12 suites — covering atomicity,
      production reach, both geometries, the surface, export isolation, retention, the raster bound,
      vocabulary and the boundary assertions.
      **One gate genuinely failed on the way, and the fix is recorded rather than hidden.** The first
      full run failed on 9.1's *process* footprint reading — the flaky instrument, not the feature. It
      was demoted from an assertion to a record, with the reason written into the test and into 9.1;
      the two passes above are the tree after that. **No evidence was lost**: the figure is still
      measured and printed, and the claim it briefly carried was always the exact instrument's.
- [x] 11.2 Confirm every negative control in groups 2–9 was **seen to fail** and reverted in full, with
      no residue in the diff.
      **Sixteen controls, every one seen to fail, every one reverted.** Audited against each task's own
      recorded failure rather than against the fact that a control was written — *"a control that has
      never been seen to fail is a comment"*.
      **Group 1 (three, ahead of the range this task names):** `cancelled` collapsed to `unavailable`
      (2 issues); `failed` collapsed to `unavailable` (2 issues); the stream-description guard removed
      (2 issues). **Group 2:** a second shared pass — `decodersMade → 4` and `decodeCalls → 4` against
      2, both counters. **Group 3:** the operation guard removed, so B's late result lands (4 issues,
      the retained source itself wrong); the pair built from two independently read sources (3 issues,
      with the signature the control exists for). **Group 4:** one lane re-ranged to its own peak
      (3 issues); every lane's fraction forced to `1` (13 issues across six tests). **Group 5:** the
      out-of-range treatment painted the ramp's floor colour (4 issues); `sharedNyquist` set to `min`
      (14 issues across seven tests). **Group 6:** the pair added beneath the single drawing instead of
      standing in (4 issues across both suites); dismissal made to re-inspect the first file (the
      single drawings did not come back). **Group 7:** *"— a lower quality rate."* appended to a string
      the surface really renders (18 issues, the sweep naming `offences → ["quality"]`). **Group 8:**
      a real second pass rebuilding the spectral model (8 issues, all counters), plus a voluntary second
      control swapping the pair's two sides (21 issues across three tests). **Group 9:** a visual made
      reachable from the export path (5 tests in 4 suites, 12 issues).
      **One was missing and was run rather than argued away.** ADR-0025's automated list requires a
      control per condition, and **bounded retention** had none — group 9 closed 9.3 on positive
      assertions alone. It was run here, before the record was promoted: a `pairHistory: [PairedVisuals]`
      on the flow, **4 tests failed with 9 issues**, naming both halves of the property. Recorded under
      9.3, where the property lives.
      **No residue.** Every revert was verified from a pristine copy by checksum and by grep; the diff
      against `main` contains no `MUTATION` marker, no `pairHistory`, and none of the mutated shapes.
- [x] 11.3 Decide **ADR-0025**'s status from what was actually demonstrated, against its own three
      promotion conditions and nothing else. Partial evidence does not promote it, and group 10's two
      checks are not optional.
      **Decided: `Accepted` (2026-08-27)**, on the three conditions and on nothing else, with a
      `Promotion` section recording the evidence, the class each piece belongs to, and what it does
      **not** cover — the shape ADR-0024 established five days earlier and ADR-0023 before it.
      **1 — reuse, not recomputation: satisfied**, counted through the real decoder over two real files
      (one decoder and one decode call **per file**, one counter each), with each artefact asserted
      equal to what that inspection produced at the coordinator's own boundary, and two controls seen to
      fail. **2 — unmixable across operations, each direction failing when its guard is removed:
      satisfied**, on one payload with no second value for a stale result to land in, and both guards
      demonstrated. **3 — the two axis properties observed by a person: satisfied**, M1 and M2 both
      yes/yes on 2026-08-27, on a build launched by its executable path with a fresh window confirmed by
      the person; the session that prepared it did not see the surface and nothing stands in for that.
      **The automated list was audited too, not assumed**, and it is what surfaced the missing bounded
      retention control that 11.2 then ran. **The layout defect does not contradict any condition** —
      the ten automated ones are arithmetic, retention, export, colours as values and vocabulary; the
      two manual ones ask about an edge and a region, and an edge and a colour. It is recorded in the
      promotion as a cosmetic defect that stands, reported and not fixed.
      **ADR-0016 and ADR-0017 stay `Proposed`** and are not touched: neither is discharged by anything
      here, and the promotion says so in its own words. **ADR-0024 is untouched.**
- [ ] 11.4 Update `CURRENT.md`, and archive through `openspec archive` **after merge**, without editing
      the promoted specs by hand.
      **Half done, and it stays open because the other half must not happen yet.** `CURRENT.md` is
      refreshed and describes the real state — one thread open and PR-ready, ADR-0025 `Accepted`, the
      cosmetic defect standing, the inherited ADR-0016/ADR-0017 debt untouched, and opening the PR as
      the next step. **`openspec archive` has not been run**, and must not be: the precedent is exact —
      `add-two-file-measurement-comparison` promoted its ADR and refreshed `CURRENT.md` on the branch,
      merged as PR #49, and archived only afterwards, on `main`. This task is marked complete when the
      archive has actually happened.
- [x] 11.5 Record in `add-two-file-technical-comparison` that its group 4 decision — *the second file's
      visualisations are discarded* — is superseded by this change, without editing its historical text.
      **Recorded additively under that change's task 4.6 — 18 insertions, no deletions**, so the
      decision as it was made stands verbatim and the note sits beneath it. What it says: the decision
      was right when it was made and its own clause (c) — *"the next slice needs them"* — is what came
      true; the second file's visualisations are no longer discarded; and **the reversal criterion was
      not met, the opposite happened** — the slice was implemented rather than abandoned, at no
      additional read, so the one-to-two seconds that task priced was never spent twice. Clause (a)
      stands unchanged: no *requested-parts* case was added and none is needed. ADR-0025 §4, not that
      task, is where the retention rule lives.

## 12. Deferred, and named so it is not quietly dropped

- [ ] 12.1 **Evidence comparison** — alignment, gain matching, residual, correlation, spectral difference,
      matching regions. ADR-0017 §9's, and every step is a heuristic with a threshold. What it will need
      is retained by this change; **nothing here authorises it.**
- [ ] 12.2 **Findings** — same master, remaster, transcode, upsample, lossy source, quality, provenance.
      This change is a producer of pictures for a reader, never a small version of that capability.
- [ ] 12.3 **Comparison export** — a document kind of its own. `schemaVersion` 1 describes one file and
      gains nothing here (ADR-0017 §9).
- [ ] 12.4 **Synchronised inspection** — cursors, zoom, scrubbing, linked scrolling. Out by ADR-0025 §11,
      and a synchronised cursor needs an alignment decision that belongs to 12.1.
- [ ] 12.5 **More than two files.** Everything here is stated for a pair, and a third would reopen the
      lifetime decision and the memory figures first.
