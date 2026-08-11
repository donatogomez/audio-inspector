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
**Focus:** `add-true-peak-measurement`, groups 1–2 done. **The methodology is closed; production has
not started.** No `Sources/` and no `Tests/` file exists for this slice — group 2's evidence lives in
`Spike/validate-true-peak/` (its own package, outside the production graph) and in
`docs/spikes/2026-08-11-true-peak-methodology-validation.md`, which is the durable record.

**What is now fixed, and why it is worth reading before writing the accumulator.** Polyphase FIR, **8×**,
**48 taps per phase**, Kaiser **β = 6.0**, cutoff **1.0**, phases normalised, **zero-extension** at the
edges, **`Float`** arithmetic, linear internally with **dBTP** only on screen. Each of those is a
measurement, not a preference, and three of them closed *against* what the design first assumed: the
convolution needs no `Double`; the factor is 8× rather than the ADR's 4× floor, because 4×'s worst case
under-reads by 0.17 dB where R128 limits are quoted to 0.1 dB; and two of the three candidate edge
policies turned out to fabricate or to miss a peak outright.

**The result that most changes how the code should be written**: `truePeak >= samplePeak` is
**structural, not a clamp** — phase 0 of the interpolator is the exact identity because `sinc` is zero at
every non-zero integer, so the stored samples are already inside the set the maximum is taken over. That
holds only while the cutoff is exactly 1.0, which makes the cutoff a guarantee rather than a tuning knob.
Related: chunk independence is **bit-exact** here, unlike RMS, because a maximum accumulates nothing.

**Known limitation, deliberately carried rather than hidden.** BS.1770 Annex 2's own filter coefficients
were not available, so the filter is one designed to recorded parameters and validated against analytic
ground truth and FFmpeg's `ebur128`. **ADR-0019 §6 therefore bounds what the product may claim**: it
follows BS.1770/R128 *practice* with a stated factor and filter — it does not claim the standard's own
filter. Anything written in the UI, the docs or the export has to respect that.

**Next step:** group 3 — the sibling domain value type (per-channel and overall true peak, plus the
method descriptor), then group 4's accumulator in `AudioInspectorAnalysis`. The interpolation is
`vDSP_conv` per phase plus `vDSP_maxmgv`, and that is not an optimisation: the scalar equivalent costs
76 seconds per minute of mono audio in an unoptimised build.

**ADR-0019 stays `Proposed`.** Its tolerance is now pinned (0.05 dB against FFmpeg on signals smooth at
their boundaries), but promotion needs that agreement demonstrated against *production* code plus a
manual pass — a spike does not promote it.

**Other open threads** (see `openspec list` for their real task counts, not restated here):
`add-static-spectrogram-visualization` (manual validation battery deferred by product decision) and
`add-two-file-technical-comparison` (one accessibility criterion open, blocked on a known VoiceOver
traversal gap shared with ADR-0015). Neither was touched this session.

---
_Last touched: 2026-08-12. Overwrite freely; empty is fine._
