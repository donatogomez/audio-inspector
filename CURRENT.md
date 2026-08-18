# Current working context

> **Contract — read before editing this file.**
>
> - **A single, overwritable snapshot** of the *current* working focus — **not a log.** Overwrite it in
>   place; never append history (git owns history).
> - **Intent only.** It records what is being worked on and *why* — the narrative no tool captures. It
>   is **never a source of truth** and must never contradict git, OpenSpec, or the ADRs. If it disagrees
>   with them, **they are right and this file is stale.**
> - **May be completely empty** (nothing under the template) when `main` is the latest and no thread is
>   open. **An empty `CURRENT.md` is the correct steady state**, not a gap to fill.
> - **Never put here:** task checklists (→ `openspec/changes/<name>/tasks.md`), branch/commit facts as
>   truth (→ git), decisions (→ `docs/adr/`), explanations (→ `docs/` / `OVERVIEW.md`), rules
>   (→ `CLAUDE.md`).
> - **To learn the real state**, do not trust this file — run `openspec list` and `git status` (see the
>   session protocol in `CLAUDE.md`).

---
**Focus: `add-loudness-measurement` is **complete and accepted**. ADR-0022 is `Accepted`; the branch is
ready to publish. Nothing is pushed, no PR exists, and the archive is deliberately still pending.**

Integrated loudness (LUFS-I) ships as the fifth consumer of the one shared PCM read, with a visible
section, an additive `schemaVersion` 1 export, and no verdict of any kind anywhere.

**All three classes of evidence are in, and ADR-0022's Promotion section keeps them apart** — which is
the point, because collapsing them is how a measurement acquires an authority nobody granted it:

- **normative** — Tech 3341 §2.9 and tests 1–5 plus both BS.1770-5 anchors, reproduced by the
  *production path* within the published ±0.1. Worst deviation **0.0213 LU** (test 5), anchors to
  **0.00028**. The tolerance was met, never widened;
- **automated** — rate-invariance (0.0065 LU over five rates), bit-exact chunk independence, the
  undefined cases as absences, the K-weighting curve, and ten negative controls applied to production
  and reverted;
- **manual** — the maintainer's own battery over four fixtures whose expected values were computed
  programmatically beforehand: 48 kHz published, 96 kHz derived, 399 ms, 10 s silence; presentation,
  copy, light/dark, resize, accessibility, A→B→C without stale state, and the four exported documents.

FFmpeg stays what it always was: a **corroborating oracle**, never a normative source. It agrees to
0.0071 LU at 48 kHz; above that it drifts 0.030 LU from the published value while production holds to
0.0065, so no cross-rate agreement bound is claimed against it.

**Two negative controls found something rather than confirming something**, and both are recorded in the
ADR: the trailing partial block was invisible until a fixture stopped landing on a hop boundary, and the
absolute gate remains unobservable from outside the accumulator — the domain value was *not* widened to
expose a threshold for a test's convenience.

**OpenSpec is 53/54.** The one open task is **9.2**, and it is open by design: its archive half is
explicitly post-merge. `openspec archive` runs after the branch lands on `main`, never before.

**Next step:** publish — push the branch and open the PR against `main`, using
`.github/pull_request_template.md`. After the merge, and only then, run `openspec archive
add-loudness-measurement` and close 9.2.

**Recorded debt, not a thread:** the export chain now takes a third positional optional, which its own
note called the moment to introduce a container. It belongs to whoever adds the fourth measurement, and
`SourceInspectionOutcome`'s fifth payload carries the sibling version of the same debt.

**Known, introduced lint warning:** `ReportJSONDTO.swift` is 415 lines against SwiftLint's 400. The file
was clean before the export change; the alternatives were splitting the wire DTOs across files or
cutting documentation. SwiftLint is not one of the four gates.

**Minor follow-up, not a thread:** `ImportFlowComparisonTests` has one `Task.yield()` that was never
audited in depth; no failure has ever been attributed to it.

**Other open threads** (see `openspec list` for their real task counts, not restated here):
`add-static-spectrogram-visualization` (manual validation battery deferred by product decision) and
`add-two-file-technical-comparison` (one accessibility criterion open, blocked on a known VoiceOver
traversal gap shared with ADR-0015). Neither was touched this session.

---
_Last touched: 2026-08-18. Overwrite freely; empty is fine._
