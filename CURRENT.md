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
**Focus: `add-loudness-measurement` — integrated loudness (LUFS-I). The 48 kHz accumulator exists and
reproduces every official target. No wiring, no domain type, no other sample rate.**

`LoudnessAccumulator` lives in `AudioInspectorAnalysis` and measures **48 kHz mono/stereo only**. Every
published expectation is reproduced within the published ±0.1 — worst deviation **0.0213 LU** on Tech 3341
test 5, and BS.1770-5's own 997 Hz anchor lands **0.0003 LU** out, which is the sharpest confirmation
available because 997 Hz is exactly where the −0.691 offset cancels the K-weighting gain. It agrees with
FFmpeg to **0.0071 LU**. None of those targets moved to meet it: they were fixed two commits earlier.

Three things were decided by measurement rather than inherited, and two of them contradict what the
design assumed:

- **`vDSP_biquadD` was implemented and rejected.** Its output changed in the last two or three digits with
  the chunk size it was handed, because how it groups an IIR's work depends on the run length. A scalar
  transposed-direct-form-II recurrence has no grouping to vary, and chunk independence is now **bit-exact**
  at 1, 3, 127, 512, 4 096, 65 536 and whole-file.
- **That cost the fast primitive**: the fold is **0.243 s** over ten minutes of stereo in Release against
  the spike's 0.14 s projection. Half of the gap was recovered by advancing the two channels *together* —
  independent dependency chains, 0.243 s against 0.455 s, arithmetic per channel untouched.
- **`Float` filter state buys nothing.** Both widths were implemented: 1.4 × 10⁻⁵ LU apart, both
  chunk-exact, both 0.469 s. `Double` keeps the headroom for free.

A negative control found a real gap and closed it: with the absolute gate removed entirely, tests 3 and 4
still read identically, because the relative gate happens to exclude the same blocks by itself. The gate
is only observable in the **derived threshold**, so the accumulator now exposes it — and FFmpeg reports
the same quantity, so the two can be compared at an intermediate rather than only at the answer.

`finish()` returns a bare LUFS `Double?` and the type is **not `public`**: the shape that crosses the
module boundary belongs to group 3's `LoudnessMeasurement`, and committing to this one first would mean
changing a published signature later.

ADR-0022 stays `Proposed`. Groups 1, 2, 4 and 5 are closed; 3 and 6–9 remain.

**Next step:** task group 3 — `LoudnessMeasurement` in the domain, carrying the methodology including
**which compliance tier produced it**, then group 7's wiring. The per-rate derivation (4.4) is a separate
thread and the accumulator refuses those rates until it lands.

**Minor follow-up, not a thread:** `ImportFlowComparisonTests` has one `Task.yield()` that was never
audited in depth; same shape as the ones above, no failure ever attributed to it.

**Other open threads** (see `openspec list` for their real task counts, not restated here):
`add-static-spectrogram-visualization` (manual validation battery deferred by product decision) and
`add-two-file-technical-comparison` (one accessibility criterion open, blocked on a known VoiceOver
traversal gap shared with ADR-0015). Neither was touched this session.

---
_Last touched: 2026-08-18. Overwrite freely; empty is fine._
