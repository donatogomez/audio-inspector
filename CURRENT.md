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
**Focus:** nothing is in flight. The three properties below are integrated; the open threads are named
at the end.

**An inspection reads a file's samples once.** One shared pass decodes the file and hands the same
chunks to the waveform, the spectrogram, the signal level metrics and the true peak, each keeping its
own accumulation, its own failure and its own reported outcome. The report is still produced from
metadata alone and emitted before any sample is read. The envelope is **identical** to the one the
waveform's own read produced — exactly, for every container measured, including a lossy one — and no
domain type, port or reduction rule changed to get there.

A consumer's failure stays its own and the read outlives it; a producer's failure ends every unfinished
consumer, each on its own terms; cancellation is global; an absence stays distinct from a failure; and
nothing partial escapes. Measured on ten minutes of stereo, a compressed inspection is 15–27 % faster
and memory does not grow with duration.

**The known consequence:** the waveform now becomes visible **0.8–1.3 s later**, because it settles when
the one read finishes rather than after a read of its own. The report is unaffected at ~1–2 ms, no
specification requires the waveform before the other analyses, and progressive delivery inside the
shared pass was deliberately not designed — it would reopen a callback contract ADR-0020 closed, and
that is a product judgement. Recorded in ADR-0021, which is `Accepted`.

**`AVFoundationWaveformGenerator` survives with no production consumer, on purpose**: it is the
independent implementation the equivalence tests compare against, and a source-level gate fails if any
production target so much as names a waveform-reading port.

**Also integrated, so not threads:** `SignalLevelMetrics` cannot publish a value that is not a number,
and the flow-state test suites synchronise on a happens-before instead of a `Task.yield()`.

**Minor follow-up, not a thread:** `ImportFlowComparisonTests` has one `Task.yield()` that was never
audited in depth; same shape as the ones above, no failure ever attributed to it.

**Other open threads** (see `openspec list` for their real task counts, not restated here):
`add-static-spectrogram-visualization` (manual validation battery deferred by product decision) and
`add-two-file-technical-comparison` (one accessibility criterion open, blocked on a known VoiceOver
traversal gap shared with ADR-0015). Neither was touched this session.

---
_Last touched: 2026-08-17. Overwrite freely; empty is fine._
