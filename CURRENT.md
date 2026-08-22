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

**No thread is open.** `add-two-file-measurement-comparison` is merged, archived and closed:
PR [#49](https://github.com/donatogomez/audio-inspector/pull/49) landed on `main` as merge commit
`63e8f2a` on 2026-08-22, **ADR-0024 is `Accepted` (2026-08-22)**, and the change is archived at
`openspec/changes/archive/2026-08-22-add-two-file-measurement-comparison/`, which created the
`audio-two-file-comparison` capability with five requirements.

Two files' measurements now compare beneath the technical rows — signal levels, true peak, integrated
loudness and programme bandwidth — reusing what the second file's single shared read already measured.
Only loudness carries a difference, in LU. Bandwidth speaks about the grid rather than the files. An
absence is words, never a zero, and the side that measured keeps its figure.

**Named follow-ups, deferred by decision and not started** — group 7 of the archived change:

- **comparison export** — `schemaVersion` 1 describes one file; a comparison document is a kind of its
  own (ADR-0017 §9);
- **visual comparison** — waveforms and spectrograms side by side (`add-two-file-visual-comparison`);
- **evidence comparison** — alignment, gain matching, residual, correlation, spectral difference; every
  step is a heuristic with a threshold;
- **Findings** — same master, remaster, transcode, upsample, lossy source, dynamics, quality,
  provenance. This feature is a **producer of facts** for that capability, never a small version of it.

**Inherited debt, untouched by any of this.** `add-two-file-technical-comparison` is still open at 52/58
and **ADR-0017 is still `Proposed`** — its own manual condition is unmet and it carries the VoiceOver
traversal gap it shares with ADR-0015. The measurement sub-section lives in the same scrolling area and
inherits that gap rather than fixing or worsening it.

**One cosmetic finding stands, reported and non-blocking**: the channel-mismatch note repeats verbatim
in three blocks. The maintainer saw it during the manual pass and classified it as redundant but not a
defect.

**Also open, and not advanced here**: `add-static-spectrogram-visualization` (73/89, manual validation
battery deferred by product decision).

---
_Last touched: 2026-08-22. Overwrite freely; empty is fine._
