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
**Focus:** `add-computed-technical-properties`, group 4 — wiring `SignalLevelMetrics` into the flow.
`SignalLevelMetricsGeneration` (decode → accumulate → finish) mirrors `SpectrogramGeneration` exactly,
and is wired into `SourceInspectionCoordinator` as a **third independent operation** over the shared
`AudioDecoding` port, with its own decoder instance and its own cancellation — never coupled to the
waveform's own, deliberately un-migrated generator. Wiring this in required extending
`SourceInspectionOutcome.inspected`/`InspectionUpdate` with a fourth case, exactly as the spectrogram's
own was added beside the waveform's — a mechanical ripple across `ImportFlowModel` and ~13 test files,
not new design. Independence from the waveform and the spectrogram (delay, blocking, cancellation,
failure) is demonstrated with real tests, not assumed, and confirmed with two negative controls (breaking
the wiring; artificially sharing the waveform's result), both run and fully reverted. Group 4's two tasks
(4.1, 4.2) are closed. All four gates are green; 821 tests, up from 791.

**Why this stopped here, not further.** Group 5 (presentation — words, units, dBFS conversion, no
verdict) and group 6 (export — the JSON `measurements` object) are both untouched by design: this
session's own scope was group 4 only, and `SignalLevelMetricsState` reaching `InspectionPresentation`
is flow-state plumbing, not presentation. ADR-0018 stays `Proposed` — its own promotion criterion is
implementing at least `averageFileBitrate` against production code **and** manual validation, and neither
this group nor the change as a whole has done the manual validation half yet.

**Next step:** group 5 — present peak, DC offset, RMS and clipping in words with explicit units (dBFS for
peak/RMS reusing the spectrogram's −120 dBFS floor, linear for DC offset, a plain integer for clipping),
no colour-only meaning, no verdict, and give `averageFileBitrate` a label distinguishing it from
`declaredBitrate`/`estimatedBitrate`. Do not start group 6 (export) before group 5 is done and reviewed.

**Other open threads** (see `openspec list` for their real task counts, not restated here):
`add-static-spectrogram-visualization` (manual validation battery deferred by product decision) and
`add-two-file-technical-comparison` (one accessibility criterion open, blocked on a known VoiceOver
traversal gap shared with ADR-0015). Neither was touched this session.

---
_Last touched: 2026-08-10. Overwrite freely; empty is fine._
