# ADR-0008: Explicit property availability and certainty model

- **Status**: Accepted
- **Date**: 2026-07-30
- **Deciders**: Project maintainer
- **Related**: docs/analysis-methodology.md, ADR-0009, change add-basic-audio-file-inspection

## Context

Audio metadata is frequently missing, format-dependent, or unreliable. The product's core principle
is honesty: never invent values, never present inference as fact, and distinguish evidence from
uncertainty (`docs/analysis-methodology.md`). A property therefore cannot be modelled as a plain
optional — "absent", "the format can't express this", "readable but untrustworthy", and "extraction
errored" are semantically different and must be distinguishable in the UI and the JSON export.

## Decision

Model every technical property as a `Property<Value>` in `AudioInspectorDomain`: a `Sendable` value
type pairing a `PropertyState` with an optional value and an optional note. `PropertyState` is a
closed enum:

- `available` — a trustworthy value is present;
- `unavailable` — the file/format simply does not carry it;
- `unsupported` — the format cannot express it (e.g. bit depth for a lossy codec);
- `uncertain` — a value was read but is not reliable (may carry the tentative value + note);
- `failed` — extracting this specific property errored (inspection continues for the rest).

Invariant: only `available` and `uncertain` may carry a value. Non-`available` states drive
`InspectionWarning`s and the global `InspectionStatus`.

## Alternatives considered

- **Plain `Optional<Value>` (nil = missing).** Collapses four distinct meanings into one; can't tell
  "unsupported" from "errored". Rejected.
- **A single global confidence on the whole report.** Too coarse; certainty is per-property.
  Rejected (a report-level status still exists, but per-property state is primary).
- **Throwing per property.** Loses partial results and forces control-flow for normal "absent"
  cases. Rejected; `failed` is a state, not an exception at the report level.

## Consequences

### Positive
- Honest by construction; the UI and JSON can render each state distinctly; reused by every future
  metric/finding.

### Negative / costs
- A generic wrapper adds a little verbosity and requires explicit DTO mapping for JSON.

### Neutral
- Establishes the vocabulary (`available/unavailable/unsupported/uncertain/failed`) that later
  analysis layers reuse alongside the confidence levels in `docs/analysis-methodology.md`.

## Follow-ups

Implemented in the `add-basic-audio-file-inspection` slice; the JSON representation of each state is
fixed in `docs/json-schema-v1.md`.
