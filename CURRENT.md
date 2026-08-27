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

**Focus:** nothing is in flight. What landed most recently is named below, and the candidate next
thread — with the one decision it is waiting on — is at the end.

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
and that is the point: it was a preparation, deliberately with no OpenSpec change and no ADR. Three
tests and a production harness used to reproduce that rule by hand because it was private to the view,
so a divergence would have been mirrored on both sides instead of caught; they now call the seam, and a
negative control demonstrates the divergence failing. Nothing normalised: programme bandwidth keeps the
extra clause its siblings do not have.

**Next thread (candidate, and one decision short of ready): a UX/UI redesign.** The direction is
decided at product level — an individual file is the primary action, comparison is contextual and
temporary, no history and no sidebar, and the surface becomes `Overview · Measurements · Waveform ·
Spectrum · Details` instead of one long scrolling page. **Nothing of it exists yet**: no branch, no
OpenSpec change, no ADR. Two ADRs are expected before code — section navigation as presentation state,
and comparison as a mode.

**The decision it is waiting on.** The approved Comparison Overview sketch includes a
`5 same · 3 different · 2 not comparable` summary, and that is **refused by an accepted requirement**:
`audio-two-file-comparison` forbids *"a count of differences or any other aggregate over the
comparison"*, pinned in the domain and in three suites. Either a filtered *properties that differ* list
with no count and no editorial ordering is accepted instead, or the comparison overview carries only
the two file identities and a link to the full table. Until that is settled, any spec written for the
redesign would contradict a capability already promoted.

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
