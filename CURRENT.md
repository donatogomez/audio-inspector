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
**No loudness thread is open.** `add-loudness-measurement` is merged, archived, and its capability is
canonical. Two older threads remain, neither touched by it.

Integrated loudness (LUFS-I) shipped end to end and closed the chain it set out to close: **the
normative documents → the DSP → the multi-rate weighting → the one shared PCM read → the report surface
→ the JSON contract → automated and manual validation.** ADR-0022 is `Accepted`, and
`openspec/specs/audio-loudness-measurement` now carries three requirements and twelve scenarios,
promoted from the change's own delta without touching any other capability.

What the product measures is one quantity, and the record is precise about how far that claim goes: the
48 kHz coefficients are BS.1770-5's own, every other supported rate runs a derivation **this project**
performed and names as such on the wire, and no conformance, certification or platform target is
asserted anywhere. FFmpeg was, and remains, a corroborating oracle rather than a source of authority.

**Real debt that outlived the change**, none of it a thread:

- **The export chain takes a third positional optional.** Its own note called that the moment to
  introduce a container; doing it inside a feature change would have hidden a refactor. It belongs to
  whoever adds the fourth measurement, and `SourceInspectionOutcome`'s fifth payload carries the sibling
  version of the same debt.
- **`ReportJSONDTO.swift` is 415 lines against SwiftLint's 400.** SwiftLint is not one of the four gates,
  and the alternatives were splitting the wire DTOs or cutting documentation.
- **The absolute gate is not observable from outside `LoudnessAccumulator`.** Deliberate: the domain
  value was not widened to expose a DSP intermediate. The evidence lives one layer down.
- **`ImportFlowComparisonTests` has one `Task.yield()`** never audited in depth; no failure has ever been
  attributed to it.

**Open threads** (see `openspec list` for their real counts, not restated here):
`add-static-spectrogram-visualization` — manual validation battery deferred by product decision;
`add-two-file-technical-comparison` — one accessibility criterion open, blocked on a known VoiceOver
traversal gap shared with ADR-0015.

---
_Last touched: 2026-08-18. Overwrite freely; empty is fine._
