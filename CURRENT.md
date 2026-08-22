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

**Open thread: `add-two-file-measurement-comparison` — done and validated; waiting on publication.**
**ADR-0024 is `Accepted` (2026-08-22).**

**Focus.** The measurement comparison is built, validated against production on real files, and on
screen beneath the technical rows. A person ran the seven-pair battery against the real application on
2026-08-22 — on a build postdating the surviving-value fix — and reported no blocking defect. That
observation was the ADR's last outstanding condition, and it is recorded verbatim in
`docs/manual-validation-mvp.md`.

**Next step: push, PR, merge — then `openspec archive`, and only then.** The archive is post-merge by
task 8.2's own words and has not run. Nothing else in this change is outstanding.

**What was deliberately left out, and stays out**: comparison export (a comparison document is a kind of
its own, ADR-0017 §9), visual comparison, evidence comparison, and Findings. They are group 7's named
follow-ups, not omissions.

**One cosmetic finding stands, reported and not fixed**: the channel-mismatch note repeats verbatim in
three blocks. The operator classified it as redundant but non-blocking, and turning a validation pass
into production work was refused.

**What no one has seen, and it is written down rather than assumed**: light, dark and window resizing
were not reported in this pass; there is no VoiceOver observation; and `incomparable(.methodsDiffer)` is
a state **no pair of real files can produce** — production runs one true peak method, one bandwidth
identity and one loudness algorithm with only the two allow-listed weightings — so it is pinned in the
domain and presentation suites and named as an exclusion in the battery.

**Inherited, and not fixed by this**: `add-two-file-technical-comparison` is still open at 52/58 and
**ADR-0017 is still `Proposed`**, blocked on its own manual condition and on the VoiceOver traversal gap
shared with ADR-0015. This change extends that surface and inherits the gap; nothing here discharges it.

**Older threads, neither advanced here**: `add-static-spectrogram-visualization` (manual validation
battery deferred by product decision).

---
_Last touched: 2026-08-22. Overwrite freely; empty is fine._
