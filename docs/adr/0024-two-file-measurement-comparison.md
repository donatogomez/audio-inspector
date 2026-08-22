# ADR-0024: Comparing measurements between two files, and why only one of them carries a difference

- **Status**: **Accepted** (2026-08-22). Promoted on the three conditions this record set for itself and
  on nothing else: the comparison exists **against production code** and reuses the second file's
  already-computed measurements — one decoder and one sample read per file, counted through the real
  decoder — rather than recomputing anything; the resolution-aware bandwidth rule is demonstrated on
  production readings sitting on **both** sides of it, the exact boundary included; and the surface was
  **validated by a person looking at it**, on a build postdating the surviving-value fix. The evidence,
  what class each piece of it belongs to, and what it does **not** cover, is in **Promotion** below.
- **Date**: 2026-08-20
- **Deciders**: Project maintainer
- **Related**: **ADR-0017** (two-file technical comparison — this record *extends its vocabulary to a
  second kind of fact and must not weaken it*; **referenced, never edited**), ADR-0008 (availability and
  certainty), ADR-0018/**ADR-0019** (true peak), **ADR-0022** (integrated loudness),
  **ADR-0023** (programme bandwidth), ADR-0009, `docs/analysis-methodology.md`, change
  `add-two-file-measurement-comparison`

## Context

The A/B comparison compares `TechnicalProperties`: container, duration, rate, channels, bit depth,
codec, three bitrates. Those are **read from the file's metadata**.

Everything derived from the file's *samples* travels beside the report, not inside it — signal level
metrics, true peak, integrated loudness, programme bandwidth — and the comparison discards all of it.
That is not an oversight; it is written into the code twice, once where the progressive update is
filtered to the report alone and once where `case let .inspected(report, _)` drops the analyses. It was
correct when it was written: ADR-0017 §9 deferred an evidence-level comparison because *"none of the
metrics it would compare exist yet."*

**All four now exist**, each self-describing and each already produced for the second file by the same
one shared PCM read. The condition that deferred this has expired, and what is left is a decision about
*semantics*, not about capability.

The temptation this record exists to refuse is specific. A collector holding two copies of an album
wants to know which to keep. Four measurements side by side look like they answer that. They do not, and
every step from "these differ" to "this one is a lossy transcode" is an inference with a threshold — the
Findings capability's work, not this one's.

## Decision

### 1. Measurement comparison inherits ADR-0017 §1 unchanged

A measurement comparison SHALL state whether two measured facts are the same, different, or not
comparable, and SHALL NOT state, imply, rank, order or score which file is better, more authentic,
higher quality, less compressed, more dynamic, or worth keeping. ADR-0017's constraint is on the
**types**, and it is inherited here as a constraint on these types.

### 2. It is a **sibling** of `FileComparison`, never an extension of it

`FileComparison` is derived from two **reports** and cannot be assembled — that is its whole integrity
argument. Measurements do not live in a report and never will (ADR-0018), so folding them in would mean
either widening its initialiser to accept values it cannot derive, or teaching the domain that a report
implies measurements. Both weaken it.

So: a separate pure value, `MeasurementComparison`, built from two settled measurement bundles. A
surface may present the two together; the domain keeps them apart.

### 3. Its input is settled values, never lifecycle

The comparator takes two `ReportMeasurements` — the container introduced by
`add-significant-bandwidth-measurement`, holding four optionals where `nil` means *nothing to compare*.
Loading, absent, failed and cancelled are collapsed to `nil` by the feature **before** the domain sees
them, exactly as the export path already does it. The comparison therefore has no error case, nothing
to await, and no way to confuse *"this measurement failed on this run"* with *"these two files differ."*

**And an outcome that compared nothing still carries what each side had** — added after the surface
existed, because leaving it out was a defect rather than a simplification. The first shape of
`MeasurementGap` carried the reason alone, so a pair where the first file measured −24.9 LUFS and the
second measured nothing arrived on screen with **no number on either side**: a row about a file that has
a loudness printed *"No value"* under it, which is false of that file however true it is of the other.

The alternative was to send both `ReportMeasurements` along beside the comparison so a formatter could
look the number up. **That is refused**, and the refusal is the same one §2 makes: it would put two
values and one outcome on screen from two different places, free to belong to two different operations,
which is exactly the atomicity this change's stale handling exists to protect. The comparison is
self-sufficient, so the value travels inside it.

Each case carries exactly what exists and nothing more — `secondMissing` a first, `firstMissing` a
second, `neitherPresent` none — so a gap naming a missing side while carrying a value for it is
unrepresentable rather than merely untested. `methodsDiffer` is the one exception and the only case with
optional payloads: it is a statement about the two **methodologies** and says nothing about presence, so
whatever it carries cannot contradict it, and both numbers survive it. This adds no lifecycle, no error
case and no second source; it only stops the domain from discarding a fact it was handed.

### 4. Two comparabilities, and method identity decides one of them

A pair is comparable when both sides carry a value **and** the two were produced by methods whose
numbers mean the same thing. The second half is read from the domain's own identities, never from a
displayed string:

| metric | identity | compatible when | incomparable when |
| --- | --- | --- | --- |
| signal level metrics | *none — a direct reduction over stored samples* | always, when both present | never on method grounds |
| true peak | `TruePeakMethod{oversamplingFactor, filter}` | both fields equal | either differs |
| integrated loudness | `LoudnessMethod{algorithm, weighting}` | `algorithm` equal **and** the weighting pair is one this project has demonstrated equivalent | algorithm differs, or an undemonstrated weighting pair |
| programme bandwidth | `SignificantBandwidthMethod{identifier, …}` | `identifier` equal | identifier differs |

**Loudness is the one place where an identity may differ and the numbers still compare, and it is
allowed only because it was measured.** The published 48 kHz tables and the rediscretised prototype are
two different constructions, and `LoudnessMeasurement` says so plainly — the identity names the method
rather than the goal, *"because two different constructions could both claim to match a response."*
What licenses comparing across them is not that argument but the end-to-end rate-invariance test, which
reads the same signal identically at every supported rate. Since that is evidence about a **specific
pair** of weightings, the rule is written as an explicit pair allow-list rather than as *"ignore the
weighting"*: a third weighting added later is `incomparable` until someone demonstrates it, instead of
being silently admitted.

Refusing this would be the wrong kind of caution. The commonest real comparison a collector makes is
44.1 kHz against 48 or 96, which is exactly the case the two weightings exist to serve; declaring it
incomparable would make the feature answer nothing in the situation it was built for.

**True peak takes the opposite ruling for the opposite reason.** An oversampling factor is not a
provenance detail, it materially changes the estimate, and no equivalence between two factors has been
measured. Both fields must match.

**Measured against production, none of these refusals is reachable today** — evidence added after the
comparator existed, and it does not change this decision. The same signal read at 44.1, 48, 88.2, 96 and
192 kHz, in mono and stereo, produces **one** true peak method, **one** bandwidth identity, **one**
loudness algorithm and exactly the two weightings the allow-list admits, so every pair of files this
product can currently produce compares. That makes the three refusals above statements about methods
this project might later add rather than about files a user has, and it is why they stay pinned in the
domain suite — which can construct measurements production cannot — rather than in a fixture pair that
would have to fake one. `MeasurementComparisonProductionReachTests` asserts the identities that actually
ran, so the day a second oversampling factor, a second bandwidth identifier or a third weighting appears,
the pair is **decided** rather than discovered inside a comparison.

### 5. Programme bandwidth is compared **on its own grid**, and the rule is stated in full

Comparing two bandwidth readings by numeric equality would be wrong in both directions: two readings in
the *same* bin can differ in hertz, and two readings a bin apart are genuinely distinguished. The
reading is a bin centre and `resolution` is the bin width, so each reading names an observable cell:

    cell(f, r) = [ f − r/2 , f + r/2 ]

Two readings are **indistinguishable at their own resolutions** exactly when their cells overlap:

    | f₁ − f₂ |  <  ( r₁ + r₂ ) / 2

and **separated** otherwise. The rule is symmetric, uses only published quantities, invents no
tolerance, and holds when the two files have different grids — which they do whenever their sample rates
differ, the window being fixed in time.

**This is not an uncertainty interval, and the wording matters.** ADR-0023 refuses to publish a bound on
where the true extent lies, and this does not publish one either: a cell is what the analysis could
*resolve*, not where the answer *might be*. The reading is also biased one way — upward, by the window's
leakage — so a symmetric interval would be wrong in shape as well as in kind. What the rule states is a
fact about the instrument's grid, and the two outcomes are named for the instrument (`indistinguishable`,
`separated`) rather than for the files (`same`, `different`).

Adjacent bins on one grid are `separated`: Δ = r is not < r. The same bin is `indistinguishable`. Both
are the intended readings.

**One consequence surfaced only when the surface existed, and it is recorded here because the answer was
a decision rather than a detail.** Two readings a single bin apart are `separated` — and they *display
identically*, because `HumanFormat.programmeBandwidth` shows no digit finer than a bin, which is
ADR-0023's rule and is right. The same collision happens on DC offset, where two values around 10⁻¹⁴ both
print as `0.0000` beside the word `Different`. Read alone, either row looks like a defect.

The tempting fix is another digit, and it is the wrong one: it would claim a precision the measurement
does not have, on exactly the metric this record spends §5 refusing to over-state. **So the surface adds
a sentence instead** — that the two round to the same figure, and that the analysis nevertheless placed
them in different bins. It states the relationship between the display and the measurement, and
deliberately not the size of the difference, which is the digit the rounding exists to withhold.

### 6. Same / different is used **only where a quantum is published**, and `difference` **only where the unit is a difference**

Two continuous measurements are almost never bit-identical, so a `same`/`different` split over them
would report floating-point noise as a finding. And ADR-0017 §3 removed delta, ratio and direction from
the property comparison deliberately. Neither rule is discarded here; both are applied to a different
kind of quantity, and the answer comes from the **units**, not from taste:

- **Programme bandwidth** is classified — `indistinguishable` / `separated` — because the method
  publishes its own quantum. It carries **no hertz difference**: printing "+50 Hz" against a 94 Hz grid
  would assert a precision the grid does not have.
- **Integrated loudness** carries a **difference, in LU**. It is the only one that does: the domain
  already stores a logarithmic quantity, so `second − first` is a plain subtraction with no conversion,
  and the result is a standard named unit which *is* a difference. Nothing about the sign is
  interpreted, coloured or worded.
- **True peak and signal levels carry no difference.** Their domain values are **linear** amplitudes.
  The difference a reader would want is a decibel one, which is a **ratio** of the stored values — the
  thing ADR-0017 §3 names explicitly. Both values are shown, in their own unit; the reader is not
  prevented from subtracting, and the type does not do it for them.
- **Exact equality is still reported where it happens**, for every metric, because two identical files
  genuinely produce identical measurements and saying so costs nothing.

### 7. Channels are compared by **index**, and a differing count is not a failure

Signal levels, true peak and programme bandwidth are per channel. Channels are compared **by index and
by index alone** — the pipeline reads channel counts and never labels, so nothing here says *left* or
*right*, and no layout is inferred (ADR-0023, ADR-0019).

When the two files carry different channel counts, the **overall** figures still compare and the
per-channel list reports the mismatch rather than the intersection. Comparing the first two channels of
a stereo file against the first two of a 5.1 file would silently assert that index 0 means the same
thing in both, which is exactly the layout claim the pipeline refuses to make.

### 8. What this record excludes, and why the exclusions are decisions

- **Every conclusion about provenance or quality.** Same master, remaster, transcode, upsample, lossy
  source, dynamic-range judgement, "which is better". These are the Findings capability's, they need
  evidence, alternatives and a confidence level (`docs/analysis-methodology.md`), and this record
  provides no field in which any of them could be written.
- **Export.** ADR-0017 §9 settled it and nothing here reopens it: `schemaVersion` 1 describes **one**
  file, no second `inspectedFile` will ever be added, and a comparison document is a kind of its own
  decided in its own record.
- **Waveform and spectrogram comparison.** Still `add-two-file-visual-comparison`'s, unchanged.
- **Alignment, gain matching, residual, correlation.** ADR-0017 §9's evidence comparison. This record
  compares scalars that already exist; it performs no signal processing of any kind and starts no read.
- **Aggregates.** No score, no similarity, no count of differences, no `allSame`. ADR-0017's reasoning
  applies verbatim: *"every comparable measurement agreed"* and *"the two files are the same"* are
  different statements, and one bit cannot hold both.

## Promotion — what was demonstrated, and what it does not cover

Recorded when this moved from `Proposed` to `Accepted`, on `add-two-file-measurement-comparison`'s
groups 5, 6 and 8. Three conditions, each read literally rather than by summary, and each labelled with
the kind of evidence that settled it.

**1. The comparison against production code, reusing what was already measured — automated.** Comparing
a second file was already paying for its four measurements and throwing them away, in two places the
code named deliberately. What promotes this is not that claim but its inversion:
`ComparisonMeasurementsReachTheComparisonTests` drives the real coordinator and the real
`AVFoundationAudioDecoder` over a written file and counts **one decoder and one decode call** for the
compared file, with the four measurements present and reaching the comparison. Driven end to end over
two real files, `MeasurementComparisonProductionReachTests` counts two and two — one per file, and not
one more — and asserts the flow publishes exactly `MeasurementComparison(first:second:)` over the two
settled bundles. A negative control adding a second shared pass fails the read count directly. **The
compute cost of this change is zero; what it adds is retention** of four small value types per side.

**2. The cell rule on both sides, from readings production produced — automated.** The rule is
`|f₁ − f₂| < (r₁ + r₂)/2`, and both sides of it are reached by real files rather than by constructed
measurements. 88.2 kHz and 96 kHz put one 16 kHz edge at 16 101.09 Hz on a 22.97 Hz grid and
16 101.56 Hz on a 23.44 Hz one — **centres 0.47 Hz apart against a 23.20 Hz boundary, and therefore
`indistinguishable` while being unequal**, which is exactly what a rule comparing hertz for equality
would get wrong. Two edges one bin apart land 23.4375 Hz apart against a 23.4375 Hz boundary: **the
boundary itself, reachable from production**, and `separated`, because the inequality is strict. Four
negative controls bite — equality of hertz, a `<=` boundary, one side's resolution used for both, and
never separating. `MeasurementComparisonPairsTests`.

**3. The surface, validated by a person — manual, and the observation is the operator's own.** On
2026-08-22 a person ran the seven-pair battery against the real application on a build postdating the
surviving-value fix, and reported what `docs/manual-validation-mvp.md` records verbatim. **This session
did not see the app**: Screen Recording and Accessibility are refused to it, two attempts are recorded
above that date, and no headless render or source reading stands in for this condition.

What was seen: a 6 dB gain reading `+6.0 LU` on the loudness row **and nowhere else**; the same content
at two rates comparing across two K-weighting constructions with no identifier on screen; two grids
reading `Indistinguishable at these resolutions` and not `Same`; two edges one bin apart reading
`Separated at these resolutions` with the bins note, **intelligible although both displayed values read
16.1 kHz** — the one point in this surface that only a person could settle; a missing loudness showing
the other file's −24.9 LUFS beside `No value`, and its mirror showing the figure follow the file rather
than the column; and a channel-count mismatch keeping the overall figures while refusing to compare an
index. The operator reported **no language ranking the two files, nothing inviting an inference about a
master, a remaster, a transcode or a source, no outcome carried by colour, and no blocking defect**.

### What this promotion does not cover, and is not claimed to

- **It establishes facts, and no more.** Nothing here says whether two files hold the same master,
  whether one is a remaster, a transcode, an upsample or a lossy source, which has more dynamic range,
  which is of higher quality, or which is worth keeping. Those need evidence, alternatives and a
  confidence level, and are the Findings capability's. This is a producer of facts for it, and the type
  provides no field in which such a conclusion could be written.
- **`incomparable(.methodsDiffer)` was not observed by anyone, and cannot be.** Measured across five
  rates in mono and stereo, production produces one true peak method, one bandwidth identity and one
  loudness algorithm carrying exactly the two allow-listed weightings, so **no pair of real files can
  reach it** (`MeasurementComparisonProductionReachTests`). It is pinned in the domain and presentation
  suites, and the battery names the exclusion rather than faking it with a public setting added so a
  screenshot could be taken. The day a second factor, identifier or third weighting appears, that test
  fails and the new pair is decided rather than discovered inside a comparison.
- **The manual pass is one observation, not a regression test**, on one machine. Light, dark and window
  resizing were **not** reported — ADR-0019's pass covered them and this one, like ADR-0023's, is
  narrower. DC offset, clipped samples and the block titles were not individually reported, and no
  word-by-word read of every string was claimed; the vocabulary sweep in
  `MeasurementComparisonPresentationTests` covers every string the sub-section can render, which is
  exhaustive where a by-eye pass is sampled.
- **No VoiceOver coverage, and the traversal gap is unchanged.** It belongs to ADR-0015 and ADR-0017,
  this change adds a sub-section to the same scrolling area every other analysis lives in, and it
  inherits the gap rather than fixing or worsening it. **ADR-0017 is not promoted by this record and is
  not touched by it** — that ADR's own condition is about the technical comparison's surface, and
  nothing here discharges it.
- **One cosmetic defect stands, reported and not fixed.** The channel-mismatch note repeats verbatim in
  three blocks. The operator classified it as redundant but non-blocking, and it was left alone rather
  than turned into production work inside a validation pass.
- **The exported document is untouched and was not read by hand**, because there is nothing new in it:
  a comparison document is a kind of its own and is deferred by §8 and ADR-0017 §9.

## Consequences

### Positive
- The second file's measurements stop being computed and thrown away. The cost is **already paid** —
  the same `SourceInspectionAction`, the same single shared PCM read — so this retains four small value
  types and starts nothing.
- The comparison finally answers the question a collector actually opens it for at the level it can be
  answered honestly: *did the loudness change, did the peak change, did the bandwidth change, did the
  levels change* — without answering *why*.
- Four self-describing measurements make their own compatibility decidable. Nothing here needs a
  tolerance constant, and there is nowhere to put one.

### Negative / costs
- **One more surface that looks like a verdict and is not.** Loudness side by side is the single most
  judgement-inviting pair in the product, which is why §6 gives it a difference and no adjective.
- **`incomparable` will be common and will look like a defect.** Two files at different rates compare
  their loudness (§4) but a true peak measured at a different oversampling factor does not, and a reader
  who does not know why will read it as a bug. The surface has to say the reason structurally, as
  ADR-0017 §5 already requires.
- **The bandwidth rule needs its own explanation on screen.** "Indistinguishable at these resolutions"
  is not a phrase a reader arrives with.
- **It inherits ADR-0017's open accessibility gap.** The technical comparison's own surface is still
  blocked on the VoiceOver traversal problem shared with ADR-0015, and adding rows to that same surface
  neither fixes nor worsens it.

### Neutral
- No new port, no new read, no export change, no `schemaVersion` change, and no new dependency.
- `FileComparison`, `PropertyComparison` and ADR-0017 are untouched.
