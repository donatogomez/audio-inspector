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

**Focus:** `add-drag-and-drop-file-import` — adding drag & drop as a second explicit way to select the
single local audio file to inspect, reusing the existing inspection pipeline end to end.

**Status:** The change and ADR-0014 are written and integrated; no functional implementation has
started. ADR-0014 stays **Proposed** on purpose: it will only be accepted once the implementation, its
tests, the manual Finder observation and the sandboxed validation back the decision, since an accepted
ADR is immutable here.

**Next step:** Prepare and run the real Finder/sandbox spike **before** the definitive routing. What
the drop actually delivers — a conventional path URL or a file-reference one, and whether the granted
access survives the asynchronous hop — decides whether URL normalisation is needed at all and which
layer owns it. Only the maintainer can perform it: it needs real drags onto a signed, sandboxed build.

**Why:** Building the routing on an assumption about Finder's behaviour would put a guessed value into
the report and the exported JSON, which is exactly what the project's honesty invariants forbid. The
observation is cheap; guessing is not reversible once the shape of the code depends on it.

**Open questions / threads:** Does a dropped URL ever arrive in file-reference form, and does the
auto-started sandbox extension survive into the asynchronous inspection? Both are answered by the
spike; the normalisation owner follows from the answer.

---
_Last touched: 2026-08-04. Overwrite freely; empty is fine._
