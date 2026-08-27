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

**Focus:** the redesign's shell — **R1 — is implemented** on `feat/restructure-inspection-workspace`,
a branch stacked on the documentation branch. Nothing after R1 is started. What landed most recently is
named first; the redesign and its slice order follow.

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

**R1 — the shell — is implemented, and it is only the shell.** The umbrella change
`restructure-inspection-workspace` is at **11/29**; its §2 is closed, §3 onward untouched. What exists
is `WorkspaceSection` (five cases), `WorkspaceNavigation` (the selection and the one rule that moves
it), `WorkspaceCopy` (the shell's words), and a segmented control in `RootView`. The selection lives in
the composition root's own `@State`: no domain value, no field of `ImportFlowModel` or
`ComparisonState`, no persistence, and a source assertion over `Sources/` and `App/` refuses any target
below it naming it. It moves in exactly one place — a single `.onChange` on the whole window — and only
when a **new primary report that did not fail globally** arrives. A comparison starting, settling, being
dismissed, superseded, cancelled or failing moves nobody; nor does an analysis settling, a `.working`
state, a dismissed picker, or a globally failed report. Three negative controls were seen to fail —
12 issues for a section that moves on its own, 4 for persistence, 4 for a `"3 differences"` count on the
shell's comparison surface — and all three were reverted and verified by checksum.

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

**The order.** R1 is the umbrella itself (the shell), and it is done. Next is R2 Empty · R3 Details ·
R4 Measurements · R5 Waveform workspace · R6 Spectrum workspace · R7 Inspection Overview · R8 Comparison
mode · R9 responsive, accessibility and the human pass — each its own change and its own small PR. R0 is
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
