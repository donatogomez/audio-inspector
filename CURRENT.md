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

**Focus:** **R7 — `add-inspection-overview` — is merged, archived and closed.** PR
[#58](https://github.com/donatogomez/audio-inspector/pull/58) landed on `main` as the two-parent merge
commit `607f901` on 2026-08-29; the change is archived at
`openspec/changes/archive/2026-08-29-add-inspection-overview/` at **35/36**, and the umbrella that
sequences the redesign is open at **17/29**. **The next slice is R8 `add-comparison-mode-surface`**
(umbrella §3.7) — the reduced Comparison Overview of ADR-0026 §8, gated by a vocabulary sweep that
includes the all-agree case — and it is not started.

**All five sections are real in inspection mode.** Selecting Overview shows the file's identity, the six
core technical facts ADR-0026 §6 names, one figure per measurement, a compact drawing of the envelope the
inspection already produced, and what became of the reading. It arranges facts and derives none: every
name, value, unit, absence, failure and outcome sentence is the one `ReportPropertyFormatter`,
`MeasurementsDisplay` or `WaveformCopy` already produces, and the view names no property of its own —
the six are selected by `ReportPropertyFormatter.coreFacts(for:)`, beside `groups(for:)` and
`summary(for:)`, because a view is not where property meaning belongs.

**The warning count §6 permits is absent, and the ground is not §7.** §7's three conditions each hold.
What they do not survive is R3's shipped requirement in `audio-file-inspection` — *"A note MUST NOT be
counted, scored, ranked by severity, or summarised into a total"* — which is unqualified, which calls
warnings **Notes**, and which became canonical on 2026-08-28 (`f9aa9b7`), *after* ADR-0026 was written on
2026-08-27. A `Proposed` record does not overrule a shipped capability, so §7's own last line is taken:
*the count goes and the section title carries the reader instead.* **ADR-0026 §7 is therefore unreachable
as written** — recorded in R7's archived `proposal.md` and `design.md`, and cited from the umbrella's
§3.6. **Umbrella task 5.3 is deliberately left verbatim**: it is the task that will *decide* this
record's status, and appending a finding to it would turn a decision into a log. The canonical
requirement is untouched.

**The legacy comparison fallback remains, and R8 removes it.** `legacyReportSurface` is `ReportView`'s
only composition caller, and `ReportView` is the only host of `ComparisonSection` — the comparison
surface itself — so replacing the `.overview` branch outright would have deleted the comparison from the
application. The branch splits on `ComparisonPresentation`, deliberately not on `ReportVisuals`, which
becomes a pair only once both files have settled both drawings and would have silently dropped the
comparison's *loading* and *failed* states. One file gets the real Overview; a window with a second file
keeps the page it has always had. **This is the only surviving dependency on the legacy `ReportView`.**

**R7 is archived with one task open, on purpose.** **6.2 — rendering the `.overview` branch with a
*settled* comparison — is manual validation deferred to R9.** Reaching that state needs two real files
driven through the picker, which no harness could do; what exists instead is a structural assertion, and
that is evidence, not a look. Closing it would have been the only dishonest route to a full count.
Separately, SwiftUI draws no `ScrollView` content in a headless test process, so the single-file surface
was hosted in a real app window to be looked at — the same limitation applies to R3's Details and is
inherited, not introduced. **Looking is what found the two presentation defects R7 fixed**, both of which
every test had passed.

**ADR states.** **ADR-0025 `Accepted`.** **ADR-0026 stays `Proposed`** — five sections existing does not
promote it; its outstanding condition is a vocabulary sweep over a Comparison Overview that R8 builds and
that does not exist. **ADR-0016 and ADR-0017 stay `Proposed`**, unchanged.

**Inherited debt, untouched.** `add-two-file-technical-comparison` is still open at **52/58** and
`add-static-spectrogram-visualization` at **73/89**, its remaining tasks the manual validation battery
deferred by product decision — which is why `spectrogram-visualization` is still not a canonical
capability. The VoiceOver traversal gap shared with ADR-0015 is inherited rather than fixed or worsened.

**Open questions.**
- **ADR-0026's status** (umbrella 5.3), for which the §7 finding is an input.
- At the 720 × 480 window minimum the Overview needs scrolling to reach the drawing and the result. A
  property of a reading surface at the minimum size, not a defect — **R9 owns it**.

**Minor follow-ups, not threads:** `SettledMeasurements` describes itself as applying *"the same rule the
export path already applies"*, and it does not — the two differ on `loading` and on the bandwidth clause.
R3's deferred split of `PropertyDisplay.detail` is still deferred; R7 did not need it either. And two
comments in `RootView.swift` say *`ComparisonView`* where the type is *`ComparisonSection`* — the file is
`ComparisonView.swift`, which is where the slip came from; R8 rewrites those comments when it removes the
fallback.

---
_Last touched: 2026-08-30. Overwrite freely; empty is fine._
