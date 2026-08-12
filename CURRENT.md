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
**Focus:** `add-true-peak-measurement`, groups 1–5 done and **group 6 no longer blocked.**

**What unblocked it.** Group 5's stop rule refused a fourth *read* of the file, not a fourth consumer,
and said this group resumes once a PCM-sharing change lands. It has: shared PCM is merged, archived,
and its capability is in the canonical specs, so `SharedPCMAnalysisGeneration` now exists here as
ordinary `main` code. **ADR-0020** is `Accepted` — *independent analyses* is the invariant,
*independent decodes* was only the implementation ADR-0016 chose while a decode looked free.

**What group 6 now is, and what its own text still says.** True peak becomes a **third consumer of the
shared read** — one more accumulator folded from the pass that already exists, costing its own DSP and
**no additional decode**. The tasks below it were written before that decision and still describe a
fourth operation with its own decoder instance; that wording is superseded by ADR-0020 and gets revised
when the group is actually started. **Nothing in it is started and nothing in it is marked.**

**What must not happen while wiring it.** `TruePeakMeasurement`, `TruePeakAccumulator`, the methodology
and their tests are finished and are **not** redesigned. If wiring true peak ever required changing the
accumulator, that is evidence the shared architecture is wrong, and it has to be justified before
proceeding rather than absorbed. **ADR-0019 stays `Proposed`**: its promotion needs the oracle agreement
and a manual validation of the surface, neither of which this wiring supplies.

**Next step:** group 6 — wire true peak as the third consumer, keeping every independence property the
other two already prove: one consumer's failure leaves the others untouched, a producer failure ends
each with its own outcome, and cancellation cancels everything without letting a partial model escape.

**Other open threads** (see `openspec list` for their real task counts, not restated here):
`add-static-spectrogram-visualization` (manual validation battery deferred by product decision) and
`add-two-file-technical-comparison` (one accessibility criterion open, blocked on a known VoiceOver
traversal gap shared with ADR-0015). Neither was touched this session.

---
_Last touched: 2026-08-12. Overwrite freely; empty is fine._
