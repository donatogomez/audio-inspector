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
**Focus:** nothing is in flight. The two guarantees below are integrated; the candidate next thread is
named at the end.

**What just landed, stated as a property rather than as history.** `SignalLevelMetrics` cannot publish a
value that is not a number. Every reduction is widened to `Double` *before* it is accumulated, so no
intermediate can overflow on the way to a result that was always representable — the mean and the RMS
are bounded by the largest magnitude in the input. The domain model refuses non-finite values outright,
as its two sibling value types already did, and a result that genuinely could not be described reaches
the **existing `failed` outcome** rather than a new state or a substituted number. Nothing is clamped,
and amplitudes beyond full scale are still reported, because that is a real fact about a file. The
export and `schemaVersion` 1 are semantically unchanged: the same fields, the same bytes, now
guaranteed to be numbers. Its change is merged and archived; the finiteness guarantee lives in the
`audio-signal-level-metrics` capability.

**The flow-state suites now synchronise on a happens-before rather than on timing.** They used to
release an update and wait one `Task.yield()` for another task to apply it, which guarantees nothing:
resuming a continuation makes the other task *runnable*, not *run*. The scripted actions complete the
round trip instead — `deliver` returns only once the handler has actually been called — reusing the
continuation handshake those same test classes already had. **Production was not touched**, and the
argument for the fix is a negative control rather than a count of green runs: with the acknowledgement
removed the affected tests fail, and with an extra scheduling hop inside the producer the handshake
still passes where the yield fails deterministically. That debt is closed.

**Focus: the waveform's own PCM read is the last redundant decode, and the case for removing it is now
made rather than assumed.** `share-waveform-pcm-read` is open and **ADR-0021 is written but Proposed**;
nothing is implemented. Three findings, all measured before any code, decided the design:

- **The recorded blocker was about a different shape.** Two decoding faults have no honest waveform
  error counterpart, which blocks *reimplementing the port over `AudioDecoding`*. It does not apply to
  the waveform becoming a **consumer** of the shared pass, because a consumer translates no error space
  at all. `PCMChunk`, `AudioDecoding` and `WaveformEnvelopeAccumulator` need no change — `startFrame` is
  already the absolute frame the reduction asks for. (The deferral being revisited is **ADR-0020's**,
  not ADR-0016's: that one scheduled the migration as conditional and last.)
- **Equivalence is not uniform, and the asymmetry is the platform's.** Bit-identical envelopes for WAV
  and FLAC; AAC differs in most buckets by about one ULP, because a lossy decoder does not return
  identical samples for a different read granularity. So the criterion is bit-exact for lossless and a
  justified tolerance for lossy — derived, not chosen.
- **How the samples are handed over is worth 12×.** Passing the chunk's array costs ~3.8 s where an
  `UnsafeBufferPointer` view of it costs ~0.3 s for ten minutes of stereo. Written the obvious way the
  migration would be a slowdown, so this belongs to the decision rather than to a later optimisation.

Saving once done: ~0.41 s (FLAC) and ~0.39 s (AAC) per ten-minute inspection, and almost nothing on WAV.
The riskiest part is not the fold — it is the test surface that scripts the waveform generator seam,
several of which assert an arrangement rather than a property.

**Next step:** implement group 2 (the waveform as the fourth consumer) before group 3 (retiring the
port), so the saving and the equivalence stay provable while the old path still exists to compare
against.

**Minor follow-up, not a thread:** `ImportFlowComparisonTests` has one `Task.yield()` that was never
audited in depth; same shape as the ones above, no failure ever attributed to it.

**Other open threads** (see `openspec list` for their real task counts, not restated here):
`add-static-spectrogram-visualization` (manual validation battery deferred by product decision) and
`add-two-file-technical-comparison` (one accessibility criterion open, blocked on a known VoiceOver
traversal gap shared with ADR-0015). Neither was touched this session.

---
_Last touched: 2026-08-13. Overwrite freely; empty is fine._
