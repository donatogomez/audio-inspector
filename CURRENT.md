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
**Focus:** nothing in flight. `add-computed-technical-properties` is merged into `main` and **archived**;
its capability specs are now canonical, so `openspec` and `git` — not this file — describe the state.

**What landed.** `averageFileBitrate` (calculated from size and duration, always `uncertain`, never
`available`, living beside `declaredBitrate`/`estimatedBitrate` without being conflated with either);
`SignalLevelMetrics` (peak, RMS, DC offset, clipped-sample count) as its own domain value type produced
by an independent operation over the shared `AudioDecoding` port, presented in the report beneath the
waveform with dBFS conversion only at the presentation layer; and the export, which carries the metrics
additively under `measurements.signalLevels` in the domain's own linear amplitude, omitting the key
entirely when there is nothing to report. `TechnicalProperties` still carries no DSP, `InspectionReport`
still carries no `SignalLevelMetrics`, and the domain still knows nothing of JSON or `schemaVersion`.
**ADR-0018 is `Accepted`** — both promotion conditions were met against production code and a manual pass
on a build whose process identity was verified rather than assumed.

**Known, deliberate debt from that change** (named at archive time, not dropped): true peak, significant
max frequency, crest factor, and any single named dynamic-range metric were all deferred with reasons —
each needs its own methodology decision under ADR-0006, not a one-line addition to this slice. A generic
`dynamicRange` field stays rejected outright, not deferred. Separately, whether `averageFileBitrate`
should generate a warning like its siblings is still open, because doing so needs a deliberate pass over
every affected fixture rather than a silent addition.

**Next step:** pick the next slice. True peak is the natural head of the deferred queue and already has
its methodology governed by ADR-0006, so it is the obvious candidate — but it needs its own OpenSpec
change before any code, per the spec-driven rule.

**Other open threads** (see `openspec list` for their real task counts, not restated here):
`add-static-spectrogram-visualization` (manual validation battery deferred by product decision) and
`add-two-file-technical-comparison` (one accessibility criterion open, blocked on a known VoiceOver
traversal gap shared with ADR-0015). Neither was touched this session.

---
_Last touched: 2026-08-11. Overwrite freely; empty is fine._
