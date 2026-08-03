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

**Status:** Groups 1–3 of the active change are complete and integrated on `main`, including the
Group-2 correction that derives descriptive-metadata warnings. Group 4 has not started.

**Next step:** Begin Group 4 of `add-basic-audio-file-inspection` (see its `tasks.md`).

**Why:** The inspection-report pipeline is now contract-complete; the next vertical-slice step is the
JSON export that Group 4 defines.

**Open questions / threads:** None.

---
_Last touched: 2026-08-03. Overwrite freely; empty is fine._
