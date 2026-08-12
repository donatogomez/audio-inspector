## Why

`SignalLevelMetrics` already reports the highest **sample** a file contains. That is not the highest
level the file actually produces: the samples are point readings of a band-limited waveform, and the
waveform's real maximum usually falls *between* two of them. A file whose every sample sits at or below
full scale can therefore still drive a converter or an encoder past it — the case `docs/roadmap.md`
Phase 1b names ("integrated LUFS and true peak (oversampling)") and `docs/analysis-methodology.md`
already defines a reference baseline for.

Nothing in the app measures it. ADR-0006 fixed the methodology in advance (ITU-R BS.1770 / EBU R128,
oversampling ≥ 4×, factor and filter recorded, cross-checked against FFmpeg `ebur128`), and the previous
change re-confirmed true peak as out of its own scope precisely so it could get a slice that devotes its
attention to the interpolation filter and that cross-check (`add-computed-technical-properties`
`design.md` §12). This is that slice.

## What Changes

- **A true-peak estimate, per channel and overall** — the maximum of the waveform reconstructed between
  samples, not of the samples themselves. Computed by oversampling before peak detection, per ADR-0006.
- **A new domain value type**, a sibling of `SignalLevelMetrics` rather than a field of it. Sample peak
  and true peak answer different questions with different methods, and the existing type states in its
  own first line that it holds sample-level facts; true peak additionally has to carry the methodology
  that produced it, which nothing in that type does (`design.md` §5).
- **The methodology travels with the value** — the oversampling factor and the interpolation filter,
  as named constants tied to the analysis engine version, never user-configurable. ADR-0006 requires
  them to be "recorded with the result"; today nothing in this project records a methodology anywhere,
  so this establishes the shape (`design.md` §6, **ADR-0019**).
- **A fourth independent operation** over the existing `AudioDecoding` port, with its own cancellation,
  exactly as the spectrogram and the signal level metrics already are (ADR-0016 decision 15). The cost
  of a fourth full decode is **measured before it is accepted**, not assumed (`design.md` §8, group 5).
- **Presentation in dBTP**, in its own section beside the signal levels, stating the value and the
  method — never a verdict. A true peak above 0 dBTP is a measured fact; calling it "clipping",
  "unsafe" or "a bad master" is not (`design.md` §10).
- **An additive `measurements.truePeak` object** in the `schemaVersion` 1 export, in the domain's own
  linear amplitude (never dBTP), beside the existing `measurements.signalLevels`. No version bump —
  the schema's own evolution rule (`docs/json-schema-v1.md`).
- **ADR-0019** (`Proposed`), recording the two decisions ADR-0006 does not make: that a measurement
  carries its own methodology, and that a positive true peak is reported as a value rather than raised
  as a flag in this slice.

## What This Deliberately Does Not Do

- **No LUFS, no LRA, no loudness timeline.** ADR-0006 governs those too, and the roadmap places the full
  suite in Phase 3. Measuring one metric well is this slice's whole scope.
- **No crest factor**, even though peak and RMS both exist and it would be one subtraction. Deferred for
  the reason `add-computed-technical-properties` `design.md` §12 already recorded, unchanged: alone and
  out of the loudness suite's context it invites exactly the "how compressed is this master" reading the
  methodology document warns against.
- **No significant max frequency**, no transcode detection, no quality score, no aggregate of any kind.
- **No inter-sample-clipping flag, warning or finding.** ADR-0006's own sentence — "inter-sample clipping
  is flagged when true peak > 0 dBFS" — is scoped to this slice as a **value**, not a flag: a flag is an
  interpretation, and interpretation in this project carries evidence, alternatives and confidence
  (`docs/analysis-methodology.md`), which is the schema's still-unused `findings` object, not this one.
  Recorded as a decision in **ADR-0019** rather than left as a silent omission.
- **No change to `SignalLevelMetrics`**, its accumulator, its presentation, its export object, or the
  clipped-sample count. `clippedSampleCount` keeps meaning exactly what it means today.
- **No `schemaVersion` bump** and no change to any existing wire field.
- **No analysis-engine-version field** in the domain or on the wire. ADR-0006 ties that to *stored*
  results, and there is no result store yet (ADR-0004 is Phase 2); introducing a cross-cutting version
  field would touch every measurement and the schema envelope, which is its own decision, not a
  side effect of this one (`design.md` §6).
- **No decode deduplication.** The fourth read is measured and either accepted or escalated to its own
  change; nothing here reworks the existing three operations.

## Impact

- Affected capability: `audio-signal-level-metrics` — new requirements only. The existing sample-level
  requirement, its clipping threshold and its isolation requirement are **not modified**.
- Affected code (when implemented, not in this change): a new domain value type, a new accumulator in
  `AudioInspectorAnalysis` (Accelerate/vDSP, per ADR-0006), a fourth generation/operation in
  `AudioInspectorApp`, a new outcome/state in `FeatureImport`, a new section in `FeatureAnalysis`, and a
  new object in the export mapper plus its row in `docs/json-schema-v1.md`.
- No change to `TechnicalProperties` (ADR-0018 forbids it: this requires decoded samples), to
  `InspectionReport`, to the waveform, or to the spectrogram.
