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
**Focus:** `add-shared-pcm-read`, groups 1–4 done. **One read feeds both analyses, the isolation that
read has to preserve is proved rather than argued, and the saving is now measured against production
code rather than against a spike's harness.**

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

**What group 4 measured, and what it refused to claim.** The saving reproduces against the real
coordinator and the real adapters: one redundant decode was removed and one decode's worth of time
disappeared, in every format and in both build configurations. Several cells recover slightly *more*
than 100 % of a decode; that is measurement spread and is written down as spread, not banked as a
second decode that was never removed. The results are identical value for value to the pre-change
ones on real files, the report still arrives first, and the footprint barely moves when the audio
grows ten-fold. **The stop rule did not fire, so the architecture stands on evidence rather than on
the spike having liked it.** Numbers live in the spike's §15, appended beside §§1–14 rather than over
them; the harness was temporary and is deleted.

**ADR-0020 is now `Accepted`** — its two stated conditions are met, and its `Promotion` section
records the one respect in which the evidence is weaker than promised: the "no consumer starves
another" property has no reachable input today, so it stays contract text rather than a test.

**Next step:** group 5 — the four gates plus the Xcode build on a confirmed-fresh process, then manual
validation that a real compressed file still produces the same report, waveform, spectrogram and
signal levels, visibly sooner. **Do not archive before merge.**

**Other open threads** (see `openspec list` for their real task counts, not restated here):
`add-static-spectrogram-visualization` (manual validation battery deferred by product decision) and
`add-two-file-technical-comparison` (one accessibility criterion open, blocked on a known VoiceOver
traversal gap shared with ADR-0015). Neither was touched this session.

---
_Last touched: 2026-08-12. Overwrite freely; empty is fine._
