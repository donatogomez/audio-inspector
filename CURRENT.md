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
**Focus: `add-loudness-measurement` — the implementation is complete and **validated against the
documents by the product itself**. What remains is manual validation, the ADR, and publication.**

Group 6 is closed. The change of subject is the whole of it: the published targets were already met by
`LoudnessAccumulator`, and they are now met by the **path** — a real file through
`AVFoundationAudioDecoder` and `SharedPCMAnalysisGeneration`, the composition the app itself runs.

**The distinction cost nothing, which is the finding.** Production and the accumulator agree to better
than **1e-9 LU** on every published vector, so the file round-trip and the shared read are transparent —
and that is what lets the accumulator-level intermediates (the derived threshold, the block set, the
chunk-independence matrix) count as evidence about the product rather than about one type.

Worst deviation from the documents, through production: **0.0213 LU** on Tech 3341 test 5, and
**0.00028 LU** on both BS.1770-5 anchors, against a published ±0.1. Tests 3 and 4 read *identically*,
which is what a missing absolute gate would break.

**The rate sweep produced the one genuinely new result.** At 48 kHz production and FFmpeg agree to
**0.0071 LU**. Above it they do not — 0.031 at 96 kHz, 0.042 at 192 — and the measurement locates the
movement: **FFmpeg's** reading drifts 0.030 LU away from the published −23.0 as the rate rises, while
production's own spread is **0.0065 LU** and it stays within 0.0122 of the document everywhere. That is
ADR-0022 §3's gap appearing as a number: BS.1770-5 publishes coefficients for 48 kHz only, so above it
two implementations run two different derivations and disagreement is not evidence against either. **No
cross-rate agreement bound is claimed against the oracle**; production is asserted against the document
instead.

**Containers separate codec from meter rather than assuming it.** Five lossless containers agree to
**1.4e-5 LU**; AAC moves **6.7e-4** — fifty times the lossless spread, which is what identifies it as
the encoder — and production agrees with the oracle on all six to 0.0060 LU.

**Ten negative controls, all reverted, and two of them found something.** Including the trailing partial
block changed nothing at first, because every published vector's duration is a whole number of hops at
48 kHz; a fixture with a deliberately unaligned tail now closes that. And the relative gate without the
absolute one is invisible in the *reading* — as this change already recorded — so it stays caught by the
threshold evidence one layer down. `LoudnessMeasurement` was **not** widened to expose a threshold for a
test's convenience.

Only groups 9.1 and 9.2 remain open, and neither is implementation.

**Next step:** the manual validation battery, then ADR-0022's promotion, then the four gates and
publication. Nothing is pushed and no PR exists.

**Known, introduced lint warning:** `ReportJSONDTO.swift` is 415 lines against SwiftLint's 400. The file
was clean before the export change; the alternatives are splitting the wire DTOs across files or cutting
documentation, and neither was taken unilaterally. SwiftLint is not one of the four gates.

**Minor follow-up, not a thread:** `ImportFlowComparisonTests` has one `Task.yield()` that was never
audited in depth; same shape as the ones above, no failure ever attributed to it.

**Other open threads** (see `openspec list` for their real task counts, not restated here):
`add-static-spectrogram-visualization` (manual validation battery deferred by product decision) and
`add-two-file-technical-comparison` (one accessibility criterion open, blocked on a known VoiceOver
traversal gap shared with ADR-0015). Neither was touched this session.

---
_Last touched: 2026-08-18. Overwrite freely; empty is fine._
