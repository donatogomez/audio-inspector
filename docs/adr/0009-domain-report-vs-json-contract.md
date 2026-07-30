# ADR-0009: Separate the domain report from the JSON export contract

- **Status**: Accepted
- **Date**: 2026-07-30
- **Deciders**: Project maintainer
- **Related**: ADR-0001, ADR-0008, docs/json-schema-v1.md, change add-basic-audio-file-inspection

## Context

The app exports results as JSON (`schemaVersion` 1). The domain must stay pure — ADR-0001 and the
boundary rules forbid `AudioInspectorDomain` from importing serialization frameworks. At the same
time the JSON is a **public, versioned contract** that must evolve independently of internal domain
types (field names, additive evolution, `schemaVersion`).

## Decision

Keep two distinct representations, joined by an explicit mapper:

- **Domain report** — `InspectionReport` and friends: pure `Sendable` value types in
  `AudioInspectorDomain`, carrying the data and its property states. The domain:
  - does **not** know `schemaVersion`;
  - does **not** import `JSONEncoder`/`Codable`-for-wire;
  - does **not** own the generation timestamp or generator identity.
- **Export envelope** — a `Codable` DTO plus a `JSONEncoder`, in the export layer (app/infra) behind
  the domain port `ReportExporting`. The **exporter creates the versioned envelope**: it owns
  `schemaVersion`, `generatedAt`, and `generator`, and maps the domain report into the field-level
  contract in `docs/json-schema-v1.md` (flat property shape, field naming, redaction).

An **explicit mapper** (domain → DTO) is the only coupling point, so the domain report and the wire
DTO **evolve independently**: renaming a JSON field or adding an additive `schemaVersion`-1 field
never touches the domain, and refactoring domain types never breaks the contract.

`generatedAt` is the **export** time, which need not equal the inspection time; if inspection time is
ever needed on the wire it becomes a separate, explicit field — it is not conflated with the
envelope timestamp.

## Alternatives considered

- **Make domain types directly `Codable` and encode them.** Simplest, but couples the wire format to
  internal types, leaks serialization into the domain, and makes `schemaVersion` discipline fragile.
  Rejected.
- **Generate JSON ad-hoc (dictionaries/strings).** Violates the "no `JSONSerialization`, use
  `Codable`" rule and is error-prone. Rejected.

## Consequences

### Positive
- Domain stays pure and framework-free; the JSON contract can evolve additively and independently;
  `schemaVersion` lives in exactly one place.

### Negative / costs
- An explicit DTO + mapping layer to maintain (more types).

### Neutral
- The mapping layer is the natural home for redaction (e.g. sandbox-safe paths, ADR-0010) and for
  future additive fields (`measurements`/`findings`).

## Follow-ups

Field-level contract in `docs/json-schema-v1.md`; DTO/encoder implemented in the
`add-basic-audio-file-inspection` slice (app/infra layer, not the domain).
