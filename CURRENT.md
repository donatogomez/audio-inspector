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
**Focus:** `add-computed-technical-properties`, group 6 — exporting `SignalLevelMetrics`. A new,
additive `measurements.signalLevels` object joins `schemaVersion` 1
(`Sources/AudioInspectorApp/Export/ReportJSONDTO.swift`), holding exactly the domain model's own public
surface (overall + per-channel peak/RMS/DC offset/clipped-sample count, plus `sampleCount`) in the
domain's own **linear** amplitude — never dBFS, which stays a presentation-only concern. `nil` metrics
means the `measurements` key is **omitted entirely**, not `null`, so a report exported without signal
level metrics is byte-identical to the pre-group-6 output. `SignalLevelMetrics?` is threaded end to end —
`ReportExporting` → `JSONReportExporter` → `ReportExportCoordinator` → `ReportExportAction` →
`ReportExportModel` → `ReportView`'s own export button — with `ReportView` as the single point that
collapses `loading`/`unavailable`/`failed`/cancelled to `nil` before the export layer ever sees them.
`InspectionReport` and `AudioInspectorDomain` are untouched; folding `SignalLevelMetrics` into
`InspectionReport` was never implemented. `averageFileBitrate`'s own export (6.1) turned out to already
be done since group 2 — confirmed by audit and existing tests, not re-implemented. Group 6's three tasks
(6.1–6.3) are closed. All six gates are green; 868 tests, up from 850.

**What the export is careful not to collapse or invent.** "Not computable" (zero frames) is a present
key with an explicit `null`, never an omitted key and never a fabricated `0`; a genuinely measured,
computed zero (real silence) exports as a real `0`, never `null`. A sample beyond full scale exports
exactly as measured, never clamped. No clipping threshold is exported — audited and declined: it is an
analysis-engine constant with no wire-version convention yet to anchor it to, not part of
`SignalLevelMetrics`'s own public surface. Two negative controls confirmed the isolation is actually
enforced: putting a DSP key directly into `technicalProperties`, and exporting peak/RMS in dBFS instead
of the domain's linear value (which also surfaced `log10(0)`'s `-∞` failing the encoder outright, as it
should). Both broke exactly the tests written to catch them, and both were fully reverted.

**Why this stopped here, not further.** Nothing in group 7 (deferred properties — true peak, significant
max frequency, crest factor, dynamic range) was started; each stays named and deferred with its own
reason, unchanged from the original design. ADR-0018 stays `Proposed` — its own promotion criterion is
implementing at least `averageFileBitrate` against production code **and** manual validation, and the
manual-validation half still hasn't happened.

**Next step:** group 8 — the four gates (already green throughout this session, but not yet re-run as
group 8's own closing act) plus 8.2 (confirm `averageFileBitrate` never becomes `.available` in any test,
and that `SignalLevelMetrics` never gains a `Codable` conformance that could let it leak into an
unrelated export path) and 8.3 (decide ADR-0018's status from what was actually implemented, update
`CURRENT.md`, archive through `openspec archive` after merge). This is very likely the change's own
last group.

**Other open threads** (see `openspec list` for their real task counts, not restated here):
`add-static-spectrogram-visualization` (manual validation battery deferred by product decision) and
`add-two-file-technical-comparison` (one accessibility criterion open, blocked on a known VoiceOver
traversal gap shared with ADR-0015). Neither was touched this session.

---
_Last touched: 2026-08-10. Overwrite freely; empty is fine._
