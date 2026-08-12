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
**Focus:** `add-true-peak-measurement`, groups 1–6 done. **True peak is wired as a third consumer of
the shared PCM read**, which is exactly what group 5's stop rule was holding out for: it refused a
fourth *decode*, never a fourth analysis.

**What that cost, measured rather than hoped.** An inspection reads the samples **twice** — the
waveform's own read and the shared one, now feeding three analyses — and the third consumer costs its
DSP and **no decode**: the same delta in every format, where a decode would have differed by format.
The decode count is asserted at the port, not inferred from the composition's shape, and a control that
gives true peak its own decoder makes that test fail.

**One thing became provable that was not before.** True peak is the only consumer with a failure a
*valid* chunk can trigger, so the isolation case that had no input under two consumers now has one: it
fails alone, the other two settle exactly as separate reads settle on the same audio, and the read runs
to the end. The bit-exact chunk independence `add-shared-pcm-read` recorded as owed to true peak is
also paid — nine chunk sizes and whole-file, against an independent reference, no tolerance.

**Deliberately not done here.** No interface and no export: the value travels beside the report, the
waveform, the spectrogram and the signal levels, and stops at the flow state. `TruePeakMeasurement` is
untouched and `TruePeakAccumulator` changed only in visibility — four `public` keywords, to match the
two sibling accumulators; no constant, no signature and no DSP moved.

**ADR-0019 stays `Proposed`,** and wiring does not promote it: its own criteria are agreement with the
oracle demonstrated **against production code** and a manual validation on a file whose true peak
genuinely exceeds its sample peak. Neither is what this group did.

**Next step:** group 7 — presentation. The value is linear in the domain and dBTP is a presentation
unit, so the conversion, the section beneath *Signal levels*, the method stated in words, and the
forbidden-word sweep all belong there.

**Other open threads** (see `openspec list` for their real task counts, not restated here):
`add-static-spectrogram-visualization` (manual validation battery deferred by product decision) and
`add-two-file-technical-comparison` (one accessibility criterion open, blocked on a known VoiceOver
traversal gap shared with ADR-0015). Neither was touched this session.

---
_Last touched: 2026-08-12. Overwrite freely; empty is fine._
