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
**Focus:** `add-true-peak-measurement`, groups 1–4 done. **A true peak can now be computed; nothing
computes one.** `TruePeakAccumulator` takes `PCMChunk`s handed to it by hand and returns a
`TruePeakMeasurement`; no decoder, no flow, no state, no interface and no export reference it, and
nothing in the app produces one.

**The two guarantees that shaped the implementation, and that any change to it must preserve.** First,
`truePeak >= samplePeak` is **structural, not clamped**: phase 0's taps are exactly `0, …, 1, …, 0`
because `sinc` is evaluated with its integer zeros used as the definition they are, so the stored
samples are already inside the set the maximum is taken over. There is no `max(samplePeak, …)` anywhere
in the file, and there must never be — it would hide a broken filter instead of failing on it. Second,
the result is **bit-exact under any chunking**, which is a stronger contract than the RMS in
`SignalLevelMetrics` can offer, and it holds because a maximum accumulates nothing.

**One number worth carrying forward.** The samples that must cross a chunk boundary are
`tapsPerPhase − 1` = **47**, not the 23 the task list first named: 23 is the left context a position
reads, and 24 more are the lookahead that holds back the last positions of a chunk. Carrying only 23
loses them, which the third negative control demonstrated by collapsing chunk independence outright.

**Performance is better than the spike predicted, not worse**: 10 min stereo costs **0.57 s in Release
and 1.06 s in Debug**, against the spike's 0.69 s and 5.24 s. The difference is that production keeps
`Float` natively and reuses its buffers where the spike converted from `Double` per chunk — the caveat
the spike report already flagged. Memory stays bounded by the chunk, never by duration.

**Next step:** group 5 — measure the **whole inspection** with three operations versus four, against the
real decode path, in Debug. Group 4's numbers are DSP only on synthesised buffers; the stop rule in
`design.md` §8 is still the escape hatch if the end-to-end figure disagrees. Only after that does group 6
wire the fourth operation in.

**ADR-0019 stays `Proposed`.** The oracle now agrees within the pinned 0.05 dB against *production*
code, which is one of its two promotion conditions; the other is a manual pass over a real surface, and
no surface exists yet.

**Other open threads** (see `openspec list` for their real task counts, not restated here):
`add-static-spectrogram-visualization` (manual validation battery deferred by product decision) and
`add-two-file-technical-comparison` (one accessibility criterion open, blocked on a known VoiceOver
traversal gap shared with ADR-0015). Neither was touched this session.

---
_Last touched: 2026-08-12. Overwrite freely; empty is fine._
