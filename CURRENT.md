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
**Open thread: `add-significant-bandwidth-measurement`.** Group 1 is complete. No production code exists
for this change yet, and group 2 comes before it.

**GO.** The blocking question was never a measurement, and it stopped pretending to be one. A window
holding only a noise floor is indistinguishable, from inside itself, from one holding only quiet music —
three independent routes converged on that — so the rule that separates them is a **declaration**, and it
was made: **programme bandwidth, within 60 dB of programme peak**. The budget is load-bearing on exactly
one case, a broadband floor alone in a file, and its cost is written into the record rather than left to
be discovered: content more than 60 dB below a file's loudest moment is not measured, and a noise floor
further down does not count as content. Those are two halves of one rule; no setting keeps one and drops
the other. The name carries the budget so the figure cannot be read as a claim about everything in the
file.

**A correction came with it, and it simplifies the method.** The absence rules — first a −120 dBFS floor,
then a file-level energy test — were both artefacts of the first harness clamping magnitudes at 1e-12,
which turned a silent window into a −240 dB window *with a reference*. Unclamped, a window of zeros has
magnitude exactly zero and is ineligible by itself; digital silence reads absent even with every other
rule switched off. So there is no absolute rule of any kind, and one methodological requirement instead:
**the accumulator must not clamp its magnitudes.**

The full rule set then ran as one thing for the first time and passed twelve of twelve pre-registered
constraints. Four constants and one declaration: per-window spectral peak as reference, −50 dB
prominence, ≥10 % persistence, ~42.67 ms time-locked window with 75 % overlap and a periodic Hann, and
the 60 dB budget.

**Next step: group 2, fixtures and the oracle** — and it is a change of kind, not of degree. Everything
measured so far is synthetic and in memory. Group 2 is where this meets real files, the rate matrix,
container and codec equivalence, and FFmpeg as a corroborating oracle only. The accumulator (group 3)
comes after it, on the change's own ordering.

ADR-0023 stays `Proposed`. Its first promotion condition is now met; the other two are the impulse
control passing against production code and human validation of the surface, and neither can be met
before the accumulator exists.

**Older threads, neither advanced here**: `add-static-spectrogram-visualization` (manual validation
battery deferred by product decision); `add-two-file-technical-comparison` (one accessibility criterion
open, blocked on the VoiceOver traversal gap shared with ADR-0015). The loudness debt recorded four
snapshots ago is unchanged and still not a thread: the export chain's third positional optional,
`ReportJSONDTO.swift` at 415 lines against SwiftLint's 400, the absolute gate not being observable from
outside `LoudnessAccumulator`, and the unaudited `Task.yield()` in `ImportFlowComparisonTests`.

---
_Last touched: 2026-08-19. Overwrite freely; empty is fine._
