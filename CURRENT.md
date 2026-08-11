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
**Focus:** `add-computed-technical-properties` is implementation-complete but **not** closing yet, on
`feature/add-signal-level-metrics-generation`, not merged. A real, reproducible defect was found by
manual validation and stands unfixed. Every capability's own architecture is still exactly as recorded
before: `averageFileBitrate` threaded end to end and confirmed on screen and in a real export;
`SignalLevelMetrics` produced by its own independent operation and presented correctly (verified on
screen, in this session, against a real build). **What is not correct: the real export button never
puts `measurements` in the JSON**, even when the screen already shows real signal level values — a
person confirmed this twice, several minutes apart, both exports missing `measurements` entirely
despite the on-screen values already being settled. Full detail, evidence, and the leading (unconfirmed)
hypothesis — a `.toolbar` `ToolbarItem`'s closure possibly not rebuilding on re-render — are in
`docs/manual-validation-mvp.md`. No code was touched to investigate or fix this: this session's scope
was validation only.

**Why the automated suite (868 tests, still green) never caught this.** Every test that exercises
`SignalLevelMetrics` reaching the exporter constructs the fixture directly and hands it to the exporter
or the coordinator — none go through `ReportView`'s real `Button`. `EndToEndFlowTests`, which does
exercise the real coordinator end to end, calls `export(report, signalLevelMetrics: nil)` explicitly in
every scenario. No test in this repository has ever driven the actual export button with real metrics
present. That gap is now named, not just implied.

**ADR-0018 stays `Proposed`.** Its promotion criterion needed this change's own manual validation to be
done — it now has been, and it failed. This is a stronger, more specific state than "not yet validated":
a real defect is now known, not merely an unattempted check.

**Next step:** reproduce the defect under a debugger (or an automated UI-level test, if this project
ever adopts one) to confirm or rule out the toolbar hypothesis, then fix it, then re-run the manual
export check to confirm `measurements` actually appears. Only after that can ADR-0018 be reconsidered
and 8.3 closed. Merge and `openspec archive` remain after that, unchanged. Nothing in this session
pushed, opened a PR, or archived.

**Other open threads** (see `openspec list` for their real task counts, not restated here):
`add-static-spectrogram-visualization` (manual validation battery deferred by product decision) and
`add-two-file-technical-comparison` (one accessibility criterion open, blocked on a known VoiceOver
traversal gap shared with ADR-0015). Neither was touched this session.

---
_Last touched: 2026-08-11. Overwrite freely; empty is fine._
