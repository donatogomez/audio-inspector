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
**Focus: `add-loudness-measurement` — integrated loudness (LUFS-I). It is now the fifth consumer of the
one shared PCM read. Still no UI and no export.**

An inspection reads the file's samples **once**, and five analyses come out of that pass: waveform,
spectrogram, signal levels, true peak and integrated loudness. The gate that counts reads still says
**one**, and it now checks that loudness was actually produced from it rather than merely present.

**Loudness is the first consumer whose accumulator declines perfectly valid streams**, and that shaped
the wiring. An unsupported sample rate or more than two channels leaves it `unavailable` — an
**absence**, on the precedent the waveform's own already set — while the other four produce complete
models. Nothing resamples, nothing guesses a layout, and nothing fails the shared read to avoid an
absence.

It also has **no reachable failure of its own**, audited rather than assumed: every way it ends without
a value is an absence, and the one genuine failure path — a non-finite loudness — cannot be reached from
`PCMChunk`'s finite `Float`s. Recorded as a limitation, as signal levels' own `nil` already is.

**The "no second read" claim is now measured end to end.** Adding it takes the shared pass from 1.269 s
to 1.524 s at 48 kHz over ten minutes of stereo — a delta of **0.255 s** against its own 0.236 s in
isolation, so the increase *is* the DSP. The proportion holds at every rate, which an extra decode would
not. Its share is 11–17 % by container against a projected 7–12 %: over at the cheap end, inside it for
FLAC and AAC.

`SourceInspectionOutcome.inspected` now carries **five** labelled payloads. The note that preceded it
warned a fifth would be the uncomfortable one, and it stands — the container refactor is **recorded
debt** and belongs to whoever adds a sixth, deliberately not done here so one change would not hide
inside another.

ADR-0022 stays `Proposed`. Groups 1–5 and 7 closed; group 6 keeps its cross-container oracle comparison
and production negative controls.

**Next step:** group 8 — the surface. One presentation row, "Integrated loudness", one decimal, LUFS,
methodology beside it, no per-channel row, absence in the existing not-computable phrasing, and **no
verdict of any kind**. Then 8.4, the additive export field with `schemaVersion` still 1.

**Minor follow-up, not a thread:** `ImportFlowComparisonTests` has one `Task.yield()` that was never
audited in depth; same shape as the ones above, no failure ever attributed to it.

**Other open threads** (see `openspec list` for their real task counts, not restated here):
`add-static-spectrogram-visualization` (manual validation battery deferred by product decision) and
`add-two-file-technical-comparison` (one accessibility criterion open, blocked on a known VoiceOver
traversal gap shared with ADR-0015). Neither was touched this session.

---
_Last touched: 2026-08-18. Overwrite freely; empty is fine._
