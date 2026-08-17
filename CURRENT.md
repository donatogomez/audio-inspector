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
**Already integrated, so not threads:** `SignalLevelMetrics` cannot publish a value that is not a
number — every reduction widens to `Double` before it accumulates, the domain model refuses non-finite
values, and an impossible result reaches the existing `failed` outcome rather than a substituted one.
And the flow-state test suites synchronise on a happens-before instead of a `Task.yield()`, which
guarantees nothing: their scripted actions now complete the round trip. Both are merged; the first is
archived.

**Focus: `share-waveform-pcm-read`, group 2 is done — the shared pass can now produce the waveform.**
The waveform is the fourth consumer of `SharedPCMAnalysisGeneration`: same chunks, its own accumulator,
its own outcome. **The legacy `WaveformGenerating` read is still alive and is still what the user sees**,
deliberately — it is the oracle every equivalence test compares against, and retiring it is group 3's
cut, not this one's.

- **Equivalence is exact, for every format measured — including AAC.** The pre-implementation probe had
  reported AAC drifting by about one ULP and the design and ADR-0021 were written expecting a tolerance
  there. Measured against the shipped composition, at the probe's own ten-minute length and with a signal
  the encoder cannot fold together, the worst bucket error is **zero**. The hypothesis fell; the records
  were corrected rather than defended, and the tests assert exact equality.
- **Position comes from `chunk.startFrame`, not from arrival order** — proven by feeding the chunks
  backwards and getting the identical envelope.
- **Failure and absence stay the waveform's own.** An incompletely covered read fails the waveform while
  the other three settle exactly as accumulators fed the same chunks directly; a resolution the stream
  cannot be mapped to is an *absence*, never a failure. Cancellation, including a deterministic
  mid-read cancellation, cancels all four and publishes nothing partial.
- **The buffer must be borrowed, and that is now confirmed against production code**: the fold costs
  0.29–0.34 s through `withUnsafeBufferPointer` and 4.21–4.23 s through the array — ~13×, on all three
  formats.

Four negative controls discriminate: dropping `startFrame`, skipping a chunk, coupling the waveform's
failure or its absence to the others, and ignoring cancellation for it.

**Next step:** group 3 — retire the legacy read. Stop calling `makeWaveformGenerator` in the coordinator,
publish the shared waveform instead, and delete `WaveformGenerating` and its adapter. The risk there is
not the fold; it is the test surface that scripts that seam, several of which assert an arrangement
rather than a property.

**Minor follow-up, not a thread:** `ImportFlowComparisonTests` has one `Task.yield()` that was never
audited in depth; same shape as the ones above, no failure ever attributed to it.

**Other open threads** (see `openspec list` for their real task counts, not restated here):
`add-static-spectrogram-visualization` (manual validation battery deferred by product decision) and
`add-two-file-technical-comparison` (one accessibility criterion open, blocked on a known VoiceOver
traversal gap shared with ADR-0015). Neither was touched this session.

---
_Last touched: 2026-08-17. Overwrite freely; empty is fine._
