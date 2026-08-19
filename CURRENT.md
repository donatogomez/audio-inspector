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
**Open thread: `add-significant-bandwidth-measurement`, group 1.** Methodology only — there is no
production code for this change and none is wanted yet.

Group 1 asked whether a threshold plus a persistence fraction can define "significant bandwidth". The
measured answer is **no, not on their own**, and that is the useful result of the session rather than a
setback. Threshold and persistence are settled (−50 dB relative to the loudest bin in the same analysis
window; presence in ≥ 10 % of eligible windows), but no relative reference at any setting can report
*absence* for digital silence — on silence the signal and the reference sit on the same numerical floor.
Two small rules complete it and both were measured rather than assumed: a gain-invariant window-
eligibility gate, and an absolute silence floor that is deliberately **not** gain-invariant because it
detects the absence of audio rather than measuring anything.

The intent behind the constants matters more than the constants. **The threshold is a sensitivity, not a
discriminator** — a weak real band and a low noise floor at the same relative level are indistinguishable,
so choosing −50 dB is choosing how deep to look, not choosing what is real. Two consequences are recorded
in the ADR rather than tuned away: a bass-dominated file under-reports, and a gentle roll-off reports the
top of the band rather than the filter's knee. This is emphatically **not** a filter-knee detector, and
the record says so before any surface can imply otherwise.

**Next step: task 1.5**, the resolution claim. The empirical half is done — the reported edge sits ≈ 4
bins above a known cut-off, one-sided upward, at four different bin widths — but the decision it feeds
(bin centre, bin edge, or range) needs the analytic Hann main-lobe figure beside the measurement, not
instead of it. 1.6 closes with it.

**The open question that outgrew group 1**: the persistence fraction is defined on *windows*, so it is
not portable across window lengths — the same signal reads 16 043 Hz at FFT 4096 and 24 000 Hz at FFT
8192. `fftSize` and `hop` are therefore part of the method identity, design.md's choice of 2048 points is
reopened, and whether the window should be fixed in **time** rather than in samples belongs to group 3
before an accumulator is written.

Everything measured so far is synthetic and in memory. Nothing has touched a real file, a container, a
codec, or the production decode path. ADR-0023 stays `Proposed`: two of its three promotion conditions —
an impulse control passing against production code, and human validation of the surface — are untouched.

**Older threads, neither advanced here**: `add-static-spectrogram-visualization` (manual validation
battery deferred by product decision); `add-two-file-technical-comparison` (one accessibility criterion
open, blocked on the VoiceOver traversal gap shared with ADR-0015). The loudness debt recorded in the
previous snapshot is unchanged and still not a thread: the export chain's third positional optional,
`ReportJSONDTO.swift` at 415 lines against SwiftLint's 400, the absolute gate not being observable from
outside `LoudnessAccumulator`, and the unaudited `Task.yield()` in `ImportFlowComparisonTests`.

---
_Last touched: 2026-08-19. Overwrite freely; empty is fine._
