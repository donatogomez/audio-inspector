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
**Open thread: `add-significant-bandwidth-measurement`.** Groups 1-6 are complete. The DSP is built, it
is **wired** as the sixth consumer of the one shared PCM read, and it is now **validated against
production** — a written file, the real decoder, the shared pass, and the outcome the composition
publishes. Still nothing visible: no UI, no export, no comparison, no findings.

**The core is unchanged and was not touched by this validation.** Counters stratified by each window's
own peak, constant in duration; channels measured apart because a summing downmix can cancel
opposite-polarity content; the budget global because the programme is the file. Group 6 found nothing
that contradicted the methodology, which is the outcome that makes the measurement worth trusting.

**The impulse control is satisfied, and the interesting part is what it is not.** An isolated
full-scale click inside a programme leaves the published reading identical — equality, not a tolerance
— and the turnover is pinned on both sides at eight impulses, where four-windows-each would predict
seven; the extra one is the Hann taper. What is *not* true, and what task 6.2 wrongly predicted, is that
a file of silence plus one click reads like silence. It reads broadband, because eligibility discards
silent windows and the click is then the whole programme. That was already measured and already
declared in ADR-0023; the task text was corrected rather than the method.

**Everything else came through the same real path**: four edges at five rates within the leakage the
window explains and never below the edge; the method identity per rate, which is what makes the
time-locked window testable; persistence, budget and prominence with both sides on real files;
undefined cases as absences and never a substituted Nyquist; every lossless container identical; a lossy
band limit surviving a rewrap identically, with no codec named. Nine negative controls, eight biting,
the ninth a documented redundancy — the budget is enforced twice, so removing its final check alone
changes nothing.

**One limitation is recorded rather than papered over.** The denormal amplitudes the underflow
arithmetic needs do not survive the write-and-decode round trip, evidenced by the zero peak the same
shared read reports. That evidence stays at PCM level. The overflow extreme does come through a real
file and answers finitely.

**Next step: group 7, the presentation** — one row stating what was measured and at what resolution, no
verdict, no comparison against the declared sample rate, absence in the existing not-computable
phrasing, and the structural half of accessibility. That surface is also what the **last** outstanding
promotion condition needs: ADR-0023 now records two of three met, with manual surface validation
pending and no surface yet to validate. Group 8's export follows it.

**Older threads, neither advanced here**: `add-static-spectrogram-visualization` (manual validation
battery deferred by product decision); `add-two-file-technical-comparison` (one accessibility criterion
open, blocked on the VoiceOver traversal gap shared with ADR-0015). The loudness debt recorded eight
snapshots ago is unchanged and still not a thread.

---
_Last touched: 2026-08-20. Overwrite freely; empty is fine._
