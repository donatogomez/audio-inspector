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

**The accumulator is NO-GO, and that is the result rather than a setback.** This session's job was to
close the resolution claim and then to try to *break* the five parameters group 1 had produced. The
threshold and the persistence criterion survived deliberate refutation on fixtures that had no part in
choosing them. The **window-eligibility gate did not**, and it sits upstream of both: it decides which
windows are looked at, so nothing downstream can be built until it is settled. That is now task 1.7.

Why the gate fails is worth carrying in the head, because it is not a tuning problem. Excluding windows
more than 60 dB below the file's loudest moment erases a real quiet passage 70 dB down, band and all —
and the table of "rejects a noise-floor-only passage" and the table of "keeps a real quiet passage" came
out as **exact mirror images**. They have to be: to a rule that only knows how far below the peak a
window sits, a noise floor 70 dB down and real music 70 dB down are the same measurement. So the gate is
a **dynamic-range budget**, not a silence test, and the honest move is to state it as one rather than
pick a number that reads as principled.

Absence, by contrast, got *simpler*. The −120 dBFS floor is gone: it discarded about 60 dB of range in
which the measurement still works, and it was never needed, because a file that carries no energy at all
is separable from a signal 180 dB down by a numeric condition with no chosen level in it.

The resolution work turned out better than expected. The earlier "≈ 4 bins" was empirical and slightly
mysterious; it is now derived — the Hann skirt falls as 1/d³, so a threshold T reaches
`(1/(π·10^(T/20)))^(1/3)` bins, 4.72 at −50 dB — and the measurement follows the derivation exactly, at
every rate and every FFT size. The tempting contract, reporting a lower and an upper bound, was derived
from that and then **falsified**: coherent tones one bin apart overshoot by 8.5 bins, outside any bound
the leakage supports. So the domain carries a frequency and a resolution, and the ADR carries the
statement that the frequency is an upper bound on where content ends.

The window is settled and time-locked at ≈ 42.67 ms with 75 % overlap. The evidence was blunt: under a
fixed 2048-point window, ten bursts totalling 5 % of a file read 12.65 % of windows at 44.1 kHz and
6.73 % at 192 kHz — the same temporal evidence, significant at one rate and not at another. `vDSP` turns
out to accept `f · 2^m` for f in {1,3,5,15}, so 1920 and 3840 hold the duration to 2 % where powers of
two alone would force 8.8 %.

**Next step: task 1.7.** Not more sweeping — the sweeps are done and they agree. What is needed is a
decision about what the measurement is allowed to ignore, and it is a product decision wearing a DSP
costume: how far below a file's loudest moment does Audio Inspector still claim to be looking? Whatever
the answer, it travels with the result.

Everything measured so far is synthetic and in memory. Nothing has touched a real file, a container, a
codec, or the production decode path. ADR-0023 stays `Proposed`.

**Older threads, neither advanced here**: `add-static-spectrogram-visualization` (manual validation
battery deferred by product decision); `add-two-file-technical-comparison` (one accessibility criterion
open, blocked on the VoiceOver traversal gap shared with ADR-0015). The loudness debt recorded two
snapshots ago is unchanged and still not a thread: the export chain's third positional optional,
`ReportJSONDTO.swift` at 415 lines against SwiftLint's 400, the absolute gate not being observable from
outside `LoudnessAccumulator`, and the unaudited `Task.yield()` in `ImportFlowComparisonTests`.

---
_Last touched: 2026-08-19. Overwrite freely; empty is fine._
