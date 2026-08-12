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
**Focus:** `add-shared-pcm-read`, groups 1–3 done. **One read feeds both analyses, and the isolation
that read has to preserve is now proved rather than argued.**

> **This branch carries only the shared-PCM thread.** `add-true-peak-measurement` is a separate, active
> thread on its own branch: its change, **ADR-0019**, `TruePeakMeasurement`, `TruePeakAccumulator` and
> their tests are **not here**, so `openspec list` and `docs/adr/` on this branch will not show them,
> and the ADR index has a gap where 0019 will land. It stays blocked until this change merges.

**What group 3 established, and what it deliberately did not.** The composition needed **no change** —
no defect was found — so this was almost entirely tests. A consumer that fails leaves the other's whole
outcome identical to a control run where nothing failed, and the read still runs to the end, counted at
the port. A producer failure is tested with a *different* fixture that fails after real audio has been
accumulated, so "no partial model escapes" is a claim about state that actually existed.

**Cancellation is deterministic now.** A scripted decoder suspends inside the read at a chosen chunk,
signals that it has arrived, and continues only once released — so the test cancels while the read is
provably mid-flight. No sleep, no polling, no `Task.yield()`. The racy test written earlier was deleted
rather than tuned; this replaces it.

**One asymmetry still worth knowing.** Only the spectrogram has a failure a valid stream can trigger, so
the mirror isolation case has no input. That is pinned as a test that starts failing the day
`SignalLevelMetricsAccumulator` gains a second failure mode — which is the moment symmetric coverage
becomes owed.

**Four superseded tests were removed, not left beside their replacements.** One of them compared the
shared read at chunk size *N* against separate reads at 4 096, which conflates "sharing changed
something" with "chunking changed something"; every chunk-size comparison now feeds both sides the
identical sequence, which is what lets it assert full equality with no tolerance.

**Next step:** group 4 — re-measure the saving against production code in the spike's own form, with the
instruction it already carries: if it does not reproduce, stop and record the difference rather than
keep the architecture because the spike liked it.

**ADR-0020 stays `Proposed`.** Its promotion needs *both* halves — the isolation demonstrated by tests
that fail when the property breaks, which group 3 has now done, **and** the saving reproduced against
production code, which is group 4's.

**Other open threads** (see `openspec list` for their real task counts, not restated here):
`add-static-spectrogram-visualization` (manual validation battery deferred by product decision) and
`add-two-file-technical-comparison` (one accessibility criterion open, blocked on a known VoiceOver
traversal gap shared with ADR-0015). Neither was touched this session.

---
_Last touched: 2026-08-12. Overwrite freely; empty is fine._
