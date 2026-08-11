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
**Focus:** `add-true-peak-measurement`, groups 1–3 done. **The domain model exists; no DSP does.**
Nothing in the project yet reads a sample to produce a true peak — `TruePeakMeasurement` is a result
type and the identity of the method that produced it, and that is all.

**What the model decided, beyond holding numbers.** `overallTruePeak` is **derived, not stored**, so it
cannot drift from the per-channel values: there is no argument to pass wrongly and no field to fill in
wrongly. That differs from `SignalLevelMetrics` on purpose — its overall RMS and DC offset genuinely are
not functions of the per-channel results, while a maximum of maxima exactly is. Contradictory channels
are unrepresentable rather than merely documented: a failable initialiser enforces `truePeak == nil` iff
`sampleCount == 0` in **both** directions, and refuses negatives, `NaN` and infinities.

**The methodology is recorded as an identity, not as configuration.** `TruePeakFilterIdentifier` follows
`WarningCode`'s existing shape in this repo — a `RawRepresentable` over `String` whose rawValue is the
identity and survives any refactor. The 48 taps, the Kaiser β and the cutoff are **not** in the model:
it says which methodology ran, never how to configure one. Changing any of those constants requires a
new identity (`v2`), which is what keeps two differently-measured files from exporting the same token.

**Next step:** group 4 — the accumulator in `AudioInspectorAnalysis`, `vDSP_conv` per phase plus
`vDSP_maxmgv`, with the filter generated from the recorded parameters rather than a pasted table. Two
things the group-2 spike already fixed and that the accumulator must honour: evaluate `sinc` with its
integer zeros used exactly (that is what makes `truePeak >= samplePeak` structural rather than a clamp),
and carry `tapsPerPhase/2 − 1` samples of history across chunks so the result stays bit-exact. The
methodological floor of ADR-0006 (≥4×) belongs there too — the model deliberately does not police it.

**ADR-0019 stays `Proposed`.** Its promotion still needs oracle agreement against production code plus a
manual pass; a domain type does not move it.

**Other open threads** (see `openspec list` for their real task counts, not restated here):
`add-static-spectrogram-visualization` (manual validation battery deferred by product decision) and
`add-two-file-technical-comparison` (one accessibility criterion open, blocked on a known VoiceOver
traversal gap shared with ADR-0015). Neither was touched this session.

---
_Last touched: 2026-08-12. Overwrite freely; empty is fine._
