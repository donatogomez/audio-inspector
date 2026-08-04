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

**Focus:** `improve-report-presentation` — the report surface stops showing the implementation and
starts reading as a report. No capability is added and the inspection behaves exactly as before.

**Status:** The functional work is complete and the automated validation is green. Internal vocabulary
no longer reaches the screen: the presentation state is a closed type of its own, warnings render from
their message and kind, and container and codec are named with the exact token kept beside them.
Values are formatted for reading against a pinned locale, always preserving the precise figure. The
report has a hero header and grouped properties instead of a settings form, exporting is a toolbar
action, colour is limited to the state of the reading, and each row is one coherent element for an
assistive reader.

**Next step:** Complete the manual accessibility validation — VoiceOver, system text sizes, contrast,
and confirming nothing depends on colour alone — then the final review, then close the change. Those
checks need a person at the keyboard; the suite cannot reach them.

**Why:** Presentation was the one part of the slice that could not be verified automatically end to
end, so the change is not finished until it has been seen and heard, not only compiled.

**Open questions / threads:** Waveform, spectrogram and the educational per-property explanations are
**not started**. Each needs its own change: the first two require reading samples, which is a different
kind of work, and the explanations add new content that can drift from describing into judging quality,
so they carry their own normative requirement.

---
_Last touched: 2026-08-04. Overwrite freely; empty is fine._
