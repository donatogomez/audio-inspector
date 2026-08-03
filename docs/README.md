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

## The repo-wide information map

This file is only the index of `docs/` above. The single, repo-wide map of **where each kind of
information lives** (OpenSpec specs vs. changes, `docs/`, ADRs, git, GitHub issues) is defined **once**
in [`OVERVIEW.md`](../OVERVIEW.md) §5 — consult it there rather than duplicating it here.
