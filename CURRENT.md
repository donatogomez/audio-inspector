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
**Focus:** `add-static-spectrogram-visualization` — the contract, the evidence behind it and **the whole
domain contract** are integrated; the previous documentation snapshot is published. Group 0 is closed: a
spike that anyone can re-run measured every constant before a single requirement was written, and three
of its findings changed the design rather than confirming it. **Groups 2 and 3 are complete**: the
domain holds `AudioDecoding`, `PCMStreamDescription`, `PCMChunk`, `PCMChunkDisposition`,
`AudioDecodingError`, `SpectrogramGridMapping` and `Spectrogram`; `AVFoundationAudioDecoder` implements
the port over real files with a fake beside it in `AudioInspectorTesting`. **No production STFT, no
wiring and no drawing** — `AudioInspectorAnalysis` is still empty.

**What the decoder's negative control taught, worth carrying into group 4:** clamping a read with
`min(frameLength, remaining)` makes the `frameLength` invariant *unobservable*, because a short read
only ever happens on the final read — so the clamp hides the one case that would expose a wrong bound.
The loop consumes exactly what a read reports and refuses anything beyond the declared length instead.
The same trap is worth watching for anywhere a second bound looks like prudence.

**The three questions group 2 was left to answer, answered.** The port hands each chunk to a
**synchronous, non-escaping callback without `@Sendable`**, inside one `async` call: an `AsyncSequence`
would let a consumer iterate after the security-scoped window had closed, and marking the callback
`@Sendable` would forbid the plain local accumulator every consumer of it needs. A file with no audio
yields a **valid, empty spectrogram** — `nil` stays reserved for a frame count that could not be
established, which is a different thing to tell a user. **`SpectrogramGenerating` was not created**:
composing decode → fold → finish is orchestration, and it is reconsidered in group 5 only if that
composition turns out to hold logic that does not belong in the composition root.

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

**Next step:** group 4 — the STFT and the reduction in `AudioInspectorAnalysis`, the module's first real
contents, behind a seam that now exists. Not started. One `vDSP.DiscreteFourierTransform` setup per
operation, confined; Accelerate reaches no further than this module and no Accelerate type crosses a
port.

**Carried forward, unchanged:** the waveform's accessibility debt (text sizes not evaluable on macOS as
written; the VoiceOver traversal failed and is parked for a dedicated change) keeps **ADR-0015 at
`Proposed`**. **ADR-0016 is also `Proposed`**, pending its own format matrix and manual validation. The
waveform's migration onto the shared seam is planned as the **last, conditional** group of this slice,
with an explicit stop rule that permits deferring it honestly.

---
_Last touched: 2026-08-06. Overwrite freely; empty is fine._
