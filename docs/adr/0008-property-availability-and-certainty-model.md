# ADR-0008: Explicit property availability and certainty model (exhaustive, no invalid states)

- **Status**: Accepted
- **Date**: 2026-07-30
- **Deciders**: Project maintainer
- **Related**: docs/analysis-methodology.md, ADR-0009, docs/json-schema-v1.md, change add-basic-audio-file-inspection

## Context

Audio metadata is frequently missing, format-dependent, or unreliable. The product's core principle
is honesty: never invent values, never present inference as fact (`docs/analysis-methodology.md`).
"Absent", "the format can't express this", "readable but untrustworthy", and "extraction errored"
are semantically different and must be distinguishable. A loose struct of `{ state, value?, note? }`
is rejected because it permits **incoherent combinations** (e.g. `state = available` with no value,
or `state = failed` with a value).

## Decision

Model a property in `AudioInspectorDomain` as an **exhaustive sum type** (Swift `enum` with
associated values) that makes invalid states unrepresentable. Conceptually:

- `available(value)` — a trustworthy value is present (value is **required**);
- `unavailable(reason?)` — the file/format does not carry it;
- `unsupported(reason?)` — the format cannot express it (e.g. bit depth for a lossy codec);
- `uncertain(value?, reason)` — read but not reliable; **reason is required**, value optional;
- `failed(code, message)` — extracting this property errored; inspection continues for the rest.

Only `available` (required) and `uncertain` (optional) can carry a value; `unavailable`,
`unsupported`, and `failed` cannot. `failed` carries a **stable `code`** (machine-processable) and a
descriptive `message`. **Error codes are part of the identity; messages are not** — messages may be
reworded/localized without changing behaviour, so automated processing keys off `code`.

Non-`available` cases drive `InspectionWarning`s (each with its own stable `code`) and the global
`InspectionStatus`.

### Domain model vs serialized contract

The safe domain model above (a sum type) is **distinct** from its wire representation. The JSON
export DTO (ADR-0009) uses a **flat** shape — `{ state, value, unit, reason, error }` — because JSON
has no sum types; the mapper (domain → DTO) is the only place that flattening happens, and it upholds
the same invariants (e.g. never emits `value` for `unsupported`). See `docs/json-schema-v1.md`.

## Alternatives considered

- **`{ state, value?, note? }` struct.** Permits invalid combinations; rejected (this ADR's whole
  point).
- **Plain `Optional<Value>`.** Collapses four "no value" meanings into one; can't tell "unsupported"
  from "errored". Rejected.
- **Throwing per property.** Loses partial results and forces control-flow for the normal "absent"
  case. Rejected; `failed` is a state at the report level, not an exception.

## Consequences

### Positive
- Invalid states are unrepresentable in the domain; honest by construction; reused by every future
  metric/finding. Stable `code`s make warnings/errors machine-processable.

### Negative / costs
- A sum type needs an explicit, tested mapper to the flat JSON DTO (more mapping code).

### Neutral
- Establishes the `available/unavailable/unsupported/uncertain/failed` vocabulary reused alongside
  the confidence levels in `docs/analysis-methodology.md`.

## Follow-ups

Implemented in the `add-basic-audio-file-inspection` slice; the flat JSON representation and the
initial stable code registry live in `docs/json-schema-v1.md`.
