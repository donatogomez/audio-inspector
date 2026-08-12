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
**Focus:** a small robustness fix — **`SignalLevelMetrics` can no longer publish a value that is not a
number.**

**What was wrong, and what was not.** From samples that were individually finite, the accumulator
produced `rms == +infinity` and `dcOffset == NaN`, and the model accepted them as measurements. The
input was valid: `PCMChunk` refuses non-finite samples at the boundary but deliberately keeps finite
ones of any magnitude, because a file may genuinely carry a sample beyond full scale. The cause was an
implementation detail — each chunk's partial sums were formed in `Float32` before being widened — and it
was **chunk-dependent**, which contradicted this capability's own independence guarantee.

**Why the fix is a repair rather than a clamp.** The answer always fits: the mean and the RMS are both
bounded by the largest magnitude in the input, so a finite `Float` input has a finite `Float` result.
The overflow was purely intermediate, so each chunk is now widened *before* it is reduced, where no
intermediate can overflow. **The measurement is preserved exactly** — nothing is clamped, substituted or
invented — and the tests assert the values are correct rather than merely finite, which is the
difference between the two.

**The model now refuses what cannot describe a measurement**, as its two sibling value types already
did, and `finish()` became optional like theirs so an impossible result reaches the existing `failed`
outcome instead of a new state. With the reduction fixed, that path is a backstop the arithmetic cannot
reach. Measured cost: 0.043 s → 0.064 s in Release over ten minutes of stereo.

**A second, unrelated finding came out of this work, and it is now identified rather than mysterious.**
The intermittent test failure recorded earlier is the flow-state suites' own pattern: they deliver an
update and wait with a single `Task.yield()` for another task to apply it. Stressed, the spectrogram's
suite fails about two runs in eight and true peak's about one in eight — signal levels' did not fail in
the same sample. **It predates this change and is not touched by it**; the fix belongs with those
suites, replacing the yield with the deterministic handshake the shared-PCM cancellation tests already
use.

**Next step:** review and merge this fix; `openspec archive` runs after that.

**Other open threads** (see `openspec list` for their real task counts, not restated here):
`add-static-spectrogram-visualization` (manual validation battery deferred by product decision) and
`add-two-file-technical-comparison` (one accessibility criterion open, blocked on a known VoiceOver
traversal gap shared with ADR-0015). Neither was touched this session.

---
_Last touched: 2026-08-12. Overwrite freely; empty is fine._
