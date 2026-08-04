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

**Focus:** None in progress — report presentation is closed as far as implementation goes, and its
manual accessibility validation is **deliberately deferred, not done**.

**Status:** The report reads as a report rather than as the implementation behind it. Internal
vocabulary no longer reaches the screen: the presentation state is a closed type of its own, warnings
render from their message and kind, and container and codec are named with the exact token kept beside
them. Values are formatted for reading against a pinned locale, always preserving the precise figure.
There is a hero header and grouped properties instead of a settings form, exporting is a toolbar
action, colour is limited to the state of the reading, and each row is one coherent element for an
assistive reader. The inspection itself behaves exactly as before.

**Next step:** Waveform — reading samples and drawing them — as its own change. Before it ships, the
deferred accessibility checks on this surface should be run: VoiceOver, system text sizes, contrast,
and confirming nothing depends on colour alone. They need a person at a keyboard, so they do not gate
starting the next slice, only finishing it.

**Why:** Presentation was the one part that no automated test can finish judging. Recording those
checks as done without performing them would be inventing evidence, so they stay open and named.

**Open questions / threads:** Waveform, spectrogram and the per-property explanations are **not
started**. Each needs its own change: the first two require reading samples, which is a different kind
of work, and the explanations add new content that can drift from describing into judging quality, so
they carry their own normative requirement. Known risks carried forward: the pinned `en_US` locale
means formatting does not follow the user's region; warning text originates in the domain yet is swept
by a presentation test; an unmapped wire key would fall back to its raw name; and `Choose another
file…` still sits at the foot of the window while exporting lives in the toolbar.

---
_Last touched: 2026-08-04. Overwrite freely; empty is fine._
