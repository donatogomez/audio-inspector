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

**One thread is open: `add-two-file-visual-comparison`, ready for a PR and not yet opened.** Two files'
waveforms and spectrograms now sit side by side on shared axes, reusing what the second file's single
read already produced — nothing is computed, nothing is read twice, and the paired drawings stand in for
the single ones rather than joining them.

**ADR-0025 is `Accepted` (2026-08-27)**, promoted on its own three conditions: reuse counted through the
real decoder, unmixability with each direction failing when its guard is removed, and the two axis
properties **the maintainer observed in person** on a build launched by its executable path with a fresh
window confirmed. What the promotion does not cover is written into the record rather than left implicit.

**The next step is to open the PR**, then merge, then archive through the CLI — in that order and never
before the merge. That is the only part of the change's last group still outstanding.

**One cosmetic defect stands, reported and deliberately not fixed**: in the paired waveform section,
text overlaps vertically — the amplitude line against the second file's attribution, and the
*no audio beyond here* sentence against the second lane's amplitude line. It was seen during the manual
pass and answered none of the four questions differently, so it was left alone rather than turned into
production work inside a validation pass. **Fixing it is its own thread**, and it wants its own look at
the surface afterwards.

**Inherited debt, untouched by any of this.** `add-two-file-technical-comparison` is still open and
**ADR-0017 is still `Proposed`** — its own manual condition is unmet, and it carries the VoiceOver
traversal gap it shares with ADR-0015 and ADR-0016. The paired drawings live in the same scrolling area
and inherit that gap rather than fixing or worsening it. **ADR-0016 is still `Proposed`** too: its
format matrix and its own manual validation belong to a different change, and nothing here discharges
them.

**Also open, and not advanced here**: `add-static-spectrogram-visualization` (manual validation battery
deferred by product decision).

---
_Last touched: 2026-08-27. Overwrite freely; empty is fine._
