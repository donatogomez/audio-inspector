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

**Focus:** **R7 — `add-inspection-overview` — is implemented on `feat/add-inspection-overview` and not
merged.** Nothing is pushed, no PR is open, nothing is archived. The four gates are green (boundaries,
`swift build` and `xcodebuild` clean, **1871 tests in 202 suites**, `openspec validate --strict`), and the
change sits at **33/36**. The umbrella is deliberately still at **16/29**: its §3.6 closes on *merge*,
not on implementation, so R7 does not mark it.

**All five sections are real in inspection mode.** Selecting Overview now shows the file's identity, the
six core technical facts, one figure per measurement, a compact drawing of the envelope the inspection
already produced, and what became of the reading. It arranges facts and derives none: every name, value,
unit, absence, failure and outcome sentence is `ReportPropertyFormatter`'s, `MeasurementsDisplay`'s or
`WaveformCopy`'s, and the view names no property of its own — the selection lives in
`ReportPropertyFormatter.coreFacts(for:)`, beside `groups(for:)` and `summary(for:)`, where property
meaning already lives.

**The warning count ADR-0026 §6 permits is refused, and the ground is not §7.** §7's three conditions each
hold. What they do not survive is R3's own shipped requirement in `audio-file-inspection` — *"a note MUST
NOT be counted, scored, ranked by severity, or summarised into a total"* — which is unqualified, which
calls warnings **Notes**, and which became canonical on 2026-08-28, *after* ADR-0026 was written on
2026-08-27. A `Proposed` record does not overrule a shipped capability, so §7's own last line is taken:
*the count goes and the section title carries the reader instead.* Specialising the requirement by a
delta — §8's manoeuvre against `audio-two-file-comparison` — was available and declined: §8 specialised a
rule in the direction of refusing **more**, and this would specialise one in order to be allowed an
exception to it. **The finding — that ADR-0026 §7 is unreachable as written — lives in R7's own
artefacts** (`proposal.md`'s first finding, `design.md` §2 and its Open Questions, and here). It belongs
eventually in the umbrella's closure task 5.3, where ADR-0026's status is decided; writing it there was
tried and **reverted**, because 5.3 is another change's task and appending an R7-derived condition to it
before R7 is on `main` widens someone else's scope. R7's task 8.3 carries it, post-merge. ADR-0026 is not
edited.

**The transitional report page survives in exactly one place, deliberately.** `legacyReportSurface` was
`ReportView`'s only caller and `ReportView` is `ComparisonView`'s only host, so replacing the `.overview`
branch outright would have **deleted the comparison from the application** until R8. The branch splits on
`ComparisonPresentation` — not on `ReportVisuals`, which becomes a pair only once both files have settled
both drawings and would have silently dropped the comparison's *loading* and *failed* states — and the
page keeps every comparison state, unchanged, until R8 owns it. That is the one surviving dependency on
the legacy `ReportView`, and R8 removes it.

**Two defects were found by rendering the surface and looking at it, and by nothing else.** A
measurement's figure carried the *measurement's* title rather than the fact's, so *Signal levels: −3.00
dBFS* did not say which level it was; it now carries the row's own name, *Peak sample*, and speaks the
measurement aloud. And only the drawing's `headline` was rendered — which an envelope does not have —
leaving the one state that has a drawing as the one state with no words. Every test passed before both.

**What could not be seen, and why.** SwiftUI draws no `ScrollView` content in a headless test process,
proven with a two-line control that came out blank, so the surface was hosted in a real app window
instead; the same limitation applies to R3's Details, which is built the same way, and it is inherited
rather than introduced. The **comparison** state was not rendered: reaching it needs a second real file
through the picker, which no harness here can drive, so it is asserted structurally instead.

**Nothing the redesign inherited was spent.** No second PCM read, no recomputation, no normalisation and
no alternative reduced envelope. The export, `schemaVersion` 1, `ComparisonView` and every comparison
semantic, the four measurement presentations, `WaveformEnvelope` and `WaveformGeometry`, and R1's five
sections and their order are untouched — asserted where they live rather than argued from the diff.
`AudioInspectorDomain`, `AudioInspectorAnalysis`, `AudioInspectorMedia` and `FeatureImport` have **zero
files changed**. Three production files, 71 lines, plus one new view and two new test suites.

**Next step.** R7 is functionally complete and committed locally, with no upstream. What remains is the
user's call: push, open the PR, merge. **Three tasks are open and none of them can honestly close before
that**: 6.2 (rendering the branch with a *settled* comparison — no harness here can drive two real files
through the picker, so it waits for R9's human pass), 8.3 (recording R7 in the umbrella's §3.6 and
carrying the §7 finding to 5.3 — both post-merge), and 8.4 (the PR, the merge and the archive). After it
merges, **R8 `add-comparison-mode-surface`** is next — the reduced Comparison Overview of ADR-0026 §8,
gated by a vocabulary sweep that includes the all-agree case — then **R9** for narrow windows, keyboard,
VoiceOver and the human pass. R8 is where the transitional page finally goes.

**Open questions.**
- **ADR-0026's status** (umbrella task 5.3), which the §7 finding above is an input to — to be written
  there post-merge, not before.
- At the 720 × 480 window minimum the Overview needs scrolling to reach the drawing and the result. That
  is a property of a reading surface at the minimum size, not a defect, and **R9 owns it** — recorded so
  it is looked at there rather than discovered.

**Inherited debt, untouched.** `add-two-file-technical-comparison` is still open at **52/58** and
ADR-0017 is still `Proposed`; ADR-0016 is still `Proposed`; `add-static-spectrogram-visualization` is
still open at **73/89**, its remaining tasks the manual validation battery deferred by product decision.
The VoiceOver traversal gap shared with ADR-0015 is inherited rather than fixed or worsened.

**Minor follow-ups, not threads:** `SettledMeasurements` describes itself as applying *"the same rule the
export path already applies"*, and it does not — the two differ on `loading` and on the bandwidth clause.
And R3's deferred split of `PropertyDisplay.detail` is still deferred: R7 did not need it either, because
the Overview shows no `detail` line at all.

---
_Last touched: 2026-08-29. Overwrite freely; empty is fine._
