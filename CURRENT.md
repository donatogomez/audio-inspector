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

**No thread is open.** `add-two-file-visual-comparison` is merged, archived and closed: PR
[#50](https://github.com/donatogomez/audio-inspector/pull/50) landed on `main` as a **two-parent merge
commit** `a62e021` on 2026-08-27 — first parent the previous `main` `d27933c`, second parent the branch
head `890f8cc` — **ADR-0025 is `Accepted` (2026-08-27)**, and the change is archived at
`openspec/changes/archive/2026-08-27-add-two-file-visual-comparison/`, which created the
`audio-two-file-visual-presentation` capability with 11 requirements and 38 scenarios. The eight
pre-existing capabilities are byte-identical.

Two files' waveforms and spectrograms now sit side by side on shared axes — time by real duration,
frequency by Nyquist — reusing what the second file's single read already produced. Nothing is computed
and nothing is read twice. The paired drawings **stand in for** the single ones rather than joining them,
so each file appears once. Past a file's own audio and above its own Nyquist are two different facts
with two different sentences, and neither is drawn as silence or as the ramp's floor. There is no visual
outcome: nothing says the two are the same, different, similar or matching.

Post-merge baseline on `main`: boundaries, the zero-warnings build, `xcodebuild`, **`swift test` twice
at 1628 tests in 181 suites**, `openspec validate --all --strict` 11/11 and `git diff --check`, all
green.

**Named follow-ups, deferred by decision and not started** — group 12 of the archived change:

- **evidence comparison** — alignment, gain matching, residual, correlation, spectral difference; every
  step a heuristic with a threshold. What it will need is retained; nothing authorises it;
- **Findings** — same master, remaster, transcode, upsample, lossy source, quality, provenance. This
  feature is a **producer of pictures for a reader**, never a small version of that capability;
- **comparison export** — `schemaVersion` 1 describes one file; a paired document is a kind of its own;
- **synchronised inspection** — cursors, zoom, scrubbing, linked scrolling; a synchronised cursor needs
  an alignment decision that belongs to evidence comparison;
- **more than two files** — everything is stated for a pair, and a third would reopen the lifetime
  decision and the memory figures first.

**One cosmetic defect stands, reported and not fixed.** In the paired waveform section, text overlaps
vertically — the amplitude line against the second file's attribution, and the *no audio beyond here*
sentence against the second lane's amplitude line. The maintainer saw it during the manual pass,
answered all four questions unambiguously in spite of it, and it contradicts no promotion condition.
**Fixing it is its own thread**, and it wants its own look at the surface afterwards.

**Inherited debt, untouched by any of this.** `add-two-file-technical-comparison` is still open and
**ADR-0017 is still `Proposed`** — its own manual condition is unmet. **ADR-0016 is still `Proposed`**:
its format matrix and its own manual validation belong to a different change. The paired drawings live
in the same scrolling area every other analysis lives in and **inherit** the VoiceOver traversal gap
those two share with ADR-0015, rather than fixing or worsening it.

**Also open, and not advanced here**: `add-static-spectrogram-visualization` (manual validation battery
deferred by product decision).

---
_Last touched: 2026-08-27. Overwrite freely; empty is fine._
