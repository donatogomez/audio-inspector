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
**Focus:** `add-computed-technical-properties` is implementation-complete and closing, on
`feature/add-signal-level-metrics-generation`, not yet merged. Every capability the change set out to
build exists end to end: `averageFileBitrate` (calculated, always `uncertain`, coexisting with
`declaredBitrate`/`estimatedBitrate` as three distinct claims about a rate) is threaded from the
property reader through the domain, the report's own presentation, and the `schemaVersion` 1 export.
`SignalLevelMetrics` (peak, RMS, DC offset, clipped-sample count — overall and per channel) is produced
by a third, independent operation over the shared `AudioDecoding` port, presented in the report as its
own section directly beneath the waveform (linear values converted to dBFS only at that presentation
layer, never earlier), and exported additively under `measurements.signalLevels` in the domain's own
linear amplitude — never dBFS on the wire. `TechnicalProperties` carries no DSP; `InspectionReport`
carries no `SignalLevelMetrics`; the domain knows nothing of JSON or `schemaVersion`. Groups 1–6 are all
closed (25 of 32 tasks); group 7's four properties (true peak, significant max frequency, crest factor,
generic dynamic range) remain deliberately deferred and named, not implemented. Group 8: 8.1 and 8.2 are
closed; 8.3 is split — the ADR decision and this snapshot are done, `openspec archive` is not (see below).

**A real defect was found and fixed while closing, not just confirmed.** An `allAvailableProperties()`
test fixture set `averageFileBitrate` to `.available`, a state production code has no path to produce
(ADR-0018 makes it structurally `.uncertain`-only). Fixed to `.uncertain`; all 868 tests still pass,
proving nothing depended on the wrong state. A repository-wide search now confirms `averageFileBitrate`
is `.available` nowhere, and that `SignalLevelMetrics` carries no `Codable` conformance anywhere.

**ADR-0018 stays `Proposed`.** Its own promotion criterion is two-part: `averageFileBitrate` implemented
against production code (done), **and** this change's own manual validation (not done). No session in
this change has opened the real app and looked at the signal-levels surface, or exported a real JSON and
read it, with a person's own eyes — the same standard already applied to ADR-0016/ADR-0017 in this
project, never satisfied by test coverage alone. That observation is the one thing left before this ADR
can be promoted.

**Next step:** a person runs the real app — inspects a real file, looks at the "Signal levels" section
on screen, exports the JSON and reads it — then ADR-0018 can be promoted and 8.3 fully closed. After
that: this branch gets reviewed and merged, and only then does `openspec archive` run. Nothing in this
session pushed, opened a PR, or archived.

**Other open threads** (see `openspec list` for their real task counts, not restated here):
`add-static-spectrogram-visualization` (manual validation battery deferred by product decision) and
`add-two-file-technical-comparison` (one accessibility criterion open, blocked on a known VoiceOver
traversal gap shared with ADR-0015). Neither was touched this session.

---
_Last touched: 2026-08-11. Overwrite freely; empty is fine._
