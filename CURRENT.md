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
**Focus:** nothing is in flight. The two guarantees below are integrated; the candidate next thread is
named at the end.

**What just landed, stated as a property rather than as history.** `SignalLevelMetrics` cannot publish a
value that is not a number. Every reduction is widened to `Double` *before* it is accumulated, so no
intermediate can overflow on the way to a result that was always representable — the mean and the RMS
are bounded by the largest magnitude in the input. The domain model refuses non-finite values outright,
as its two sibling value types already did, and a result that genuinely could not be described reaches
the **existing `failed` outcome** rather than a new state or a substituted number. Nothing is clamped,
and amplitudes beyond full scale are still reported, because that is a real fact about a file. The
export and `schemaVersion` 1 are semantically unchanged: the same fields, the same bytes, now
guaranteed to be numbers. Its change is merged and archived; the finiteness guarantee lives in the
`audio-signal-level-metrics` capability.

**The flow-state suites now synchronise on a happens-before rather than on timing.** They used to
release an update and wait one `Task.yield()` for another task to apply it, which guarantees nothing:
resuming a continuation makes the other task *runnable*, not *run*. The scripted actions complete the
round trip instead — `deliver` returns only once the handler has actually been called — reusing the
continuation handshake those same test classes already had. **Production was not touched**, and the
argument for the fix is a negative control rather than a count of green runs: with the acknowledgement
removed the affected tests fail, and with an extra scheduling hop inside the producer the handshake
still passes where the yield fails deterministically. That debt is closed.

**Next step (candidate, not yet decided):** whether the waveform can stop decoding the file a second
time and become a fourth consumer of the shared PCM read. It is the last redundant decode per
inspection. ADR-0016 declined this once, so the first move is reading what it actually decided and
against what evidence — not implementing.

**Minor follow-up, not a thread:** `ImportFlowComparisonTests` has one `Task.yield()` that was never
audited in depth; same shape as the ones above, no failure ever attributed to it.

**Other open threads** (see `openspec list` for their real task counts, not restated here):
`add-static-spectrogram-visualization` (manual validation battery deferred by product decision) and
`add-two-file-technical-comparison` (one accessibility criterion open, blocked on a known VoiceOver
traversal gap shared with ADR-0015). Neither was touched this session.

---
_Last touched: 2026-08-13. Overwrite freely; empty is fine._
