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

**Focus:** **R8 — `add-comparison-mode-surface` — is merged, archived and closed.** PR
[#60](https://github.com/donatogomez/audio-inspector/pull/60) landed on `main` as the two-parent merge
commit `2765bae` on 2026-08-30; the change is archived at
`openspec/changes/archive/2026-08-30-add-comparison-mode-surface/` at **56/59**, and the umbrella is at
**18/29**. **The next slice is R9 `polish-inspection-workspace`** (umbrella §3.8) — narrow windows,
keyboard, VoiceOver and the human pass — and it is not started.

**A comparison is a mode of this workspace, not a page.** The same five sections exist whether one file
is open or two, in the same order; what a comparison changes is what each one *contains*. Details renders
the technical comparison, both identities, each file's notes and each file's result. Measurements renders
the comparison of the same four measurements **in place**, not appended. **Waveform and Spectrum needed
nothing**: R5 and R6 built them against `ReportVisuals`, which has paired the two files since it shipped,
so they have zero lines changed.

**The transitional report page is gone.** `legacyReportSurface`, `ReportView` and `ComparisonSection` had
no callers left and were deleted — but `ReportSection` was **extracted first**, because it was declared
inside `ReportView.swift` and four live sections use it. That is the distinction the deletion turned on:
dead UI goes, reusable containers, formatters and copy stay.

**The Comparison Overview is ADR-0026 §8 exactly, and its safety is structural rather than lexical.** It
carries the two identities and two sentences of framing. **No outcome reaches it at all** — it reads each
file's own `AudioFileReference` and the copy, never a property, a measurement, a warning, a status or any
comparison type — so no element can appear or disappear for a reason that means the two files are alike.
An all-agree pair and a pair agreeing about nothing render the same elements; only the files' own facts
differ. That generalises §8's own argument, which refused a filtered *properties that differ* list on the
ground that it fails on its **empty state**, where the absence of rows *is* the prohibited phrase.

**`warningSummary` is deleted, not migrated.** It rendered *"1 warning on this file"* per side — a
cardinality over notes, written before `audio-file-inspection` made *"A note MUST NOT be counted, scored,
ranked by severity, or summarised into a total"* canonical. Nothing stands in for it: no badge, no icon,
no pluralised phrase. Details presents each file's notes in the report's own words, which is more than a
count ever said.

**The export stays where the hotfix put it** — `ReportExportToolbar`, once, above the section routing,
reachable from all five sections and in every comparison state. R8 did not move it, and that placement is
what made removing `ReportView` possible without losing it.

**R8 archives with three visual observations open, on purpose**: **10.2** the settled measurement
comparison, **10.4** the paired waveform and **10.5** the paired spectrum. R8 changed no line of the two
drawings and R5/R6 rendered them when they were built, but that is not having looked at them here, and
the automated presentation tests passing is not the observation those tasks ask for. **They are deferred
to R9's human pass.** What *was* rendered — the Comparison Overview in four states and Details compared
at three window sizes — found a defect no test had: at the 640 pt reading measure the outcome column was
clipped mid-word, and a reason a reader cannot finish is not a stated reason.

**ADR states.** **ADR-0024 and ADR-0025 `Accepted`.** **ADR-0026 stays `Proposed`** — but its position
changed materially: its eighth promotion condition was a vocabulary sweep over a Comparison Overview that
did not exist, and now it does and the sweep ran. All eight of its conditions have live coverage, and the
record states *"Manual — none in this record, and that is a decision."* **Promoting it is a decision that
has not been taken**, and it belongs with the umbrella's closure task 5.3 — where the finding that §7 is
unreachable as written is also waiting. **ADR-0016 and ADR-0017 stay `Proposed`.**

**Inherited debt, untouched.** `add-two-file-technical-comparison` is still open at **52/58** and
`add-static-spectrogram-visualization` at **73/89**, its remaining tasks the manual validation battery
deferred by product decision. The VoiceOver traversal gap shared with ADR-0015 is inherited rather than
fixed or worsened.

**Open questions.**
- **ADR-0026's status** (umbrella 5.3), now with all eight conditions covered and the §7 finding as an
  input. R9's human pass is the natural moment to decide it.
- At the 720 × 480 minimum the compared grid runs past the window and scrolls horizontally inside its
  section — the closed decision R8 was given. **R9 owns whether that is the final answer.**

**Minor follow-ups, not threads:** `SettledMeasurements` still describes itself as applying *"the same
rule the export path already applies"*, and it does not. R3's deferred split of `PropertyDisplay.detail`
is still deferred.

---
_Last touched: 2026-08-30. Overwrite freely; empty is fine._
