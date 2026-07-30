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

Keep two distinct representations:

- **Domain report** — `InspectionReport` and friends: pure `Sendable` value types in
  `AudioInspectorDomain`, carrying the data and its `PropertyState`s. The domain does **not** import
  `JSONEncoder`/`Codable`-for-wire and knows nothing about `schemaVersion`.
- **Export contract** — a `Codable` DTO plus a `JSONEncoder`, living in the export layer (app/infra)
  behind the domain port `ReportExporting`. The DTO maps the domain report to the field-level
  contract in `docs/json-schema-v1.md` and owns `schemaVersion`, `generator`, and field naming.

Mapping is explicit at that boundary; changing the wire shape never forces a domain change and
vice-versa.

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
