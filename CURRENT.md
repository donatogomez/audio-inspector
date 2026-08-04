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

**Focus:** None in progress. Report presentation is **closed and integrated**; no change is open.

**Status:** The report reads as a report rather than as the implementation behind it. Internal
vocabulary no longer reaches the screen: the presentation state is a closed type of its own, warnings
render from their message and kind, and container and codec are named with the exact token kept beside
them. Values are formatted for reading against a pinned locale, always preserving the precise figure.
There is a hero header and grouped properties instead of a settings form, exporting is a toolbar
action, colour is limited to the state of the reading, and each row is one coherent element for an
assistive reader. The inspection itself behaves exactly as before.

Its manual accessibility validation remains **deliberately deferred, not done**: VoiceOver, system text
sizes, contrast, and confirming nothing depends on colour alone. Those need a person at a keyboard, so
they were left open and named rather than recorded as evidence that does not exist.

**Next step:** Research and design a **static waveform** — reading samples and drawing them once, with
no interaction — as its own change, starting from investigation rather than from code. It is the
thinnest slice that turns the app into something that examines the signal instead of only its
metadata, and it builds the sample-reading path that everything later depends on.

**Why:** The product's own premise is to examine the signal, and so far nothing reads a single sample.
Starting with a still drawing keeps the arithmetic trivial while proving decoding, bounded memory,
progress and cancellation — the same seam-first order that made the earlier slices work.

**Open questions / threads:** **Not started:** waveform, spectrogram, playback, zoom, editing, and the
per-property explanations. Each needs its own change — the visual ones because reading samples is a
different kind of work, the explanations because new prose can drift from describing into judging
quality and so carries its own normative requirement.

Known risks carried forward from the presentation work: the pinned `en_US` locale means formatting does
not follow the user's region; warning text originates in the domain yet is swept by a presentation
test; an unmapped wire key would fall back to its raw name; and `Choose another file…` still sits at
the foot of the window while exporting lives in the toolbar.

---
_Last touched: 2026-08-04. Overwrite freely; empty is fine._
