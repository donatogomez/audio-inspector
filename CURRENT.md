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

**Open thread: `add-two-file-measurement-comparison` — built, tested and on screen; blocked on one
manual observation.** ADR-0024 is `Proposed` and **stays there**.

**Focus.** Groups 1 to 6 are closed and 8.1 is green. The measurement comparison runs against production
on real files, the flow publishes it atomically, and the sub-section renders beneath the technical rows.
Nothing in the export, the JSON schema, Findings or the two visualisations was touched.

**Why the ADR is not promoted.** Two of its three literal conditions are met. The third —
*"the surface is validated by a person looking at it"* — did not happen: Screen Recording and
Accessibility are both refused to this session, exactly as they were for `add-two-file-technical-comparison`
on 2026-08-08. Partial evidence does not promote it, by the ADR's own words.

**Next step: a person runs the battery.** Everything is prepared — twelve fixtures, six pairs, every
expected string measured through production *before* the app was opened, in the change's `README.md`;
the app cleaned and rebuilt from the branch head. `docs/manual-validation-mvp.md` (2026-08-21) has the
re-run instructions and what blocked it. Then decide ADR-0024, then push, PR, merge, and
`openspec archive` — in that order.

**Three things for that person to rule on**, seen in a headless render and deliberately not acted on:

- A missing measurement shows `No value` in **both** columns, though the first file has a value. The
  domain's gap carries no surviving number, so the surface has none to show; fixing it means publishing
  both bundles beside the comparison, which is a flow change with the atomicity cost group 3 exists to
  prevent.
- Every single-row block repeats its own name — `True peak` above a row called `True peak`. Only
  `Signal levels` genuinely groups.
- The channel-count note repeats verbatim in three blocks, and the rounding note can land on three rows
  of one pair. Both correct, both wordy.

**Also unobserved, and not this change's to fix**: `incomparable(.methodsDiffer)` is a state no pair of
real files can produce, so it is validated in the presentation tests and named as an exclusion in the
battery rather than faked.

**Inherited, and not to be claimed as fixed**: `add-two-file-technical-comparison` is still open at 52/58
and **ADR-0017 is still `Proposed`**, blocked on the same permissions and on the VoiceOver traversal gap
shared with ADR-0015. This change extends that surface and inherits both.

**Older threads, neither advanced here**: `add-static-spectrogram-visualization` (manual validation
battery deferred by product decision).

---
_Last touched: 2026-08-21. Overwrite freely; empty is fine._
