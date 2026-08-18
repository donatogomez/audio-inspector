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
**Focus: `add-loudness-measurement` — integrated loudness is now **visible and exportable**. The
capability runs end to end; what remains is validation, the ADR, and publication.**

An inspection reads the file's samples **once**, five analyses come out of that pass, and the fifth one
now has a surface and a wire form. Nothing about the other four moved: the waveform, the spectrogram,
the signal levels, the true peak and the report itself are byte-identical with and without it.

**On screen** it is a section of its own, between true peak and the spectrogram — a programme
measurement whose methodology has to travel beside it, and a row had nowhere to put one. One value, one
decimal, `LUFS`, signed, never clamped and never floored. Absence is a sentence that **names no single
cause**, because the state does not carry one and the four causes are honestly a disjunction. **No
standard is named on screen at all**: "BS.1770" beside a number reads as certification whatever sentence
surrounds it, so the methodology is stated in plain words and the full identity travels on the wire.

**The two weighting identities read identically on screen and differ in the JSON**, and that asymmetry
was the turn's one real design question. The derivation exists to reproduce the published response and
the rate-invariance is demonstrated, so the provenance does not change how the number is read — while a
caption that varied by sample rate would suggest the two numbers mean different things. It is an audit
fact, so it lives where a consumer can act on it.

**On the wire** it is `measurements.integratedLoudness`, additive, `schemaVersion` still **1**. The key
names the **quantity, not the family** — a `loudness` object carrying one `method` would imply that
method covered momentary, short-term and LRA, which this change deliberately does not ship. `value` is
the unrounded LUFS `Double`, which is the *opposite* of true peak's linear rule and deliberately so.
Absence is the key omitted, never `null`, and no cause of an absence survives to the document.

**The real path is proved at three rates.** A real file drives the real decode through the flow, the
composition root's translation and the export, at 44.1, 48 and 96 kHz — and the exported number is the
accumulator's own, with the weighting that actually ran rather than one inferred from a rate the mapper
never sees. Ten negative controls (five presentation, five export) were applied and reverted.

**New recorded debt:** the export chain now takes a **third** positional optional. Its own note called
that the moment to introduce a container; the container was not built here, because doing it while
wiring a measurement would hide one change inside another — the same reasoning
`SourceInspectionOutcome` applied to its fifth payload. It belongs to whoever adds the fourth.

ADR-0022 stays `Proposed`, now recording how this is presented and what leaves on the wire. Groups 1–5,
7 and 8 closed; **group 6 is the only implementation work left** — its cross-container oracle comparison
and production negative controls.

**Next step:** group 6, then 9.1's gates and the manual validation battery, then ADR-0022's promotion.
Nothing is pushed and no PR exists.

**Known, introduced lint warning:** `ReportJSONDTO.swift` is now 415 lines against SwiftLint's 400.
The file was clean before; the alternatives are splitting the wire DTOs across files or cutting
documentation, and neither was taken unilaterally. SwiftLint is not one of the four gates.

**Minor follow-up, not a thread:** `ImportFlowComparisonTests` has one `Task.yield()` that was never
audited in depth; same shape as the ones above, no failure ever attributed to it.

**Other open threads** (see `openspec list` for their real task counts, not restated here):
`add-static-spectrogram-visualization` (manual validation battery deferred by product decision) and
`add-two-file-technical-comparison` (one accessibility criterion open, blocked on a known VoiceOver
traversal gap shared with ADR-0015). Neither was touched this session.

---
_Last touched: 2026-08-18. Overwrite freely; empty is fine._
