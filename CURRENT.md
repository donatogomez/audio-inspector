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
**Open thread: `add-significant-bandwidth-measurement`.** Groups 1, 2 and 3 are complete, and the domain
model came with 3. Nothing is wired: no shared PCM consumer, no UI, no export, no comparison.

**The accumulator exists and it reproduces group 2's targets exactly** — no expected value changed, no
tolerance widened. That was the point of settling them first, and it paid: the one place the production
type disagreed with the reference was real, and it was the stratification, not the method.

**Two questions had to be answered before the type had a shape, and both were decided by arithmetic
rather than taste.** Bounded memory first: the budget compares each window against the *file's* peak,
which is unknown until the last chunk, so something must be carried. One bit per bin per window is exact
and was seriously considered — the rule is not to trade exactness for O(1) when a compact O(duration)
form costs a few MB — but it is 499 MB for three hours at 192 kHz, and task 3.3 forbids retaining a
spectrogram at any resolution, which one bit per bin still is. Counters stratified by the window's own
peak are **constant in duration**: 7.57 MB for stereo at 192 kHz whether the file is a minute or three
hours, against 879 MB of PCM for ten minutes of the same audio.

**That structure costs exactly one tolerance, and a fixture found which way it must round.** The budget's
boundary always falls *inside* a stratum whose members straddle it, and whose exact peaks are gone.
Resolving that stratum exclusively read 16 102 Hz for a passage sitting at exactly −60.0 dB where the
exact rule reads 20 016 — a window *on* the budget is eligible, and dropping its stratum drops it. So it
is resolved inclusively, and the declared budget became "60 dB, resolved to whole 0.25 dB strata,
admitting at most 0.25 dB below it". Both sides are pinned by tests. A side effect worth remembering:
the budget is enforced **twice**, by the ring's capacity as well as by the check at the end, which is
why removing the check alone changes nothing.

**Channels are measured apart, and the fixture that decided it cannot be argued with.**
`oppositePolarity` — identical content with the sign flipped on odd channels — cancels to a flat line
under any downmix that sums, and a measurement of where energy stops must not be able to lose energy the
file carries. So each channel is measured on its own, `overall` is the highest of those readings, and
channels are indices with no layout named. The budget stays global, because the programme is the file: a
channel 70 dB under the rest reports nothing, which is a fact about the file's dynamics.

Nine negative controls, applied and reverted one at a time, all break a test — two of them by trapping
rather than by an assertion, which is the right failure for a bounds violation. One methodological
sentence is now load-bearing in code: **there is no clamp anywhere in the transform path**, and the
silence test is what stands between the method and an epsilon.

**Next step: group 5, the sixth consumer** — wiring the accumulator into the one shared PCM read, on
ADR-0021's terms, and the cost that ADR-0023 already names as this change's main negative consequence.
Group 6's correctness battery and group 7's presentation follow it. The accumulator's own cost is
measured and small: 0.28 s per audio-minute at 192 kHz in Release, `finish()` in milliseconds.

ADR-0023 stays `Proposed`. Its remaining promotion conditions are the impulse control against production
code, which group 6 owns, and human validation of a surface that does not exist yet.

**Older threads, neither advanced here**: `add-static-spectrogram-visualization` (manual validation
battery deferred by product decision); `add-two-file-technical-comparison` (one accessibility criterion
open, blocked on the VoiceOver traversal gap shared with ADR-0015). The loudness debt recorded six
snapshots ago is unchanged and still not a thread.

---
_Last touched: 2026-08-19. Overwrite freely; empty is fine._
