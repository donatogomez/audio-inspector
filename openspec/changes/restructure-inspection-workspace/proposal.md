# Turn one scrolling page into a workspace with five sections

## Why

Everything the app knows about a file arrives on **one page**, in the order the features were built.
Waveform, spectrogram, eight property rows, four measurements, warnings, the global status — and, when a
second file is chosen, a whole comparison underneath all of it.

That has three costs, and they are structural rather than cosmetic:

- **There is no first thing to read.** `docs/vision.md` §5 requires *"a plain-language summary and a
  technical view"* for every result. The page delivers both simultaneously, which is neither.
- **A comparison arrives as more page.** A person asks for it explicitly and it appears below everything
  they did not ask about, after the part of the page they had already scrolled past.
- **Nothing has a place to be delivered into.** Every new analysis has been appended to the bottom for
  seven slices, and the next one has nowhere better to go.

Meanwhile the domain says clearly what the shape should be: there is **one file at a time**, nothing is
kept between inspections (ADR-0004, ADR-0010), and a comparison is derived *from the report on screen*
and dies with it. The surface has simply never matched that.

## What Changes

- **Five sections replace the scroll** — Overview, Measurements, Waveform, Spectrum, Details — and the
  same five exist whether or not a comparison is settled. What changes with a comparison is what each
  section **contains**, never which sections there are.
- **The selected section becomes presentation state owned by the composition root** (ADR-0026 §4). No
  target below it can name the selection; no domain value, no flow field, no persistence.
- **A comparison becomes a mode**, not a document. Starting one does not move the reader; ending one
  does not either. Only a new primary file returns to Overview.
- **The Comparison Overview is deliberately reduced** to the two file identities, each side's own basic
  facts, the existing factual framing and a way through to the full comparison — because
  `audio-two-file-comparison` forbids aggregates, and a filtered differences list would carry one in its
  empty state (ADR-0026 §8).
- **Delivered as nine slices**, each a small PR against a settled architecture. This change **is the
  first of them** — the shell — and carries the map for the rest; each later slice carries its own
  requirements against the capability that already owns the content it re-lays-out.

## What This Deliberately Does Not Do

**It changes where things are, not what is true about them.**

Every semantic contract survives the redesign unchanged, and the design's contract matrix names each one
with the capability or ADR that protects it. In particular: no aggregate over a comparison, absence is
never zero, *first* and *second* stay positional, no origin or provenance inference, measurement outcome
semantics as they are, an LU difference only where the unit is one, resolution-aware bandwidth wording,
absolute scales for both drawings, shared axes for a pair, paired standing in for single, the export
untouched, `schemaVersion` 1 untouched, one PCM read per inspection, one accessibility element per
drawing, and no zoom, cursor or scrubbing.

**A redesign may not retire a semantic test by calling it legacy.** If a slice makes an existing
assertion impossible to write in the same words, that is a finding about the slice, not about the test.

Also excluded, each deliberately: **history, recents and any library** — nothing persists, so there is
nothing to browse; **a sidebar** (ADR-0026 §12, which records the divergence from `docs/vision.md` §7 and
the condition that would end it); **any new interaction on the drawings** — no zoom, cursor, scrubbing,
playback or synchronised navigation; **evidence comparison and Findings**; **export**; and **any summary,
score, verdict or count over a comparison**.

## Impact

- **New**: the section selection and its lifetime, in the composition root, and the
  `inspection-workspace-navigation` capability that describes them. Nothing about what a section
  contains.
- **Changed, per slice**: how each existing section's content is laid out and reached. `ReportView` is
  decomposed rather than rewritten.
- **Untouched**: `AudioInspectorDomain`, `AudioInspectorMedia`, `AudioInspectorAnalysis`,
  `ImportFlowModel`, `ComparisonState`, every accumulator, the shared read, `SpectrogramColourRamp`, the
  export contract and `schemaVersion` 1.
- **Inherited**: the VoiceOver traversal gap recorded against ADR-0015 and ADR-0017, which the redesign
  is a plausible opportunity to close and is not required to.

## Dependencies

- **ADR-0026** (`Proposed`) governs this change, and R1 is what its promotion conditions are written
  against.
- **ADR-0024** and **ADR-0025** (`Accepted`) are inherited unchanged and must not be weakened; the
  Comparison Overview's smallness is derived from the first of them.
- **ADR-0017** is `Proposed` and referenced only. This change supplies no evidence toward its promotion.
- **`add-two-file-technical-comparison`** and **`add-static-spectrogram-visualization`** are open and
  are **not touched**. Their surfaces are re-laid-out by later slices; their contracts are not reopened.
