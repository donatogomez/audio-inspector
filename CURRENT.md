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

**Focus:** **R2 — `restructure-empty-state` — is being implemented, and its first four groups are
done.** The branch is `feat/restructure-empty-state` and the change is at **15/43**. `ImportFlowCopy`
owns the surface's six sentences; `PreInspectionPresentation` is a failable projection of the flow's
three pre-report states that refuses a report rather than degrading it; and `ImportFlowView` is one
frame plus **one** status region rather than two insertion points at two heights.
**The surface has changed for the first time.** The frame now says, in reading order, what the app does,
the way to begin, that a file can be dragged instead, and — last, and in every state — *"The file is only
read, never modified, moved or copied."* That sentence used to be the tail of a line about dragging, with
no test and no requirement mentioning it; it is now rendered by production and its absence fails.
The heading that repeated the window's own title bar is gone. **The running state now says so**: the
indicator is joined by *"Inspecting…"*, and by nothing else — no file (the state carries none, and begins
before the panel is answered), no stage, no figure, and no way to stop it, because the flow exposes no
cancellation for a control to call. **The failed state still keeps its own content** — the flow's message
with `Try again` beside it — which is group 5.
`RootView`, `ImportFlowModel` and the drop are untouched. R1 is merged and the umbrella that sequences
both is still open.

**`add-two-file-visual-comparison` is merged, archived and closed.** PR
[#50](https://github.com/donatogomez/audio-inspector/pull/50) landed on `main` as a two-parent merge
commit `a62e021` on 2026-08-27, **ADR-0025 is `Accepted` (2026-08-27)**, and the change is archived at
`openspec/changes/archive/2026-08-27-add-two-file-visual-comparison/`, which created the
`audio-two-file-visual-presentation` capability with 11 requirements and 38 scenarios. Two files'
waveforms and spectrograms now sit side by side on shared axes — time by real duration, frequency by
Nyquist — reusing what the second file's single read already produced. The paired drawings **stand in
for** the single ones rather than joining them. Past a file's own audio and above its own Nyquist are
two different facts with two different sentences, and neither is drawn as silence or as the ramp's
floor. There is no visual outcome: nothing says the two are the same, different, similar or matching.

**The export payload no longer lives in a view.** PR
[#51](https://github.com/donatogomez/audio-inspector/pull/51) merged as `58a9b18`: the rule that turns
four presentation states into `ReportMeasurements`' four optionals moved out of `ReportView` into
`ExportableMeasurements`. **Nothing observable changed** — same UI, same JSON, same `schemaVersion` 1 —
and that is the point: it was a preparation, deliberately with no OpenSpec change and no ADR.

**R1 — the shell — is merged, and it is only the shell.** PR
[#52](https://github.com/donatogomez/audio-inspector/pull/52) landed on `main` as a two-parent merge
commit `9a5f006` on 2026-08-27, carrying ADR-0026, the umbrella change and the shell together — the
shape #45, #48 and #50 all used. **The umbrella is not archived**: it is at **11/29** and stays open
until its last slice lands, because it is the record the eight remaining slices are sequenced by. Its §1
and §2 are closed, §3 onward untouched. What exists
is `WorkspaceSection` (five cases), `WorkspaceNavigation` (the selection and the one rule that moves
it), `WorkspaceCopy` (the shell's words), and a segmented control in `RootView`. The selection lives in
the composition root's own `@State`: no domain value, no field of `ImportFlowModel` or
`ComparisonState`, no persistence, and a source assertion over `Sources/` and `App/` refuses any target
below it naming it. It moves in exactly one place — a single `.onChange` on the whole window — and only
when a **new primary report that did not fail globally** arrives. A comparison starting, settling, being
dismissed, superseded, cancelled or failing moves nobody; nor does an analysis settling, a `.working`
state, a dismissed picker, or a globally failed report. Three negative controls were seen to fail —
a section that moves on its own (**39 issues across 8 tests**, once the lifetime tests were widened to
assert from *every* section), persistence (4), and a `"3 differences"` count on the shell's comparison
surface (4) — and all three were reverted and verified by checksum.

**R2 is open, and it is documentation only so far.** The change is
`openspec/changes/restructure-empty-state` at **0/43**, adding five requirements and sixteen scenarios to
`audio-file-inspection` about the surface *before* a report — the starting screen, the running state and
the recoverable failure, as three states of **one** shell rather than three screens. **No ADR**:
ADR-0026 §1 and §12 already decide that there is one subject, no collection and no sidebar, and layout is
not an ADR's business.

Four findings came out of reading production, and each is a fact about the code rather than a preference.
One sentence carries three claims at once, so the **read-only promise** — *"The file is only read, never
modified, moved or copied."* — is the tail of a sentence about dragging, and **no test or requirement
protects it**. **`Try again` names something the app cannot do**: nothing about a failed selection is
retained (ADR-0010, ADR-0013), so the button opens the panel exactly as the idle one does. The running
state shows a bare spinner and says nothing. And **`.working` begins before a file has been chosen**,
because `selectAndInspect()` sets it and *then* awaits the panel — which is why the running state may
name no file and no phase, a limitation recorded rather than papered over. There is **no quantitative
progress anywhere in `Sources/`**, so no percentage is invented, and **no cancellation exists**, so no
`Cancel` is offered.

**What R1 deliberately does not do.** No section has its own content yet. Selecting one changes the
control's state and nothing else: all five still show the existing report page underneath, exactly as it
was. There is no Inspection Overview, no Comparison Overview, no comparison mode, no Details or
Measurements rework, no waveform or spectrum workspace, no toolbar, and no responsive pass. The
paired-waveform overlap defect below is untouched. Those are R2–R9, each its own change and its own PR.
**ADR-0026 is still `Proposed`** — R1 satisfies seven of its eight promotion conditions, and the eighth
is a vocabulary sweep over a Comparison Overview that does not exist yet.

**The decision that was blocking it is settled, against the capability rather than by preference.** The
Comparison Overview carries the two file identities, each side's own facts, the existing factual framing
and a way through to the full comparison — and nothing else. The `5 same · 3 different · 2 not
comparable` block is refused because `audio-two-file-comparison` forbids aggregates. **The filtered
*properties that differ* list is refused too, and on a narrower ground than it looks**: it survives while
it has rows and fails on its empty state, where the absence of rows is itself the phrase *"the two files
match"* that capability's own scenario refuses. ADR-0026 §8 writes that out; the older requirement is
specialised, not weakened.

**One thing the ADR disagrees with, on the record.** `docs/vision.md` §7 names `NavigationSplitView`
among the marks of a native macOS app. ADR-0026 §12 declines it — a sidebar navigates a collection and
there is none — and says so rather than diverging quietly. `docs/vision.md` is not edited; if
persistence or batch ever creates a collection, that is the decision to reopen.

**The order.** R1 is the umbrella's own work (the shell), and it is merged. **Next is R2
`restructure-empty-state`, not yet opened** · then R3 Details · R4 Measurements · R5 Waveform workspace ·
R6 Spectrum workspace · R7 Inspection Overview · R8 Comparison mode · R9 responsive, accessibility and
the human pass — each its own change and its own small PR. R0 is
merged and outside the sequence. Manual validation sits on R9, not on the ADR: ADR-0026's subject is
structure, and every claim it makes is a value a test can read.

**One cosmetic defect stands, reported and not fixed.** In the paired waveform section, text overlaps
vertically — the amplitude line against the second file's attribution, and the *no audio beyond here*
sentence against the second lane's amplitude line. It was seen during ADR-0025's manual pass, answered
none of the four questions differently, and contradicts no promotion condition. Its cause is known: a
whole `WaveformSection` — drawing plus two lines of copy — is placed inside a 96 pt frame that only the
drawing fills. The waveform workspace slice is where it belongs.

**Inherited debt, untouched.** `add-two-file-technical-comparison` is still open and **ADR-0017 is
still `Proposed`**; **ADR-0016 is still `Proposed`**; the VoiceOver traversal gap they share with
ADR-0015 is inherited rather than fixed or worsened. `add-static-spectrogram-visualization` is also
open, its manual validation battery deferred by product decision.

**Minor follow-up, not a thread:** `SettledMeasurements` describes itself as applying *"the same rule
the export path already applies"*, and it does not — the two differ on `loading` and on the bandwidth
clause. Worth correcting the next time something legitimate opens that file.

---
_Last touched: 2026-08-27. Overwrite freely; empty is fine._
