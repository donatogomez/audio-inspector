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
**Open thread: `add-significant-bandwidth-measurement`.** Groups 1-8 are complete. Programme bandwidth
now has a methodology decided by measurement, an accumulator that reproduces its targets, a place as the
sixth consumer of the one shared PCM read, validation against production, a section on screen, and a key
in the exported document. What remains is the manual pass and the closing gates.

**Group 8 paid a debt before it spent one.** Three places in the export chain carried a note saying that
three positional optionals was past the shape's comfortable width and that whoever added a fourth
measurement owed the container — written that way so the refactor could not be hidden inside the change
that added one. `ReportMeasurements` landed on its own commit and is byte-identical across all five
existing combinations. `InspectionAnalyses` was not reused for it: that is the flow's bundle, it carries
the visualisations, and its fields model lifecycle that must never reach the wire.

**The wire carries the measurement and nothing else.** Hertz, unrounded — `16101.5625` where the screen
says `16.1 kHz`, and a test asserts the two are different, because the change most likely to erode this
is a well-meant tidy-up. The resolution is its own field and never a `±`. The method is copied from what
ran, with the rule set standing behind a versioned identifier rather than travelling as loose constants.
Absence is the key not being there. There is no field in which a verdict could be written.

**What is left, exactly.** ADR-0023 stays `Proposed` with two of three promotion conditions met; the
third is a person looking at the surface, and the runbook with pre-computed expected displays is in
`docs/manual-validation-mvp.md`, marked PREPARED. Group 9 is the deferred work, named so it is not
quietly dropped — a shared STFT stage, an average spectrum, comparison between two files, and findings —
and none of it belongs to this change. Group 10 is the four gates plus the manual pass, and then the
archive.

**Next step: the manual validation pass.** Everything else in this change is either done or explicitly
deferred, and the fixtures are already written with their expected values computed before the app is
opened. Fixture 4 is the one that matters: a 16 kHz programme with one click in it, which must be
indistinguishable from the same programme without it.

**Older threads, neither advanced here**: `add-static-spectrogram-visualization` (manual validation
battery deferred by product decision); `add-two-file-technical-comparison` (one accessibility criterion
open, blocked on the VoiceOver traversal gap shared with ADR-0015). The loudness debt recorded ten
snapshots ago is unchanged and still not a thread.

---
_Last touched: 2026-08-20. Overwrite freely; empty is fine._
