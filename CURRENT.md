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
**Focus:** `add-computed-technical-properties`, group 5 — presenting `SignalLevelMetrics`. A new
presentation vocabulary, `SignalLevelMetricsPresentation`/`SignalLevelMetricsCopy`
(`Sources/FeatureAnalysis/SignalLevelMetricsPresentation.swift`), mirrors `WaveformPresentation`/
`SpectrogramPresentation` exactly (`loading`/`metrics`/`absent`/`failed`, no `cancelled`), with one
stated structural difference: the content here **is** words, so `.metrics` produces four independent,
accessible rows rather than one section-level sentence standing in for a picture. Peak and RMS read in
dBFS via a new `HumanFormat.decibelsFullScale`, reusing `Spectrogram.floorDecibels` for exact silence so
`log10(0)`'s mathematical `-∞` never reaches a reader; DC offset is linear and signed
(`HumanFormat.linearOffset`, four decimal places); clipped-sample count is a grouped plain integer. Wired
into `ReportView` directly beneath the waveform (both concern amplitude/level; the spectrogram, which
concerns frequency, follows both) via a new, total `RootView.signalLevelMetricsPresentation(for:)`. The
domain model is untouched — every conversion lives in `HumanFormat`, never inline in a view body. Group
5's three tasks (5.1–5.3) are closed; 5.3 needed no code, since group 2 had already satisfied it. All six
gates are green; 850 tests, up from 821.

**What the presentation is careful not to collapse.** A channel with no samples reports "Not computable"
for peak/RMS/DC offset — never a fabricated zero, never a bare unexplained dash — while a channel that
was measured and is genuinely silent reports the real, floored value; the clipped-sample count has no
such state, since counting is always defined. Two negative controls confirmed this is actually enforced,
not merely written: converting "not computable" to a fabricated zero, and formatting peak/RMS as raw
linear values instead of dBFS, each broke exactly the tests written to catch it. Both fully reverted.

**Why this stopped here, not further.** Group 6 (export — the JSON `measurements` object) is untouched by
design: this session's own scope was group 5 only, and nothing here changes `InspectionReport`, the
`schemaVersion` 1 export, or any warning. ADR-0018 stays `Proposed` — its own promotion criterion is
implementing at least `averageFileBitrate` against production code **and** manual validation, and neither
this group nor the change as a whole has done the manual validation half yet.

**Next step:** group 6 — add `averageFileBitrate` to the exported `technicalProperties` object
(additive, no `schemaVersion` bump) and `SignalLevelMetrics` under the schema's already-anticipated,
still-unused `measurements` object; confirm the export stays byte-identical for a report without either,
following the isolation-test pattern already established for the waveform and the spectrogram.

**Other open threads** (see `openspec list` for their real task counts, not restated here):
`add-static-spectrogram-visualization` (manual validation battery deferred by product decision) and
`add-two-file-technical-comparison` (one accessibility criterion open, blocked on a known VoiceOver
traversal gap shared with ADR-0015). Neither was touched this session.

---
_Last touched: 2026-08-10. Overwrite freely; empty is fine._
