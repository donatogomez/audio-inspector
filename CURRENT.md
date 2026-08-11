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
**Focus:** `add-computed-technical-properties` is implementation-complete and validated, on
`feature/add-signal-level-metrics-generation`, **not yet merged**. All 32 tasks are settled: 28 done,
4 (group 7 — true peak, significant max frequency, crest factor, generic dynamic range) deliberately
deferred and named, not implemented. **ADR-0018 is now `Accepted`.**

**The apparent export defect from the previous session was investigated under live instrumentation and
found to be a false negative, not a code defect.** A trace at every seam from `ReportView`'s export
button through to `JSONReportExporter` showed the real `SignalLevelMetrics` reaching every step,
including the `.toolbar` button the earlier session suspected — that hypothesis is disconfirmed. The
actual cause: a stale, unkillable `AudioInspector` process from an earlier Xcode run was still alive in
the background, and `open` (used to launch the build in the prior session) activates an already-running
instance rather than starting a new one — the prior manual pass almost certainly validated a stale build,
not this change's own code. Full account in `docs/manual-validation-mvp.md`, "Signal level metrics —
resolved: a stale app instance, not a code defect." All instrumentation was reverted before any commit.

**The real validation was then repeated on a confirmed-fresh process instance, twice, and passed both
times**: the on-screen `Signal levels` surface and the real exported `measurements.signalLevels` JSON
both correct — linear values (never dBFS), `averageFileBitrate` under its own key, no absolute paths, no
UI-only state, reproducible byte-for-byte except `generatedAt`. One thing was added and kept:
`EndToEndFlowTests.theRealSignalLevelMetricsPathReachesTheExportedDocument`, which closes the real gap
this whole investigation started from — no test previously drove the production export path with
genuine, non-`nil` signal level metrics. A negative control confirmed the new test actually
discriminates, then was reverted.

**Every capability is implemented, threaded end to end, and now manually confirmed**:
`averageFileBitrate` (calculated, always `uncertain`, coexisting with `declaredBitrate`/
`estimatedBitrate`); `SignalLevelMetrics` (peak, RMS, DC offset, clipped-sample count) produced by its
own independent operation, presented in the report beneath the waveform (dBFS only at the presentation
layer), and exported additively under `measurements.signalLevels` in the domain's own linear amplitude.
`TechnicalProperties` carries no DSP; `InspectionReport` carries no `SignalLevelMetrics`; the domain
knows nothing of JSON or `schemaVersion`. All six gates green (boundaries, build, `swift test` × 2 —
869 tests — `xcodebuild` Debug, OpenSpec strict, `git diff --check`).

**Next step:** this branch is ready for review and merge. Only after merge does `openspec archive` run.
Nothing in this session pushed, opened a PR, or archived.

**Other open threads** (see `openspec list` for their real task counts, not restated here):
`add-static-spectrogram-visualization` (manual validation battery deferred by product decision) and
`add-two-file-technical-comparison` (one accessibility criterion open, blocked on a known VoiceOver
traversal gap shared with ADR-0015). Neither was touched this session.

---
_Last touched: 2026-08-11. Overwrite freely; empty is fine._
