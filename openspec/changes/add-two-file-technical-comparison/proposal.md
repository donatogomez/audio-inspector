## Why

The product vision names the question in the user's own words — *"Which of my three copies of this
album is the best one to keep?"* — and the roadmap places version comparison in Phase 7 with a guard
attached: *"never auto-picking highest SR/bitrate/bit depth."* The question a collector asks and the
answer this instrument may honestly give are not the same question, and closing that gap carelessly is
the fastest way to turn an instrument into an oracle.

Today a user with two copies of the same album inspects one, writes down what they saw, inspects the
other, and compares in their head. Everything they need is already on screen — twice, at different
times. The app produces the facts and leaves the reader to hold them side by side.

**This slice does the holding, and nothing else.** It answers exactly one question:

> Which observable technical facts are the same, different, or not comparable between these two files?

It forces one modelling decision that everything later depends on, which is the real reason to do it
first. **Comparing two files is not comparing two numbers — it is comparing two `Property` values.**
When one file reports `bitDepth = .available(16)` and the other reports `bitDepth = .unsupported`
because its codec is lossy, the answer is not "different": nothing was compared, and saying otherwise
manufactures a fact out of an absence. ADR-0008 made that class of mistake unrepresentable for a single
property; a comparison inherits the problem one level up and needs the same structural answer rather
than a `Bool`. Settling that now makes the visual and evidence levels additive later; settling it
wrongly would poison them.

This slice is also only feasible now. It inspects and holds **two** files where the app held one, and
before the spectrogram's optimisation the second file's analysis would have cost tens of seconds.

## What Changes

- A **new capability**, `audio-file-comparison`. Not an extension of `audio-file-inspection`: it has
  its own behaviour and, more importantly, its own honesty rules.
- A **three-way comparison semantics** in the domain — *same*, *different*, *not comparable* — as an
  exhaustive sum type in the shape ADR-0008 established, with the non-comparable case **first-class**
  and explaining structurally which state each side was in.
- A **pure comparison operation** over two `InspectionReport`s. **No port, no adapter, no framework, no
  I/O, no `URL`, no `async`, no `throws`** — the reports already exist, and comparing them is
  arithmetic over data the app produced.
- A **second-file selection** from an open report — *Compare with another file…* — running the second
  file through the **existing** inspection pipeline unchanged, with the first report preserved
  throughout.
- A **presentation** that shows both files' facts and the comparison state for each property **in
  words**, never by colour alone and never as a ranking.

## What This Deliberately Does Not Do

Each of these is a decision recorded in **ADR-0017**, not an omission:

- **No ordering and no winner.** Nothing states, implies or ranks which file is better, preferable,
  more authentic or worth keeping. The types cannot express it.
- **No aggregate score.** No similarity percentage, no difference count presented as a measure. That is
  product invariant #3 with a different label.
- **No duration tolerance.** Duration is compared **exactly**. A tolerance would implicitly answer a
  different question — *could these be the same recording?* — with an undeclared threshold, inside a
  comparator that claims to state technical facts.
- **No hashes.** Objective and cheap, but they answer *same file* while inviting the reading *same
  audio*, which is false in both directions.
- **No signal comparison.** Waveforms and spectrograms side by side are deferred to
  `add-two-file-visual-comparison`. Both models already exist and are already on an absolute,
  un-normalised scale *because* the user compares copies — they are deferred so the property semantics
  are settled first, not because they are hard.
- **No alignment, correlation, residual or spectral difference**, and no heuristics of any kind. None
  of the metrics such a comparison would need exists yet.
- **No "same recording", no "derived from", no "transcode", no "fake".**
- **No export.** `schemaVersion` 1 stays byte-identical; no comparison field enters it, and no second
  `inspectedFile` will ever be added to it.
- **No batch, no multi-select, no two-file drop, no dedicated two-slot mode.** One file is open; one
  more is chosen.
- **The spectrogram, the waveform, the JSON exporter, `InspectionReport`, `TechnicalProperties`,
  `Property` and the property reader are not modified.**

## Impact

- **New capability**: `audio-file-comparison`.
- **New ADR**: ADR-0017, in `Proposed`.
- **Domain gains** a comparison value type, a per-side state enumeration and one pure operation. It
  gains no port and no dependency.
- **`audio-file-inspection` is not modified.** Inspecting one file behaves exactly as it does today,
  and its export is untouched.
- **`FeatureImport`'s flow state** grows a comparison alongside the report, in the shape the waveform
  and spectrogram already established: **beside** the report, never inside it.
- **No new dependency, no entitlement change, no network, no persistence.** Access to each file remains
  scoped to its own inspection (ADR-0010); the two files are inspected one after the other, and only
  their reports are kept.
