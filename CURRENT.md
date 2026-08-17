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

**Focus: `share-waveform-pcm-read`, group 3 is done — production reads a file's samples once.**
The coordinator publishes the waveform the shared pass produced and no longer owns a second read: the
generator factory, its typealias and its private helper are gone, and `AudioInspectorApp` names no
waveform-reading port at all. The update order the surface sees is unchanged — report, waveform,
spectrogram, signal levels, true peak.

- **What did change is when the waveform arrives.** It used to settle after its own read, before the
  shared pass started; now it settles with its three siblings when the one read finishes. The report
  still precedes every sample read, which is the ordering the spec protects.
- **The saving, measured against a `main` worktree** (whole inspection, ten minutes of stereo, Release,
  three rounds): 2.18 s → 1.64 s on FLAC and 2.42 s → 2.04 s on AAC. **WAV's ~0.04 s is inside the
  measurement's own spread and is not claimed as a gain** — its decode was nearly free to begin with.
- **Counting reads was not enough to protect this.** Reintroducing the legacy read left every counter
  happy, because a directly constructed adapter passes through no injected seam. The gate that actually
  failed is a source-level one, and both now live side by side.
- **Two tests were removed rather than converted**, each with a note in place: cancelling the waveform
  alone has no reachable input once there is a single read, and a test with no reachable input is green
  for the wrong reason.

**The legacy `WaveformGenerating` and its adapter are deliberately still here.** Production calls
neither; the equivalence tests use the adapter as their **oracle**, and deleting it would delete the
evidence ADR-0021's promotion rests on. They go once group 4 is closed. ADR-0021 stays **Proposed** —
its criteria name groups 4, 5 and 7, and none is finished.

**Next step:** group 4 — prove the equivalence as tasks 4.1–4.4 state it, including the deliberate
behaviour change on a file that over-reads its declared length.

**Minor follow-up, not a thread:** `ImportFlowComparisonTests` has one `Task.yield()` that was never
audited in depth; same shape as the ones above, no failure ever attributed to it.

**Other open threads** (see `openspec list` for their real task counts, not restated here):
`add-static-spectrogram-visualization` (manual validation battery deferred by product decision) and
`add-two-file-technical-comparison` (one accessibility criterion open, blocked on a known VoiceOver
traversal gap shared with ADR-0015). Neither was touched this session.

---
_Last touched: 2026-08-17. Overwrite freely; empty is fine._
