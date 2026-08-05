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
**Focus:** `add-static-spectrogram-visualization` — the contract is open, **no production code exists
yet**. Group 0 is done and versioned: a reproducible spike measured every constant before a single
requirement was written, and three of its findings changed the design rather than confirming it.

**Why this slice matters beyond the drawing:** it executes the reversal condition ADR-0015 wrote for
itself. The first FFT is the second consumer of the decoded stream, so `AudioDecoding` becomes a real
seam and `AudioInspectorAnalysis` gains its first contents — behind a seam that exists, not because a
module was waiting to be filled.

**What the spike settled, with numbers rather than convention:** the current transform API is
`vDSP.DiscreteFourierTransform` and it is **not `Sendable`**, so its setup is confined to one operation
and reused — recreating it per frame costs ten times as much. Channels must be transformed separately
and combined in the **frequency** domain; combining samples was measured to invent spectral content
that exists in no channel, which for an instrument that shows where energy stops could conceal the very
thing it is looking for. Reduction is by **maximum**, because the mean buries a short transient by
almost 9 dB. The final incomplete window is discarded rather than padded.

**What it refuses to do:** say what a cutoff means. The drawing can show that energy stops and that the
edge is abrupt; it cannot separate lossy encoding from the master or from deliberate filtering, and two
measured limits — scalloping loss and an edge uncertainty of about one reduced band — are why.
Automatic detection of lossy origin is a **separate future change**, and must carry evidence,
alternative explanations and confidence rather than a verdict.

**Next step:** group 2 — the `AudioDecoding` port and the domain models. Three questions are
deliberately left to it rather than guessed now: the port's exact shape, whether a separate
`SpectrogramGenerating` port is warranted at all, and whether a zero-frame file yields an empty model
or none.

**Carried forward, unchanged:** the waveform's accessibility debt (text sizes not evaluable on macOS as
written; the VoiceOver traversal failed and is parked for a dedicated change) keeps **ADR-0015 at
`Proposed``**. **ADR-0016 is also `Proposed`**, pending its own format matrix and manual validation. The
waveform's migration onto the shared seam is planned as the **last, conditional** group of this slice,
with an explicit stop rule that permits deferring it honestly.
---
_Last touched: 2026-08-05. Overwrite freely; empty is fine._
