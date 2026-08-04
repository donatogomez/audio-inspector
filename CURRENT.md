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

**Focus:** None in progress — the tree is at a clean checkpoint, ready for the next slice.

**Status:** Groups 1–5 of the active change are complete and integrated on `main`. A report view in
`FeatureAnalysis` presents an already-available `InspectionReport`, and the App layer can export it
as JSON v1 to a destination the user chooses. Group 6 has not started.

**Next step:** Begin Group 6 of `add-basic-audio-file-inspection` — sandboxed selection of the source
file and wiring selection → inspection → the report view (see its `tasks.md`).

**Why:** Presentation and export are in place but still have no real report to show: the remaining
vertical-slice step is letting the user pick a file, running the inspection, and feeding the result in.

**Open questions / threads:** None.

---
_Last touched: 2026-08-03. Overwrite freely; empty is fine._
