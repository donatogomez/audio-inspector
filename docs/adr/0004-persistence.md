# ADR-0004: Persistence with SwiftData (results and references only)

- **Status**: Proposed (direction; not in the MVP — to be confirmed by a Phase-2 spike)
- **Date**: 2026-07-30
- **Deciders**: Project maintainer
- **Related**: ADR-0002, docs/architecture.md, docs/privacy.md

## Context

We must persist analysis results, file references (security-scoped bookmarks), hashes, dates,
sizes, warnings, reports, comparisons, and the analysis engine version — **never audio, never file
copies**. The store keys a versioned result cache with invalidation. Target is macOS 15 with Swift
6 / Strict Concurrency.

## Decision

**Proposed direction:** when persistence is introduced (Phase 2 — the MVP needs none), use
**SwiftData** as the local store, isolated in the `AudioInspectorPersistence` target behind the
Domain `AnalysisPersisting` port, mapping Domain value types to/from SwiftData models at that
boundary so the domain never imports SwiftData. This is **not Accepted yet**: SwiftData's behavior
at collection/batch scale (queries, migrations, `@ModelActor` throughput) will be validated by a
Phase-2 spike before it is locked in; the `AnalysisPersisting` port keeps a fallback to SQLite
contained.

## Alternatives considered

- **Raw SQLite (GRDB or C API).** Maximum control and query power, mature concurrency story.
  Heavier to hand-roll; a third-party wrapper needs justification. Kept as the fallback if SwiftData
  proves limiting for batch-scale queries or migrations.
- **Core Data directly.** Capable but more boilerplate and an older concurrency model than
  SwiftData on our target OS. Rejected.
- **Plain files (JSON per analysis).** Trivial and transparent, but poor for querying/filtering a
  large library and for cache invalidation. May still back JSON *export* (a separate concern).

## Consequences

### Positive
- Native, first-class Swift 6 concurrency, minimal boilerplate, easy to keep behind a port; no
  third-party dependency.

### Negative / costs
- SwiftData is younger than Core Data/SQLite; complex batch queries or custom migrations may push us
  toward SQLite later.

### Neutral
- The `AnalysisPersisting` port boundary makes a future swap to SQLite contained.

## Follow-ups

Define the result-cache fingerprint (file hash + size + mtime + engine version) and invalidation
rules in the relevant OpenSpec change; validate performance on large collections in Phase 2. The
`AudioInspectorPersistence` target is introduced in Phase 2, not the MVP.
