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

**Focus:** None in progress — drag & drop is implemented, validated and closed; the tree is at a clean
checkpoint.

**Status:** A file can now be inspected by dropping it anywhere on the window as well as by picking it
in the open panel. Both are explicit user selections and both run the **same** pipeline — one
coordinator, one security-scope handling, one mapper, one reader, one use case and one flow state
machine — so neither entry point can drift from the other. A drop that cannot become a single
inspectable local file is refused whole, keeping any report already on screen, and refusals never
become inspection failures. No entitlement was added, nothing is persisted, and feature modules stay
free of file locations, now enforced by the boundary script rather than by convention. ADR-0014 is
accepted, backed by the automated suite and a sandboxed manual run.

**Next step:** Not started. The next product step opens as its own OpenSpec change with its own
proposal — waveform, spectrogram, an educational mode, or anything else. None of them may be grafted
onto the closed change.

**Why:** The slice existed to add a second way in without a second pipeline, and that is exactly what
it does; further capability belongs to a different scope.

**Open questions / threads:** One known gap, carried in ADR-0014 and in the manual runbook rather than
in code: iCloud files, aliases, symlinks, app bundles and Mail file promises were never dropped, so a
file-reference URL is unproven rather than impossible. It would surface as a wrong display name, and
the answer is to extend the manual run when such a source appears — not to add preventive
normalisation.

---
_Last touched: 2026-08-04. Overwrite freely; empty is fine._
