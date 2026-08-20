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

**Open thread: `add-two-file-measurement-comparison` — groups 1 to 5 closed, nothing on screen.**
ADR-0024 is `Proposed` and stays there.

**Focus.** The comparison exists, the flow publishes it, and it is now validated against production:
`design.md` §7's ten fixture pairs run over real files through the real decoder and the real shared
read, and twelve negative controls were applied and reverted one at a time. Nothing in the surface or
the export has been touched.

**Next step: group 6 — the surface.** One sub-section beneath the technical rows, in the report's own
order; bandwidth's outcome words about the **grid** rather than about the files; the difference column on
the loudness row and nowhere else; `incomparable` saying *why* structurally; and the forbidden-vocabulary
sweep extended.

**Why ADR-0024 cannot be promoted yet.** Its own criteria are three, and two are met — the comparison
runs against production reusing the already-computed measurements, and the bandwidth rule is demonstrated
on both sides of itself, the boundary case included. The third is *a person looking at the surface*, and
there is no surface. Partial evidence does not promote it.

**Open questions carried into group 6.**

- All three of the comparator's method refusals are **unreachable from production today** — one true
  peak method, one bandwidth identity, one loudness algorithm, two allow-listed weightings. So
  `incomparable(.methodsDiffer)` is a state group 6 must render and cannot produce a screenshot of from
  a real pair of files. How it is validated by eye is undecided.
- `MeasurementComparisonBoundaryTests` reads the shape with `Mirror`, which does not see computed
  properties. It pins the shape a difference would have to take; it cannot pin one derived beside it.
  The surface sweep is the control that has to catch that.

**Inherited, and not to be claimed as fixed**: `add-two-file-technical-comparison` is still open at 52/58
and **ADR-0017 is still `Proposed`**, blocked on the VoiceOver traversal gap shared with ADR-0015. This
change extends that surface and inherits that gap.

**Older threads, neither advanced here**: `add-static-spectrogram-visualization` (manual validation
battery deferred by product decision).

---
_Last touched: 2026-08-20. Overwrite freely; empty is fine._
