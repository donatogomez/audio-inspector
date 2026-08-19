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
**Open thread: `add-significant-bandwidth-measurement`, group 1, task 1.7.** Methodology only — no
production code exists for this change and none is wanted yet.

**Still NO-GO, and the reason is now one sentence long.** This session tested the hypothesis that there
is no eligibility gate at all: a window participates if it carries energy, the threshold decides
prominence inside a window, persistence decides repetition between windows. The hypothesis is good. It
needs no invented constant — `FFT(zeros)` is identically zero, so "carries energy" is decidable with no
epsilon — and it reads seven of the collector's eight files correctly, including an analog transfer that
plays continuously and, importantly, including a *band-limited* noise floor, which is the case the
feature exists to catch.

It fails on one case, and the failure is not about level: **a broadband noise floor alone in more than
10 % of a file sets the answer, at any level, down to 200 dB below the programme.** A window that
contains nothing but a floor is its own reference, so the floor is 0 dB from its own peak and every bin
qualifies. Level is completely irrelevant, which is what makes it indefensible rather than merely
awkward.

Two escape routes were tried and both closed. Spectral flatness gives **0.564 for tape hiss and 0.564
for musical "air"** at the same per-bin level — a cymbal and a hiss are the same kind of signal, so
shape cannot separate them. Reading the measurement at several persistence levels adds real information
(persistent versus intermittent) but not that information, because noise-like content thins out at high
persistence exactly as a floor does. Together with part B's rejected level gate, that is three
independent routes converging on the same structural fact: **a window holding only a noise floor is
indistinguishable, from inside itself, from one holding only quiet music.** The difference exists only
in comparison with the rest of the file, and every such comparison is a dynamic-range budget.

So the remaining decision is not a measurement. It is a declaration: **how far below a file's programme
does Audio Inspector claim to still be looking?** Whatever the answer, it travels with the number rather
than hiding inside it. The metric's *name* is blocked on the same decision — "significant" cannot
describe a figure that a −200 dBFS floor can set, and the honest alternatives either drop the word
(*persistent spectral extent*) or carry the budget in it (*programme bandwidth, within N dB of programme
peak*).

One constant got deleted rather than sourced. The −120 dBFS floor was invention twice over: unnecessary,
and masking 120 dB of range in which the measurement is exact. Absence is now numeric — a file carrying
no energy has no bandwidth — and a new edge case came with it: a constant signal is DC, so DC is
legitimately its highest qualifying bin and the reading is 0 Hz. ADR-0023 says zero is not a result, so
task 4.4 has to say what the model does with it.

**Next step: task 1.7, as a product decision rather than another sweep.** The sweeps are done and they
agree with each other. What is needed is a number chosen deliberately, with its cost stated: content in
passages more than that far below the programme is not measured, and a noise floor further down than
that does not count as content.

Everything measured so far is synthetic and in memory. Nothing has touched a real file, a container, a
codec, or the production decode path. ADR-0023 stays `Proposed`.

**Older threads, neither advanced here**: `add-static-spectrogram-visualization` (manual validation
battery deferred by product decision); `add-two-file-technical-comparison` (one accessibility criterion
open, blocked on the VoiceOver traversal gap shared with ADR-0015). The loudness debt recorded three
snapshots ago is unchanged and still not a thread: the export chain's third positional optional,
`ReportJSONDTO.swift` at 415 lines against SwiftLint's 400, the absolute gate not being observable from
outside `LoudnessAccumulator`, and the unaudited `Task.yield()` in `ImportFlowComparisonTests`.

---
_Last touched: 2026-08-19. Overwrite freely; empty is fine._
