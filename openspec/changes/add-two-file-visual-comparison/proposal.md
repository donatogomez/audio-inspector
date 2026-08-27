# Show two files' waveforms and spectrograms under one shared, absolute reference

## Why

The comparison already compares two files' metadata and, since `add-two-file-measurement-comparison`,
four measurements. It shows no pictures — and not for want of them.

The second file's amplitude envelope and spectral model **are produced**. Its inspection runs the same
pipeline, and one shared PCM read yields all six analyses;
`ComparisonMeasurementsReachTheComparisonTests` asserts, against production, that the compared file gets
**one decoder and one decode call** and that its waveform and spectrogram both come back `.available`.
They are then dropped one line later, in `ImportFlowModel.settle(…)`, where `analyses.settledMeasurements`
is kept and the rest of `analyses` goes out of scope. The code says why: *"The visualisations are still
discarded, because `ReportMeasurements` has no field either could occupy."*

That discard was decided deliberately, in `add-two-file-technical-comparison` group 4, with a reversal
criterion and this reason among its evidence: *"The next slice needs them.
`add-two-file-visual-comparison` will draw exactly these two models."* This is that slice.

A person holding two copies of an album can currently read that both are 44.1 kHz 16-bit FLAC, see four
measurements side by side, and never look at the two pictures that would show them **where each file's
energy sits and where it stops** — pictures that exist, in memory, and are deleted.

## What Changes

- **The flow stops discarding the compared file's visual artefacts.** They are kept in a per-file
  container that is a **sibling** of `ReportMeasurements`, never a field of it (ADR-0025 §3), carrying
  what became of the envelope, what became of the spectral model, and the `PCMStreamDescription` the read
  already produced. Nothing is read again and nothing is computed again.
- **A settled pair is published atomically**, one payload in one assignment, so a first file's picture can
  never appear beside a second file's from another operation (ADR-0025 §5, the shape
  `MeasurementComparison` already uses).
- **Both waveforms are drawn on one absolute amplitude scale and one shared time axis**, spanning the
  **longer** of the two files. Each file occupies its own fraction of that axis and stops there; the
  remainder carries no bar and is stated as **outside that file's audio** — not as silence (ADR-0025 §8).
- **Both spectrograms are drawn on the same ramp, the same floor and the same legend**, on that same
  shared time axis, and on one shared frequency axis reaching the **higher** of the two Nyquists. Each
  grid occupies `its nyquist / the shared nyquist`; the region above it carries no cell, is stated as
  **outside what that file can represent**, and is visually distinguishable from the ramp's floor colour
  (ADR-0025 §7, §9).
- **While a settled pair exists, the paired drawings stand in for the first file's own waveform and
  spectrogram sections.** The technical comparison, the measurement comparison and every property row stay
  exactly where they are. When the pair goes — dismissed, superseded, or ended by a new primary
  inspection — the single-file drawings return from the values already held, with nothing recomputed.

## What This Deliberately Does Not Do

**It pairs and presents two pictures. It says nothing about what their similarity or difference means —
and it does not say whether they are similar or different at all.**

There is no visual outcome, and no field one could be written in: not *same*, *different*, *identical*,
*similar*, *matching*, *matching regions*, *indistinguishable*, *separated*; not *louder* or *quieter*,
not *more* or *less high-frequency content* — those already have measured, compared answers in the rows
above, and repeating them from a picture would be a second, worse source for a fact the surface already
carries. ADR-0017 itself predicts the visual level needs `same`/`different` **with a confidence level
added**; a confidence level is the Findings capability's machinery, and that is exactly why the
vocabulary is declined here rather than borrowed (ADR-0025 §2, §12).

Also excluded, each deliberately:

- **No mathematical comparison of the two pictures** — no difference, residual, correlation, alignment,
  gain matching, spectral difference or matching regions. That is ADR-0017 §9's *evidence comparison*.
- **No interaction** — no cursor, no zoom, no scrubbing, no synchronised scrolling. The canonical
  `waveform-visualization` rule (*"no playback, no zoom, no scrubbing, no selection and no cursor"*) is
  not weakened by putting two drawings on one surface, and a synchronised cursor is an alignment claim
  wearing a control.
- **No conclusion about origin or quality** — same master, remaster, transcode, upsample, better, worse,
  which to keep. Findings'.
- **No export.** Neither `WaveformEnvelope` nor `Spectrogram` is `Codable`; `schemaVersion` 1 describes
  one file and gains nothing here.
- **No second PCM read and no recomputation.** Recomputing either artefact for the pair would be a second
  decode by another name.
- **No third file**, and no change to what a single file's inspection produces or reports.

## Impact

- **New**: a per-file visual container and its settled pair in `FeatureImport`; paired geometry and a
  paired section in `FeatureAnalysis`; one new capability, `audio-two-file-visual-presentation`.
- **Changed**: `ImportFlowModel` retains what it already receives and publishes the pair beside the
  comparison it belongs to; the report surface chooses between the single drawings and the paired ones.
- **Untouched**: `WaveformEnvelope`, `Spectrogram`, `PCMStreamDescription`, `ReportMeasurements`,
  `MeasurementComparison`, `FileComparison`, `InspectionReport`, every accumulator, the shared read, the
  export contract and `schemaVersion` 1. No new port, no adapter, no framework, no second decode, no new
  dependency.
- **Inherited**: the VoiceOver traversal gap this surface already carries (ADR-0015, ADR-0017), which this
  change neither fixes nor worsens.

## Dependencies

- **ADR-0025** (`Proposed`) governs every decision here, and this change is what its promotion conditions
  are written against.
- **ADR-0020** and **ADR-0021** (`Accepted`) are load-bearing: one read per inspection is what makes the
  second file's pictures free. This change spends none of that saving.
- **ADR-0024** (`Accepted`) is inherited unchanged — factuality, absence-is-never-zero, atomicity, and
  sibling-never-extension — and is not weakened.
- **ADR-0016** is `Proposed` and its deferred manual validation is **not** read as a pass. It is **not a
  precondition**: what this change uses from it is the `Spectrogram` model and two rules already in
  production and asserted by tests (ADR-0025's *Relationship to ADR-0016*). The `spectrogram-visualization`
  capability is not canonical yet, which is why this change **adds** a capability of its own rather than
  modifying that one.
- **ADR-0017** is `Proposed`, referenced, and **not edited**. Its `First file` / `Second file` attribution
  is reused verbatim; its `same`/`different`/`incomparable` vocabulary is not. This change supplies no
  evidence toward its promotion.
