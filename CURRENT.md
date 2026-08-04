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

**Focus:** None in progress — the MVP is finished and integrated; the tree is at a clean checkpoint.

**Status:** The basic audio-file inspection MVP is complete. The app runs the whole path: the user
picks a local audio file under the App Sandbox, it is inspected without DSP, the report is presented
with every property's state, its warnings and a global status, and it can be exported as
`schemaVersion` 1 JSON to a destination the user chooses. The guarantees behind it are covered too:
an automated end-to-end pass over the real chain, the source file proven byte-identical after
inspecting and exporting, an offline configuration with no network capability, the real macOS app
built in CI, and a manual sandbox validation runbook that has been executed.

**Next step:** Open a **new** change for the next product step. The MVP change is closed and must not
be reopened or extended — the next slice (analysis features, or import conveniences such as
drag-and-drop) starts as its own OpenSpec change with its own proposal.

**Why:** The vertical slice it was created to prove — select → inspect → report → export — now runs
and is verified, so further work belongs to a different scope rather than to this one.

**Open questions / threads:** None.

---
_Last touched: 2026-08-03. Overwrite freely; empty is fine._
