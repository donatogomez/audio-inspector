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

**Focus: `share-waveform-pcm-read`, group 4 is done — the shared waveform is the file's own waveform.**
The whole `WaveformEnvelope` is compared with `==` against the legacy read of the same file, and it is
identical everywhere the contract reaches: WAV at one, two and four channels, FLAC at one and two, AIFF,
ALAC, AAC and 32-bit float WAV; silence, an impulse, opposing polarity, a peak above full scale, files
of 1, 2, 7 and 512 frames, and zero frames. Nine chunk sizes and five resolutions change nothing. Every
fixture is 44 101 frames — prime — so a short final chunk is a property of every row.

- **A peak above full scale needed a new fixture format.** Every container already here quantises to
  16-bit integer and clamps, so the rule could only be checked against the reduction in isolation. A
  32-bit float WAV round-trips 2.5 as 2.4999995, and both paths report it unclamped.
- **AAC is exact.** No tolerance was needed, confirming the correction made in group 2.
- **The over-read case has no fixture.** Measured across all six writable containers, bounded and
  unbounded: every one delivers exactly what it declares. So the deliberate difference is pinned at the
  port instead, where a misbehaving decoder is expressible, and named as an exception rather than as
  equivalence. **The policy: the declared frame count sizes the reduction and bounds the read; frames
  delivered beyond it are a fault of the read, reported as one, never trimmed away.** The legacy loop
  trimmed silently; that is recorded from its source, since no file can make it happen.

**The legacy oracle is now a judgement call, not a blocker.** Group 4 no longer needs it to produce
evidence, but it is what makes the equivalence tests compare against an *independent* implementation
rather than against the shared path itself. The recommendation written into task 3.2 is to keep it and
change the task; nothing in groups 5–8 depends on the answer. ADR-0021 stays **Proposed** — its criteria
name groups 5 and 7 as well.

**Next step:** group 5 — the five properties, each with a negative control that is reverted in full.

**Minor follow-up, not a thread:** `ImportFlowComparisonTests` has one `Task.yield()` that was never
audited in depth; same shape as the ones above, no failure ever attributed to it.

**Other open threads** (see `openspec list` for their real task counts, not restated here):
`add-static-spectrogram-visualization` (manual validation battery deferred by product decision) and
`add-two-file-technical-comparison` (one accessibility criterion open, blocked on a known VoiceOver
traversal gap shared with ADR-0015). Neither was touched this session.

---
_Last touched: 2026-08-17. Overwrite freely; empty is fine._
