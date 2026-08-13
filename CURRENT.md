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
**Focus:** the next thread is the **flow-state test flake**, now that finite signal level metrics are an
integrated guarantee rather than work in progress.

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

**The open thread: the flow-state suites synchronise on timing, not on a happens-before.** They deliver
an update and wait with a single `Task.yield()` for another task to apply it, so under load the
assertion can run before the state it inspects has settled. Observed intermittently in the spectrogram
and true peak suites; the signal level suite shares the pattern without having been seen to fail. It is
**pre-existing and independent of the metrics work** — deliberately left untouched there so the fix
would not ride along in an unrelated diff. Shared PCM already uses a deterministic handshake for the
same problem, which is the first candidate to reuse rather than a new helper.

**Next step:** reproduce the flake with the code intact, establish the actual happens-before before
assuming the yield is the cause, and only then replace the probabilistic synchronisation.

**Other open threads** (see `openspec list` for their real task counts, not restated here):
`add-static-spectrogram-visualization` (manual validation battery deferred by product decision) and
`add-two-file-technical-comparison` (one accessibility criterion open, blocked on a known VoiceOver
traversal gap shared with ADR-0015). Neither was touched this session.

---
_Last touched: 2026-08-13. Overwrite freely; empty is fine._
