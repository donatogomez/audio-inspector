# ADR-0025: Two files' waveforms and spectrograms, side by side — a paired presentation, not a visual comparison

- **Status**: **Proposed.** It stays Proposed until three things are true against production code: the
  compared file's envelope and spectral model are **reused** from the read it already performs — one
  decoder and one decode call per file, counted at the boundary that opens it — and never recomputed;
  the pair is demonstrated to be **unmixable across operations**, each direction failing when its guard
  is removed; and the two axis properties a test cannot answer are **observed by a person** (see
  **Promotion conditions**). Partial evidence does not promote it.
- **Date**: 2026-08-25
- **Deciders**: Project maintainer
- **Related**: **ADR-0024** (measurement comparison — this record reuses its atomicity and its
  factuality, and *must not weaken either*; **referenced, never edited**), **ADR-0017** (comparison
  semantics, still `Proposed` — *referenced, never edited*), **ADR-0016** (the spectrogram model and its
  uncropped axis, still `Proposed`), **ADR-0020**/**ADR-0021** (one PCM read per inspection),
  ADR-0008, ADR-0009, ADR-0023, changes `add-two-file-technical-comparison`,
  `add-static-spectrogram-visualization`, `add-two-file-visual-comparison` (not created)

## Context

The two-file comparison compares metadata (`FileComparison`) and, since ADR-0024, four measurements
(`MeasurementComparison`). It compares no pictures. The second file's waveform and spectrogram **are
produced** — `ComparisonMeasurementsReachTheComparisonTests` asserts both are `.available` on the same
single read that produced its measurements — and then thrown away, at one line:
`ImportFlowModel.settle(…)`, `case let .inspected(report, analyses)`, where `analyses.settledMeasurements`
is kept and the rest of `analyses` goes out of scope. The code says why: *"The visualisations are still
discarded, because `ReportMeasurements` has no field either could occupy."*

That discard was decided deliberately, with a reversal criterion, in `add-two-file-technical-comparison`
group 4: *"the second file runs the same pipeline, unchanged, and its visualisations are discarded"* —
justified partly because *"the next slice needs them. `add-two-file-visual-comparison` will draw exactly
these two models."* **This record is that slice's decision.** Nothing new is computed and nothing is read
twice; what changes is that a value already produced stops being dropped.

The intent inherited from `add-two-file-technical-comparison` task 9.1 is one sentence — *"waveforms and
spectrograms side by side, on the same absolute scale, with compatible axes"* — and ADR-0017 §9 explains
why it was deferred rather than why it is easy: *"Both models already exist and are already on an
absolute, un-normalised scale because the user compares copies."*

**The trap this record exists to refuse is geometric rather than verbal.** Both drawings are already
resolution-independent and map their model onto whatever area they are given:
`WaveformGeometry.horizontalBand` places bucket *i* of *n* at `width · i/n`, and
`SpectrogramGeometry` does the same for columns and bands. Put two of them in two equal lanes and the
layout asserts, with no words at all, that the two files have the same duration and the same spectral
range. For a 3:00 file beside a 3:30 one, and for a 44.1 kHz file beside a 96 kHz one, that assertion is
false — and it is exactly the claim `SpectrogramAxes` already refuses to make for one file: *"The axis is
never cropped. A 96 kHz file that holds nothing above 22 kHz is showing exactly the thing a collector is
looking for."*

A picture can lie by being drawn, without a single word being written. Everything below follows from
that.

## Decision

### 1. This slice **pairs and presents**; it does not compare

The system SHALL retain both files' already-computed visual artefacts and present them together,
attributed to *First file* and *Second file*, on shared absolute axes. It SHALL publish **no outcome
about the two pictures** — no `same`, `different`, `identical`, `similar`, `matching`, no score, no
count, no colour or symbol standing for a verdict.

The pictures are the content. The only words the surface adds are attribution, the axis extents it
actually drew, and the absence sentences each side already has. **A paired presentation needs no
linguistic outcome**, and adding one would be the first inference in a feature whose whole value is that
it makes none.

### 2. Why not `same`/`different`/`incomparable` here, given ADR-0017 established that vocabulary

ADR-0017's Neutral consequence predicts the visual level *"will need the same three-way answer **with
confidence added**"*. That prediction is accepted, and it is precisely the reason the vocabulary is
declined **for this slice**: a confidence level is Findings' machinery
(`docs/analysis-methodology.md`), and any honest statement that two *reduced* pictures are "the same"
needs one. A 2048-bucket min/max envelope and a 1024 × 512 dBFS grid are lossy summaries; two different
files can produce identical ones, and two identical files can produce different ones after a resample.
Saying `same` about them would be the strongest claim on the surface and the least supported.

ADR-0017 is not weakened by this: its vocabulary is left exactly where it is, still governing the
property comparison, and this record adds no competing vocabulary of its own.

### 3. Ownership — a per-file visuals value, sibling to `ReportMeasurements`, never inside it

Visual artefacts SHALL live in **their own per-file container**, a sibling of `ReportMeasurements` and
never a field of it. `SettledMeasurements.swift` already states the rule this obeys: *"A waveform and a
spectrogram are pictures of the samples rather than measurements of them… `ReportMeasurements` has no
field either could occupy, so this is enforced by the type rather than by this comment."* Widening
`ReportMeasurements` would put a picture where the measurement comparison, the export mapping and
ADR-0024's comparator all expect a number.

The container SHALL carry, for one file: what became of its envelope, what became of its spectral model,
and the **`PCMStreamDescription` the read used**. Recommended names, not semantics: `FileVisuals` for one
file, `PairedVisuals` for the pair.

**The stream description is load-bearing, not stored "just in case."** `WaveformEnvelope` is
deliberately poor — it carries `frameCount` and `channelCount` and **no sample rate** — so an envelope
alone cannot state a duration, and two envelopes alone cannot share a time axis. `Spectrogram` carries
`sampleRate` and can. The description resolves that asymmetry from **one** source that the shared read
already holds (`AudioDecoding` returns it, and returns `nil` exactly when the file exposed no usable
frame count, in which case every analysis is absent anyway). Nothing is added to `WaveformEnvelope`, and
no second read, no second decode and no second source of truth is created.

### 4. Lifetime — retained per comparison operation, released with it

The compared file's visuals SHALL be retained for exactly as long as `comparedMeasurements` already is,
by the same events and no others: cleared when a comparison starts, when one is dismissed, and when a new
primary inspection ends the comparison. The primary file's visuals are **not** re-retained — they are
already in `InspectionPresentation` and stay their own.

### 5. Atomicity — one payload, or no payload

The pair SHALL be **one value published in one assignment**, carrying both sides. It SHALL NOT be
assembled by a surface reading one side from the flow's presentation and the other from a retained
bundle. This is ADR-0024 §3's refusal applied unchanged: *"it would put two values and one outcome on
screen from two different places, free to belong to two different operations, which is exactly the
atomicity this change's stale handling exists to protect."*

Concretely, and each one testable:

- the pair exists only when **both** sides have settled, in the shape
  `publishMeasurementComparisonIfBothSettled` already has;
- a **cancelled** side is *not settled* — never an absence — so it yields **no pair**, exactly as
  `SettledValue` already treats a cancelled measurement;
- the retained per-comparison payload SHALL be structured so that a visuals bundle **cannot** be paired
  with another operation's measurements or technical comparison. Whether that is one merged value or
  sibling fields cleared in lockstep is the change's call; the property is not;
- replacing the second file while a pair is in flight, dismissing the comparison, and starting a new
  primary inspection each leave **no** pair built from two operations.

### 6. Absence and failure — words, never an empty picture

Per side, and per artefact, **absence and failure SHALL remain distinguishable**, and neither SHALL be
drawn. No empty envelope, no black grid, no zero-filled array, no floor-coloured rectangle stands in for
a missing picture. The single-file surfaces already keep three statements apart — absent, failed, and
*"too short to analyse as a spectrogram"* — and `SpectrogramCopyTests` exists to keep them apart; the
paired surface inherits that and states the missing side in words beside the drawn one.

An absent side SHALL NOT withhold the present one. One file having no spectrogram is not a reason to
stop showing the other's.

### 7. Scales stay absolute, and are never re-ranged for the pair

Neither lane SHALL be normalised, auto-contrasted, auto-ranged or re-coloured relative to the other or to
itself:

- **Amplitude** — both lanes use the same fixed scale the single-file drawing already uses
  (`WaveformGeometry.drawnRange`, `-1 … +1`), and a value beyond it is limited **when drawn and only
  then**, never written back.
- **Energy** — both lanes use the **same colour ramp, the same floor and the same legend**. The floor is
  `Spectrogram.floorDecibels` (−120), a property of the model; the −120…0 legend is a property of the
  legend. Neither is recomputed per file.

A quiet file SHALL look quiet beside a loud one, and a file whose energy stops early SHALL look like it.
**The surface preserves real differences; it does not remove them to make two pictures easier to lay
out.**

### 8. Time — one shared axis, spanning the **longer** file, and nothing invented in the remainder

Both lanes of a kind SHALL share **one time axis** whose extent is `max` of the two files' own extents,
each taken as `frameCount / sampleRate` from that file's own stream description.

- Each file's drawing occupies exactly `its extent / the shared extent` of the axis, and **ends there**.
- The remainder of the shorter file's lane carries **no bucket and no cell**, and is stated as **outside
  that file's audio** — not as silence. `WaveformBucket.silent` is a *measured* zero; the region past a
  file's last frame was never measured, and drawing the two the same way would invent audio.
- **No stretching**, **no clipping**, **no alignment**, **no correspondence**. Nothing here asserts that
  the two files start at the same moment, and the surface SHALL NOT say or imply that a position in one
  lane is the same position in the other.

Equal extents are the ordinary case — two copies of one track — and produce two full-width drawings with
no remainder, which is the same picture the naive layout would have given. **The rule costs nothing when
the files agree, and refuses to lie when they do not.**

### 9. Frequency — one shared axis to the **higher** Nyquist, with the missing range shown as missing

Both spectrogram lanes SHALL share **one frequency axis** running from 0 Hz to `max` of the two files'
Nyquists.

- Each file's grid occupies exactly `its nyquist / the shared nyquist` of the axis, from 0 Hz upward.
- The region above a file's own Nyquist carries **no cell**, and SHALL be **visually distinguishable
  from the floor colour** used inside the drawing. *"This file cannot represent this range"* and *"this
  file was measured here and is very quiet"* are different facts, and the ramp's darkest colour already
  means the second one.
- **The shared axis is never cropped to the lower Nyquist**, for the reason `SpectrogramAxes` already
  gives for one file: an empty upper range is evidence, and hiding it hides the thing a collector is
  looking for.
- A 44.1 kHz file drawn beside a 96 kHz one is therefore **shorter on the axis**, not rescaled to match.
  Making them look alike is the specific failure this decision exists to prevent.

Time on the spectrogram lanes follows §8 unchanged.

### 10. Channels are not paired

Both models already combine channels — the envelope by min/max across all of them, the spectrogram by
maximum in the frequency domain — and each carries its own `channelCount`. Differing channel counts are
**not** an error, are **not** reconciled, and are **not** compared here: ADR-0024 §7 already compares
channel counts where a per-channel measurement exists, and re-stating it from a picture would be a second
source for a fact the rows above already carry.

### 11. What this record excludes, and why the exclusions are decisions

- **Every mathematical comparison of the two pictures** — difference, residual, correlation, alignment,
  gain matching, spectral difference, matching regions, similarity. That is ADR-0017 §9's *evidence
  comparison*: every step is a heuristic with a threshold, and none of them is authorised here.
- **Interaction.** No cursor, no zoom, no scrubbing, no synchronised navigation. The canonical
  `waveform-visualization` requirement — *"no playback, no zoom, no scrubbing, no selection and no
  cursor"* — is not weakened by putting two drawings on one surface. A synchronised cursor is also an
  alignment claim wearing a UI control.
- **Every conclusion about provenance or quality.** Same master, remaster, transcode, upsample, lossy
  source, better, worse, which to keep. Findings' work; this record provides no field one could be
  written in.
- **Export.** ADR-0017 §9 settled it and nothing here reopens it. Neither `WaveformEnvelope` nor
  `Spectrogram` is `Codable`, by decision (ADR-0009), so the exclusion is enforced by the types.
- **A second PCM read, and any recomputation.** The pair is built from what one read per file already
  produced. Recomputing either artefact for the pair would be a second decode by another name.
- **A third file.** Everything here is stated for a pair.

### 12. The words the surface may use, and the ones it may not

Stated as a table so it can be asserted by a vocabulary sweep rather than remembered, in the shape
`MeasurementComparisonPresentationTests` already uses. *Factual* = read from a value the app holds.
*Derived* = arithmetic on such values, with no threshold. *Inferential* = needs a threshold, a model of
how files are made, or a confidence level.

| Term or claim | Class | Permitted here |
| --- | --- | --- |
| *First file* / *Second file* | factual (position) | **yes** — ADR-0017's attribution, reused verbatim |
| *waveform*, *amplitude envelope* | factual (names the artefact) | **yes** |
| *spectrogram*, *energy in dBFS* | factual (names the artefact) | **yes** |
| the axis extents actually drawn (a duration, a frequency) | derived — `frameCount / sampleRate`, `sampleRate / 2` | **yes**, as the axis's own labels |
| *this file carries no audio beyond here* | factual — past its own frame count | **yes**, and required by §8 |
| *this file cannot represent this range* | factual — above its own Nyquist | **yes**, and required by §9 |
| *same*, *identical* | inferential over a lossy reduction | **no** (§2) |
| *different*, *separated at this resolution* | inferential over a lossy reduction | **no** (§2) |
| *similar*, *indistinguishable at this resolution* | inferential, and needs a confidence level | **no** (§2) |
| *matching*, *matching regions* | inferential — asserts correspondence | **no**; alignment is evidence comparison's |
| *louder* / *quieter* | derived, but not from a picture | **no** — signal levels and loudness already say it, compared, in the rows above |
| *more* / *less high-frequency content* | inferential from a reduced grid | **no**; programme bandwidth is the measured statement, and ADR-0023 keeps it independent of the spectrogram |
| *same source*, *different source*, *master*, *remaster*, *transcode* | inferential | **no** — Findings' (§11) |
| *quality*, *better*, *worse*, *which to keep* | inferential | **no** — refused by ADR-0017 §1 and ADR-0024 §1 |

Two rows are worth stating rather than assuming. *Louder* and *more high-frequency content* are the two
readings a paired picture most invites, and both already have a **measured**, compared answer elsewhere on
the same surface. Repeating them from a drawing would be a second source for a fact the rows above
already carry — ADR-0024 §3's refusal — and a less accurate one.


## Alternatives considered

- **Extend `ReportMeasurements` with the two artefacts.** The smallest diff. Rejected on the type's own
  recorded reason: a picture is not a measurement, it has never appeared under `measurements` on the
  wire, and the container is what ADR-0024's comparator, the export mapping and `SettledMeasurements`
  all agree means *numbers*. Widening it would make the export mapping the place a picture has to be
  explicitly excluded, instead of a place it cannot reach.
- **Retain the whole `InspectionAnalyses` for the compared file** instead of a visuals container. Also
  small, and it would leave everything available for later. Rejected: it retains six outcomes to use
  two, re-introduces `.cancelled` into what a surface reads, duplicates the measurements already held as
  `ReportMeasurements`, and invites a refactor that makes the measurement comparison's atomicity depend
  on the visual one's. Rejected on ownership clarity, not on cost.
- **Two lanes read from two places** — the primary's visuals from `InspectionPresentation`, the second's
  from a retained field. The obvious shape, and the one ADR-0024 §3 already refused for values: the two
  sides would be free to belong to two operations.
- **Each drawing keeps its own axes, side by side.** What the naive layout does. Rejected: it is the
  silent stretch. Two equal lanes make a 3:00 file and a 3:30 file look the same length and a 44.1 kHz
  file and a 96 kHz one look like they cover the same spectrum.
- **Share axes at the `min` of the two extents.** Symmetrical with §8 and §9 and much tidier — every
  drawing full width, no remainder. Rejected: it crops the longer file and hides the higher file's upper
  range, which is exactly what `SpectrogramAxes` refuses for one file. Cropping to make a layout tidy is
  the same act as cropping to make a verdict easy.
- **Stretch the shorter file to the shared extent.** Rejected outright: it deforms time and would make a
  tempo difference invisible while making everything else look aligned.
- **Give `WaveformEnvelope` a sample rate.** It would make the shared time axis fall out for free.
  Rejected: the type is deliberately poor, its poverty is what makes it resolution-independent, and the
  rate is available from a description the read already produces. The pairing needs the rate; the
  envelope does not.
- **A `VisualComparison` value with an outcome.** Rejected by §1 and §2, and by its own name: it would
  publish a judgement about two lossy summaries, and ADR-0017 already says that judgement needs a
  confidence level this slice has no way to produce.
- **Synchronised cursors or zoom.** Rejected by §11, and deferred to nothing: it needs an alignment
  decision first, which is evidence comparison's.

## Consequences

### Positive

- **Nothing is computed.** The feature's whole cost is not dropping a value, and one read per file stays
  one read per file — the property ADR-0020 and ADR-0021 exist to hold.
- The layout cannot silently equate two files, because the shared-axis rule is arithmetic and can be
  asserted without rendering anything, exactly as `WaveformGeometry` and `SpectrogramGeometry` already
  are.
- **No verdict has anywhere to live.** With no outcome type, no score and no ordering, the honesty
  constraint is structural rather than conventional — the same argument ADR-0017 makes for itself.
- Evidence comparison is left a clean starting point without being designed: what it will need is two
  reductions **and the stream description they came from**, which is precisely what is retained. No API
  is added beyond that.

### Negative / costs

- **About 2.02 MiB more retained** while a comparison is open — the second file's `Spectrogram.values`
  (1024 × 512 floats = exactly 2 MiB) plus its envelope (2048 buckets × 8 bytes = 16 KiB). Both files'
  models together are ~4.03 MiB.
- **Rasters are the larger number, and they are not this record's invention.** Drawing a spectrogram
  builds an RGBA8 image at the model's own size — 1024 × 512 × 4 = 2 MiB — held while it is on screen.
  A second drawn spectrogram adds another. On-screen worst case roughly doubles, ~4 MiB of models plus
  ~4 MiB of rasters against ~4 MiB total today.
- **The pair waits for both sides.** A comparison whose second file has settled still shows no pair until
  the primary file's own read finishes. That is the measurement comparison's existing behaviour and it is
  inherited deliberately, but it means the visual section can appear later than the rows above it.
- **The shared axis makes the single-file drawing and the paired drawing different pictures of the same
  file.** A 44.1 kHz file occupies the full height alone and less than half of it beside a 96 kHz file.
  That is correct and it will surprise someone.
- **A large empty region is a bad thing to show a person**, and §9 spends a colour distinction on making
  it legible. Two files of very different durations or rates will produce a lot of nothing.

### Neutral

- No new port, no adapter, no framework, no I/O, no dependency. The pairing is a pure function of values
  the app already produces, exactly as `FileComparison` and `MeasurementComparison` are.
- No module boundary moves. `WaveformEnvelope`, `Spectrogram`, `PCMStreamDescription`,
  `ReportMeasurements`, `InspectionReport` and the exporter are unchanged.
- `schemaVersion` 1 is untouched, and stays untouched by construction.

## Relationship to ADR-0016 — **NOT REQUIRED**, and the dependency is partial and named

ADR-0016 is `Proposed` and its manual validation (group 10, tasks 10.1, 10.2, 10.5 and 10.6) is
**deferred by product decision**. That deferral is not a pass and is not read as one here.

**ADR-0016 being `Accepted` is not an architectural precondition for this record.** What this record uses
from it is the `Spectrogram` **model** and two rules — the absolute, never-per-file-normalised scale, and
the axis that is never cropped — all of which are in production, asserted by tests, and *reinforced*
rather than relied upon here. What remains unvalidated in ADR-0016 is how its **surface reads to a
person**, which is a property of the single-file drawing this record does not change.

Two honest qualifications:

- ADR-0016 decision 15 — *"both consumers use the seam, but as independent operations with independent
  cancellation"* — is **not** what ships and is **not** used here. ADR-0020 revisited its mechanism under
  the condition ADR-0016 wrote for itself, and ADR-0021 completed it: one read per inspection, cancelled
  as one. This record depends on **ADR-0020 and ADR-0021**, both `Accepted`, and on ADR-0016 only for the
  model.
- The `spectrogram-visualization` capability is **not canonical yet** — its spec lives in the delta of
  the still-active `add-static-spectrogram-visualization`. A change implementing this record therefore
  **adds** its own capability rather than modifying that one, and does not wait on an archive.

If ADR-0016's deferred validation ever fails, what is at risk is the spectrogram's *presentation*, and
this record's §7 and §9 would inherit the same defect the single-file drawing had. That is a shared
exposure, stated rather than discovered, and it is not a reason to hold this design.

## Relationship to ADR-0017 — referenced, unchanged, and given no evidence either way

ADR-0017 stays `Proposed` and is **not edited**. Its `First file` / `Second file` attribution is reused
verbatim, including its rule that neither is *original*, *copy*, *source* or *derived*. Its
`same`/`different`/`incomparable` vocabulary is **not** reused, for the reason in §2, and is not weakened
by the omission.

**This record supplies no evidence toward ADR-0017's promotion.** Its unmet condition is a person
validating the technical comparison's surface, and it carries the VoiceOver traversal gap it shares with
ADR-0015. A paired drawing added below that surface neither answers that question nor changes it.

## Relationship to ADR-0020 / ADR-0021 — depends on, and must not spend

Both are `Accepted` and both are load-bearing here: one read per inspection is what makes the second
file's pictures free, and the shared composition is where they come from. This record **spends nothing**
of that saving — no new read, no second decode, no recomputation — and its first promotion condition is
the decode counter staying where ADR-0021 left it.

## Relationship to ADR-0024 — specializes it, and inherits its rules unchanged

This record **specializes** ADR-0024's shape to a second kind of artefact. Inherited and not weakened:

- **Factuality.** No ranking, no score, no aggregate, no provenance (§1, §11).
- **Absence is never zero.** §6 for a missing picture, §8 and §9 for a region of an axis a file does not
  span — the same rule the measurement comparison applies to a missing number.
- **Atomicity, and the self-sufficient payload.** §5 is ADR-0024 §3's refusal applied to pictures.
- **Sibling, never extension.** §3 is ADR-0024 §2's argument applied to `ReportMeasurements`.
- **Reuse what the read already produced.** ADR-0024's first promotion condition, restated as this
  record's first.

It does **not** inherit ADR-0024 §6's `same`/`different`, because that rule turns on *"where a quantum is
published"* and neither picture publishes one.

## Promotion conditions

Recorded here rather than left to be argued about later. **Automated** and **manual** are separated
because they answer different questions, and the manual ones name the exact property a person looks at —
the lesson of `add-static-spectrogram-visualization` 10.4, where a check written as one property was run
against a stronger one.

**Automated — each must fail when the property is broken, demonstrated by a negative control.**

1. **One read per file, still.** The compared file's inspection makes one decoder and one decode call,
   counted at the boundary that opens it, with the visuals retained.
2. **Reuse, not recomputation.** The envelope and the model in the pair are equal to the values that
   file's own single read produced.
3. **Atomicity, in every direction.** Replacing the second file mid-flight, dismissing the comparison,
   and starting a new primary inspection each leave no pair assembled from two operations.
4. **Cancellation is not absence.** A cancelled compared inspection yields no pair, never a pair with an
   absent side.
5. **Absence and failure stay apart**, per side and per artefact, and neither is drawn.
6. **Shared-axis arithmetic, without rendering.** For extents *(e₁, e₂)*, each side's drawn fraction is
   `eᵢ / max(e₁, e₂)`; the shorter side's drawing ends exactly at its own extent; the remainder is
   reported as out of range rather than as a bucket or a cell. Asserted for time and for frequency, and
   for the equal-extent case, where both fractions are exactly 1.
7. **No per-file re-ranging.** Both lanes are driven by the same amplitude range and the same ramp
   inputs, asserted as values; a control that re-ranges one lane fails.
8. **Export unchanged.** A report exported with a comparison on screen is byte-identical to the same
   report exported without one.
9. **Bounded retention.** At most one pair is retained, and a new comparison releases the previous one.
10. **Vocabulary sweep.** No string the paired surface can render contains a term §12 forbids, asserted
    over every state it can be in, including both absence sentences.

**Manual — two properties, and only two, because no test can answer either.**

- **M1 — the time remainder reads as absence.** With two files whose durations differ visibly, a person
  looks at the two waveform lanes and reports **whether the shorter file's drawing ends before the right
  edge of the shared axis at a position consistent with the two durations shown in the rows above**, and
  **whether the remainder reads as *there is no audio here* rather than as silence.**
- **M2 — the frequency remainder is distinguishable from the floor.** With a 44.1 kHz file beside a
  96 kHz one, a person looks at the two spectrogram lanes and reports **whether the 44.1 kHz drawing
  stops below the top of the shared axis**, and **whether the region above it is distinguishable by eye
  from the floor colour used inside the drawing.**

Neither is *"looks good"*. M1 asks about one edge and one region; M2 asks about one edge and one colour
distinction. A person who cannot answer them as written has found a defect, not a gap.

## Follow-ups

- **The change is `add-two-file-visual-comparison`**, and it is not created by this record. One
  presentation question is deliberately left open for it rather than decided here: whether the paired
  drawings sit **beside** the primary file's own waveform and spectrogram sections — showing the first
  file twice — or **replace** them while a comparison is open. Both are defensible: the canonical
  `waveform-visualization` requirement leans toward the first, and the second duplicates nothing but
  removes a view the reader may still want. It is a product judgement, and it changes what the change's
  spec has to say.
- **Evidence comparison is unblocked and undesigned.** What it will need is retained; nothing is added
  for it, and nothing here authorises alignment, correlation, residual or gain matching.
- **`add-two-file-technical-comparison` group 4's reversal criterion is met** — *"revisit if… the visual
  slice is abandoned"*, and it is not. Its decision that the second file's visualisations are discarded
  is superseded by the change implementing this record, not by this record, and its own task text is not
  edited here.
- **A third file, or a comparison over many files**, is out of scope and would reopen §4 and the memory
  figures before anything else.
