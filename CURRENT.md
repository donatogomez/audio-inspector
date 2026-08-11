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
**Focus:** designing **true peak** — the contract only. `add-true-peak-measurement` is open with its
proposal, design, task list and delta spec on `audio-signal-level-metrics`, plus **ADR-0019** in
`Proposed`. **No DSP, no `Sources/`, no tests: only group 1 is done, deliberately**, exactly as the
previous change began. The preceding slice (`add-computed-technical-properties`) is merged and archived;
its capability specs are canonical, so `openspec` and `git` — not this file — describe the state.

**Why the design took a whole session before any code.** ADR-0006 fixes the methodology (BS.1770/R128,
oversampling ≥ 4× before peak detection, the factor and filter recorded with the result, Accelerate in
`AudioInspectorAnalysis`, FFmpeg `ebur128` as the cross-check oracle) but leaves six things genuinely
open — the factor above 48 kHz, the interpolation filter, edge handling, arithmetic width, the
cross-check tolerance, and whether that oracle can run in CI at all. All six are named as decisions with
their criteria and handed to a spike; none is chosen by assumption. Two structural questions ADR-0006
does not answer are what **ADR-0019** records: a measurement that carries its own methodology (the first
in this project), and a positive true peak reported as a **value rather than a flag** — narrowing that
ADR's own "inter-sample clipping is flagged" sentence, because a flag is an inference and inferences
here carry evidence, alternatives and confidence.

**The two decisions most likely to be revisited later, so they are written down.** True peak becomes a
**sibling** value type, never a field of `SignalLevelMetrics` — that type is sample-level facts by its
own definition and has nowhere to put a method. And it is produced by a **fourth** independent operation
over the shared decoding port, per ADR-0016's own rule; the cost of a fourth full decode is measured
before it is accepted, with a stop rule written in advance that opens a separate deduplication change
rather than quietly folding operations together.

**What is already in `main` and stays untouched by this change:** the calculated bitrate and
`SignalLevelMetrics` (sample peak, RMS, DC offset, clipped-sample count), each produced by its own
independent operation and exported additively under `measurements`. `clippedSampleCount` keeps meaning
exactly what it means today — the true peak is a **separate** fact, and proving that independence is a
task group of its own.

**Next step:** the methodology spike (group 2 of the new change) — pin the interpolation filter, the
oversampling factor per sample rate, edge handling and the cross-check tolerance against FFmpeg
`ebur128`, then write the spike report. Nothing in `Sources/` moves before that spike produces numbers.

**Known, deliberate debt** (unchanged, named rather than dropped): significant max frequency, crest
factor, and any single named dynamic-range metric all still wait on their own methodology decisions
under ADR-0006; a generic `dynamicRange` field stays rejected outright. Whether `averageFileBitrate`
should generate a warning like its siblings is still open, because it needs a deliberate pass over every
affected fixture rather than a silent addition.

**Other open threads** (see `openspec list` for their real task counts, not restated here):
`add-static-spectrogram-visualization` (manual validation battery deferred by product decision) and
`add-two-file-technical-comparison` (one accessibility criterion open, blocked on a known VoiceOver
traversal gap shared with ADR-0015). Neither was touched this session.

---
_Last touched: 2026-08-11. Overwrite freely; empty is fine._
