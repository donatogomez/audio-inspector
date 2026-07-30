# Audio Inspector documentation

## Index

- [project-principles.md](project-principles.md) — the guiding principles (tie-breakers).
- [vision.md](vision.md) — product vision, principles, non-goals.
- [architecture.md](architecture.md) — modules, boundaries, dependency rules, composition root.
- [concurrency.md](concurrency.md) — Swift 6 isolation map and cancellation model.
- [analysis-methodology.md](analysis-methodology.md) — evidence/inference/conclusion, confidence, metric definitions.
- [testing-strategy.md](testing-strategy.md) — Swift Testing, fakes, determinism, `SyntheticAudioFactory`.
- [json-schema-v1.md](json-schema-v1.md) — the versioned JSON export contract (`schemaVersion` 1).
- [privacy.md](privacy.md) — local-only processing, what is stored, telemetry opt-out.
- [roadmap.md](roadmap.md) — phased plan.
- [signal-flow-reuse-audit.md](signal-flow-reuse-audit.md) — what we adopted from the SignalFlow reference and why.
- [claude-code-setup.md](claude-code-setup.md) — OpenSpec-generated config and the (deferred) review-agent proposal.
- [adr/](adr/README.md) — architecture decision records.

## Where each kind of information lives

To avoid duplicating the same content in several places, each source has a distinct job. Prefer a
cross-link over a copy.

| Source | Holds | Does **not** hold |
| --- | --- | --- |
| **OpenSpec specs** (`openspec/specs/`) | Current, accepted behavior and requirements — the source of truth for *what the system does*. | Rationale, proposals, or how-to. |
| **OpenSpec changes** (`openspec/changes/`) | In-flight proposals: `proposal.md` (why), `design.md` (how), `specs/` deltas, `tasks.md` (work). Archived on completion. | Long-lived reference material. |
| **docs/** | Stable, human-oriented material: vision, architecture, methodology, concurrency, testing, guides. | Per-change task lists or accepted-requirement text (those live in OpenSpec). |
| **ADRs** (`docs/adr/`) | Significant, hard-to-reverse decisions with consequences and rejected alternatives. Immutable once accepted. | Day-to-day design detail or requirements. |
| **GitHub issues / PRs** | Execution and review of specific work. | Specifications — an issue never replaces a spec. |

Rule of thumb: a **requirement** goes in an OpenSpec spec; a **decision** goes in an ADR; an
**explanation/guide** goes in `docs/`; a **task** goes in an OpenSpec change's `tasks.md`; **review
of a change** goes in a PR.
